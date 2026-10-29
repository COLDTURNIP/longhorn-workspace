#!/usr/bin/env bash
#
# ascii-checker.sh - reject non-ASCII and invisible/control characters.
#
# Non-ASCII characters break grep-based code search and render badly in some
# terminals and log viewers. Invisible and bidirectional (BiDi) characters can
# also make source code look different to a reviewer than to a compiler or
# shell ("Trojan Source", CVE-2021-42574 and CVE-2021-42694).
#
# See usage() for the interface. Requires bash and Python 3.7+ (standard
# library only), found as python3 or python.
#
# Agent skill copy of longhorn/longhorn scripts/development/ascii-checker.sh.
# The detection rules are the same; relaxed-path patterns are read per git
# repository (see --relaxed-from) so that the script works from any location.

set -euo pipefail

# Keep the bash part portable to macOS (bash 3.2, BSD tools): no bash 4
# features, and expand arrays that may be empty as ${arr[@]+"${arr[@]}"}, since
# bash before 4.4 treats an empty "${arr[@]}" as unbound under set -u.

SCRIPT_NAME=ascii-checker.sh
# Empty when bash reads this script from stdin (curl ... | bash -s).
SCRIPT_SOURCE=${BASH_SOURCE[0]:-}

usage() {
	cat <<EOF
Usage:
  ${SCRIPT_NAME} [options] [--] FILE...
  ${SCRIPT_NAME} [options] -f LIST_FILE [-f LIST_FILE...] [FILE...]
  ${SCRIPT_NAME} [options] -

Check text for characters outside printable ASCII. Only TAB, LF, CRLF line
endings, and 0x20-0x7E are allowed.

Inputs:
  FILE...                Files to check.
  -f, --file-list FILE   Read file paths from FILE, one per line. Use "-f -"
                         to read the list from stdin (e.g. git diff --name-only).
  -                      Check the content of stdin instead of files. Must be
                         the only input.

Options:
  -d, --dangerous-only   Report only dangerous characters: BiDi controls,
                         zero-width and other default-ignorable (invisible)
                         characters, Unicode tag and variation-selector
                         smuggling, and ASCII/C1 control characters. Other
                         non-ASCII text is allowed.
  -c, --commit-message   Check commit messages: strict everywhere except
                         identity trailers (Signed-off-by, Co-authored-by, ...)
                         in paragraphs made only of trailer lines, other than
                         the subject paragraph. Those are checked with
                         --dangerous-only so that contributor names with
                         accents are accepted.
  -r, --relaxed-from F   Glob patterns of files that are checked with
                         --dangerous-only, relative to the root of the git
                         repository that contains each checked file.
                         Default: per repository, the first file found of
                         .ascii-checker-relaxed-paths and
                         scripts/development/ascii-checker-relaxed-paths.txt.
      --no-relaxed       Do not load relaxed path patterns.
  -l, --label NAME       Name used for stdin in reports (default: <stdin>).
  -h, --help             Show this help.

File names are checked with the same rules as file content. The content of
binary files (containing NUL bytes and invalid UTF-8) and symbolic links is
skipped with a warning. When GITHUB_ACTIONS=true, findings are printed as
GitHub workflow annotations.

Exit status: 0 no violations, 1 violations found, 2 usage or I/O error.

Examples:
  ${SCRIPT_NAME} README.md chart/values.yaml
  git diff --name-only --diff-filter=ACMR origin/master... | ${SCRIPT_NAME} -f -
  git log --format=%B%n origin/master..HEAD | ${SCRIPT_NAME} --commit-message -
EOF
}

usage_error() {
	echo "${SCRIPT_NAME}: $*" >&2
	echo "Try '${SCRIPT_NAME} --help' for more information." >&2
	exit 2
}

need_arg() {
	[[ $# -ge 2 ]] || usage_error "option '$1' requires an argument"
}

mode=strict
label='<stdin>'
relaxed_from=''
no_relaxed=false
stdin_content=false
list_files=()
files=()

while [[ $# -gt 0 ]]; do
	case "$1" in
	-h | --help)
		usage
		exit 0
		;;
	-f | --file-list)
		need_arg "$@"
		list_files+=("$2")
		shift 2
		;;
	-d | --dangerous-only)
		mode=dangerous
		shift
		;;
	-c | --commit-message)
		mode=commit
		shift
		;;
	-r | --relaxed-from)
		need_arg "$@"
		relaxed_from=$2
		shift 2
		;;
	--no-relaxed)
		no_relaxed=true
		shift
		;;
	-l | --label)
		need_arg "$@"
		label=$2
		shift 2
		;;
	--)
		shift
		files+=("$@")
		break
		;;
	-)
		stdin_content=true
		shift
		;;
	-?*)
		usage_error "unknown option '$1'"
		;;
	*)
		files+=("$1")
		shift
		;;
	esac
done

if [[ ${stdin_content} == true ]]; then
	if [[ ${#files[@]} -gt 0 || ${#list_files[@]} -gt 0 ]]; then
		usage_error "'-' (check stdin) cannot be combined with other inputs"
	fi
elif [[ ${#files[@]} -eq 0 && ${#list_files[@]} -eq 0 ]]; then
	usage_error "no input given"
fi

# With "curl ... | bash -s", bash reads this script from stdin, so stdin cannot
# also carry a file list or text to check. Fail instead of checking nothing.
uses_stdin=${stdin_content}
for list_file in ${list_files[@]+"${list_files[@]}"}; do
	if [[ ${list_file} == - ]]; then
		uses_stdin=true
	fi
done
if [[ ${uses_stdin} == true && -z ${SCRIPT_SOURCE} ]]; then
	usage_error "stdin is already used to read this script; run 'bash <(curl -fsSL URL) ...' instead of 'curl -fsSL URL | bash -s -- ...'"
fi
stdin_list_used=false
for list_file in ${list_files[@]+"${list_files[@]}"}; do
	if [[ ${list_file} == - ]]; then
		[[ ${stdin_list_used} == false ]] || usage_error "'-f -' can be given only once"
		stdin_list_used=true
		list_file=/dev/stdin
	elif [[ ! -f ${list_file} || ! -r ${list_file} ]]; then
		usage_error "cannot read file list '${list_file}'"
	fi
	while IFS= read -r path || [[ -n ${path} ]]; do
		[[ -n ${path} ]] && files+=("${path}")
	done <"${list_file}"
done

if [[ -n ${relaxed_from} && ! -r ${relaxed_from} ]]; then
	usage_error "cannot read relaxed path patterns '${relaxed_from}'"
fi

if [[ ${stdin_content} == false && ${#files[@]} -eq 0 ]]; then
	echo "${SCRIPT_NAME}: no files to check" >&2
	exit 0
fi

find_python() {
	local candidate
	for candidate in python3 python; do
		if command -v "${candidate}" >/dev/null 2>&1 &&
			"${candidate}" -c 'import sys; sys.exit(sys.version_info < (3, 7))' >/dev/null 2>&1; then
			echo "${candidate}"
			return 0
		fi
	done
	return 1
}

PYTHON=$(find_python) || {
	echo "${SCRIPT_NAME}: Python 3.7 or later is required (python3 or python)" >&2
	exit 2
}

read -r -d '' PY_PROG <<'PY' || true
import os
import re
import signal
import sys
import unicodedata

MODE = os.environ["AC_MODE"]
LABEL = os.environ["AC_LABEL"]
USE_STDIN = os.environ["AC_STDIN"] == "true"
RELAXED_FROM = os.environ.get("AC_RELAXED", "")
NO_RELAXED = os.environ.get("AC_NO_RELAXED", "") == "true"
RELAXED_LIST_NAMES = (
    ".ascii-checker-relaxed-paths",
    os.path.join("scripts", "development", "ascii-checker-relaxed-paths.txt"),
)
GITHUB = os.environ.get("GITHUB_ACTIONS", "") == "true"

# Keep findings and the stderr summary in order when both go to a terminal.
sys.stdout.reconfigure(line_buffering=True)

# Exit quietly when the reader goes away, e.g. when piped into head.
if hasattr(signal, "SIGPIPE"):
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

# A line made only of TAB and printable ASCII needs no further checks.
CLEAN_LINE = re.compile(rb"[\t\x20-\x7e]*")

# Unicode Default_Ignorable_Code_Point (DerivedCoreProperties.txt, Unicode
# 18.0): characters that render as nothing, including reserved code points in
# these ranges. Other format characters (category Cf) are rejected as well.
DEFAULT_IGNORABLE = (
    (0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160),
    (0x17B4, 0x17B5), (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E),
    (0x2060, 0x206F), (0x3164, 0x3164), (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF),
    (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3), (0x1D173, 0x1D17A),
    (0xE0000, 0xE0FFF),
)
LINE_SEPARATORS = {0x2028, 0x2029}

# Identity trailers whose values may hold contributor names.
IDENTITY_TRAILER = re.compile(
    rb"(?i)(?:Signed-off-by|Co-authored-by|Acked-by|Reviewed-by|Tested-by"
    rb"|Reported-by|Suggested-by|Helped-by):[ \t]"
)
# Any git trailer line ("Token: value") or a folded continuation line.
TRAILER_LINE = re.compile(rb"[A-Za-z0-9][A-Za-z0-9-]*:[ \t]|[ \t]+\S")

HINTS = {}
for cps, hint in (
    ((0x2010, 0x2011, 0x2012, 0x2013, 0x2212, 0x2500, 0x2501), "-"),
    ((0x2014, 0x2015), "--"),
    ((0x2018, 0x2019, 0x201A, 0x201B, 0x2032), "'"),
    ((0x201C, 0x201D, 0x201E, 0x201F, 0x2033), '"'),
    ((0x2502, 0x2503), "|"),
    ((0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524, 0x252C, 0x2534, 0x253C), "+"),
    ((0x2022, 0x00B7), "*"),
    ((0x2705, 0x2713, 0x2714), "yes"),
):
    for cp in cps:
        HINTS[cp] = hint
HINTS.update({
    0x00A0: " ", 0x2026: "...", 0x00D7: "x", 0x00B1: "+/-",
    0x2190: "<-", 0x2192: "->", 0x2194: "<->", 0x21D0: "<=",
    0x21D2: "=>", 0x2264: "<=", 0x2265: ">=", 0x2260: "!=",
    0x26A0: "WARNING", 0x1F517: "link",
})

# unicodedata has no names for control characters; use their Unicode aliases.
C0_NAMES = (
    "NULL", "START OF HEADING", "START OF TEXT", "END OF TEXT",
    "END OF TRANSMISSION", "ENQUIRY", "ACKNOWLEDGE", "ALERT", "BACKSPACE",
    "CHARACTER TABULATION", "LINE FEED", "LINE TABULATION", "FORM FEED",
    "CARRIAGE RETURN", "SHIFT OUT", "SHIFT IN", "DATA LINK ESCAPE",
    "DEVICE CONTROL ONE", "DEVICE CONTROL TWO", "DEVICE CONTROL THREE",
    "DEVICE CONTROL FOUR", "NEGATIVE ACKNOWLEDGE", "SYNCHRONOUS IDLE",
    "END OF TRANSMISSION BLOCK", "CANCEL", "END OF MEDIUM", "SUBSTITUTE",
    "ESCAPE", "INFORMATION SEPARATOR FOUR", "INFORMATION SEPARATOR THREE",
    "INFORMATION SEPARATOR TWO", "INFORMATION SEPARATOR ONE",
)

violations = 0
errors = 0
checked = 0


def is_variation_selector(cp):
    return 0xFE00 <= cp <= 0xFE0F


def is_dangerous(text, i):
    """Dangerous characters are rejected in every mode, including relaxed
    paths and commit message trailers."""
    cp = ord(text[i])
    if cp < 0x20:
        # ASCII control characters. CR is allowed only in a CRLF line ending,
        # which check_line() strips before scanning.
        return cp != 0x09
    if 0x7F <= cp <= 0x9F:
        return True
    if is_variation_selector(cp):
        # Allowed only directly after a non-ASCII base character, as in emoji.
        if i == 0:
            return True
        prev = ord(text[i - 1])
        return prev < 0x80 or is_variation_selector(prev)
    if cp in LINE_SEPARATORS or any(lo <= cp <= hi for lo, hi in DEFAULT_IGNORABLE):
        return True
    return unicodedata.category(text[i]) == "Cf"


def is_violation(text, i, mode):
    if mode == "strict":
        cp = ord(text[i])
        return not (cp == 0x09 or 0x20 <= cp <= 0x7E)
    return is_dangerous(text, i)


def printable(text):
    """Render text as printable ASCII so that reports never carry the
    offending characters themselves."""
    return "".join(c if 0x20 <= ord(c) <= 0x7E else "<U+%04X>" % ord(c) for c in text)


def decode_prefix(data):
    """Decode UTF-8 strictly; return the valid prefix and the offset of the
    first invalid byte (None when the whole input is valid)."""
    try:
        return data.decode("utf-8"), None
    except UnicodeDecodeError as e:
        return data[:e.start].decode("utf-8"), e.start


def display_name(name):
    """File names and labels arrive as OS strings: decode what is valid UTF-8
    and show any remaining bytes in hex."""
    data = os.fsencode(name)
    text, bad = decode_prefix(data)
    rest = data[bad:] if bad is not None else b""
    return printable(text) + "".join(
        chr(b) if 0x20 <= b <= 0x7E else "<0x%02X>" % b for b in rest
    )


def gh_escape(text, is_property=False):
    text = text.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
    if is_property:
        text = text.replace(":", "%3A").replace(",", "%2C")
    return text


def report(level, name, is_file, line, col, msg):
    where = display_name(name) + (":%d:%d" % (line, col) if line is not None else "")
    if GITHUB:
        props = ["title=" + gh_escape("ASCII check", True)]
        if is_file:
            props.append("file=" + gh_escape(display_name(name), True))
            if line is not None:
                props += ["line=%d" % line, "col=%d" % col]
        print("::%s %s::%s" % (level, ",".join(props), gh_escape("%s: %s" % (where, msg))))
    elif level == "error":
        print("%s: %s" % (where, msg))
    else:
        print("%s: %s: %s" % (where, level, msg), file=sys.stderr)


def excerpt(text, col):
    start = col - 60 if col > 60 else 0
    piece = text[start:start + 140]
    more = len(text) > start + 140
    return "    | %s%s%s" % ("..." if start else "", printable(piece), "..." if more else "")


def char_name(cp):
    if cp < 0x20:
        return C0_NAMES[cp]
    if cp == 0x7F:
        return "DELETE"
    if 0x80 <= cp <= 0x9F:
        return "C1 CONTROL CHARACTER"
    return unicodedata.name(chr(cp), "UNNAMED CHARACTER")


def describe(cp, dangerous):
    desc = "U+%04X %s" % (cp, char_name(cp))
    if dangerous:
        return desc + ": invisible, BiDi, or control character (Trojan Source risk); remove it"
    msg = desc + ": non-ASCII character"
    if cp in HINTS:
        quote = "'" if '"' in HINTS[cp] else '"'
        msg += "; use %s%s%s instead" % (quote, HINTS[cp], quote)
    return msg


def check_name(path, mode):
    """A file name is part of the change too: check it with the same rules as
    the file content, reporting each offending character once."""
    global violations
    data = os.fsencode(path)
    text, bad = decode_prefix(data)
    found = 0
    if bad is not None:
        report("error", path, True, None, None,
               "file name has invalid UTF-8 byte sequence starting with byte 0x%02X" % data[bad])
        found += 1
    seen = set()
    for i, c in enumerate(text):
        if not is_violation(text, i, mode) or ord(c) in seen:
            continue
        seen.add(ord(c))
        dangerous = mode != "strict" or is_dangerous(text, i)
        report("error", path, True, None, None, "file name: " + describe(ord(c), dangerous))
        found += 1
    violations += found


def check_line(name, is_file, lineno, data, mode):
    global violations
    # Allow a CRLF line ending; any other CR is reported as a control character.
    if data.endswith(b"\r\n"):
        data = data[:-2]
    elif data.endswith(b"\n"):
        data = data[:-1]
    if CLEAN_LINE.fullmatch(data):
        return

    text, bad = decode_prefix(data)
    found = 0
    if bad is not None:
        report("error", name, is_file, lineno, len(text) + 1,
               "invalid UTF-8 byte sequence starting with byte 0x%02X" % data[bad])
        found += 1

    # Collapse runs of the same character into one finding: [cp, col, len, dangerous].
    runs = []
    for i, c in enumerate(text):
        if not is_violation(text, i, mode):
            continue
        cp = ord(c)
        if runs and runs[-1][0] == cp and runs[-1][1] - 1 + runs[-1][2] == i:
            runs[-1][2] += 1
            continue
        runs.append([cp, i + 1, 1, mode != "strict" or is_dangerous(text, i)])
    for cp, col, length, dangerous in runs:
        msg = describe(cp, dangerous)
        if length > 1:
            msg += " (x%d)" % length
        report("error", name, is_file, lineno, col, msg)
        found += 1

    if found:
        print(excerpt(text, runs[0][1] if runs else len(text) + 1))
        violations += found


def relaxed_trailer_lines(lines):
    """Return the indexes of identity trailer lines that may hold non-ASCII
    contributor names: those in a paragraph made only of trailer lines, other
    than the first (subject) paragraph. Besides the final trailer block, this
    covers the per-commit sign-offs that squashing leaves in the body; an
    identity-like line inside prose stays strict."""
    relaxed = set()
    start = None
    seen_paragraph = False
    for index, line in enumerate(lines + [b""]):
        if line.strip():
            if start is None:
                start = index
            continue
        if start is None:
            continue
        paragraph = range(start, index)
        if seen_paragraph and all(TRAILER_LINE.match(lines[i]) for i in paragraph):
            relaxed.update(i for i in paragraph if IDENTITY_TRAILER.match(lines[i]))
        seen_paragraph = True
        start = None
    return relaxed


def check_stream(stream, name, is_file, mode):
    global checked
    if mode == "commit":
        lines = stream.readlines()
        relaxed = relaxed_trailer_lines(lines)
        for index, line in enumerate(lines):
            check_line(name, is_file, index + 1, line, "dangerous" if index in relaxed else "strict")
    else:
        for lineno, line in enumerate(stream, 1):
            check_line(name, is_file, lineno, line, mode)
    checked += 1


def glob_to_re(glob):
    glob = glob.lstrip("/")
    if glob.endswith("/"):
        glob += "**"
    parts = []
    for token in re.findall(r"\*\*/|\*\*|\*|\?|[^*?]+", glob):
        if token == "**/":
            parts.append("(?:.*/)?")
        elif token == "**":
            parts.append(".*")
        elif token == "*":
            parts.append("[^/]*")
        elif token == "?":
            parts.append("[^/]")
        else:
            parts.append(re.escape(token))
    return re.compile("".join(parts) + r"\Z")


def load_patterns(list_path):
    patterns = []
    with open(list_path, encoding="utf-8") as lines:
        for pattern in lines:
            pattern = pattern.strip()
            if pattern and not pattern.startswith("#"):
                patterns.append(glob_to_re(pattern))
    return patterns


EXPLICIT_RELAXED = load_patterns(RELAXED_FROM) if RELAXED_FROM else None
_root_cache = {}
_relaxed_cache = {}


def repo_root(directory):
    """Return the nearest directory at or above directory that holds .git (a
    directory, or a file in worktrees and submodules), or None."""
    seen = []
    root = None
    while True:
        if directory in _root_cache:
            root = _root_cache[directory]
            break
        seen.append(directory)
        if os.path.exists(os.path.join(directory, ".git")):
            root = directory
            break
        parent = os.path.dirname(directory)
        if parent == directory:
            break
        directory = parent
    for d in seen:
        _root_cache[d] = root
    return root


def relaxed_patterns(root):
    if root not in _relaxed_cache:
        patterns = []
        for name in RELAXED_LIST_NAMES:
            candidate = os.path.join(root, name)
            if os.path.isfile(candidate):
                patterns = load_patterns(candidate)
                break
        _relaxed_cache[root] = patterns
    return _relaxed_cache[root]


def is_relaxed(path):
    if NO_RELAXED:
        return False
    absolute = os.path.abspath(path)
    root = repo_root(os.path.dirname(absolute))
    if root is None:
        return False
    patterns = EXPLICIT_RELAXED if EXPLICIT_RELAXED is not None else relaxed_patterns(root)
    if not patterns:
        return False
    rel = os.path.relpath(absolute, root).replace(os.sep, "/")
    return any(pattern.match(rel) for pattern in patterns)


def is_binary(path):
    with open(path, "rb") as fh:
        data = fh.read()
    if b"\0" not in data[:8000]:
        return False
    return decode_prefix(data)[1] is not None


if USE_STDIN:
    check_stream(sys.stdin.buffer, LABEL, False, MODE)
else:
    for path in sys.argv[1:]:
        path_relaxed = MODE == "dangerous" or is_relaxed(path)
        check_name(path, "dangerous" if path_relaxed else "strict")
        if os.path.islink(path):
            report("warning", path, True, None, None, "skipped (symbolic link)")
            continue
        if os.path.isdir(path):
            report("error", path, False, None, None, "is a directory")
            errors += 1
            continue
        try:
            fh = open(path, "rb")
        except OSError as e:
            report("error", path, False, None, None, "cannot open: %s" % e.strerror)
            errors += 1
            continue
        with fh:
            if is_binary(path):
                report("warning", path, True, None, None, "skipped (binary file)")
                continue
            input_mode = "dangerous" if MODE == "strict" and path_relaxed else MODE
            check_stream(fh, path, True, input_mode)

summary = "ascii-checker: %d input(s) checked, %d violation(s)" % (checked, violations)
if errors:
    summary += ", %d error(s)" % errors
print(summary, file=sys.stderr)
sys.exit(2 if errors else 1 if violations else 0)
PY

export AC_MODE=${mode}
export AC_LABEL=${label}
export AC_STDIN=${stdin_content}
export AC_RELAXED=${relaxed_from}
export AC_NO_RELAXED=${no_relaxed}

# -I (isolated mode) keeps PYTHON* variables, user site-packages, and modules
# in the current directory out of the checker.
if [[ ${stdin_content} == true ]]; then
	exec "${PYTHON}" -I -c "${PY_PROG}"
fi
exec "${PYTHON}" -I -c "${PY_PROG}" "${files[@]}"
