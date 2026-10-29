---
name: ascii-scanner
description: >
  Use before committing changes in repo/, before finalizing a commit message or
  pull request title, after generating analysis reports in ticket/, and after
  multi-file refactoring, to catch non-ASCII text and invisible, BiDi, or
  control characters (Trojan Source) that violate the ASCII-only policy.
metadata:
  version: "2.0"
  impact: High (Policy Enforcement)
  tags: ["compliance", "validation", "lint", "ascii", "trojan-source"]
---

# ASCII scanner

`ascii-checker.sh` in this folder is a copy of longhorn/longhorn
`scripts/development/ascii-checker.sh` (longhorn/longhorn#14406) with one
change: relaxed-path rules are read per git repository, so it works on files in
any `repo/*` checkout from the workspace root. It needs bash and Python 3.7+.

The workspace policy is ASCII-only, so run it in its default strict mode. Each
finding prints `file:line:col`, the Unicode name, and an ASCII replacement for
common characters. Run `bash agent-skills/ascii-scanner/ascii-checker.sh --help`
for all options.

## Run

From the workspace root, set the checker path once:

```bash
C=$PWD/agent-skills/ascii-scanner/ascii-checker.sh
```

1. Files changed in a repository: committed since the target branch, plus
   uncommitted and untracked files, without vendored code. Use the branch the
   change targets in place of `upstream/master`:

   ```bash
   (cd repo/<name> &&
     { git -c core.quotepath=off diff --name-only --diff-filter=ACMRT --merge-base upstream/master -- . ':(exclude)vendor'
       git -c core.quotepath=off ls-files --others --exclude-standard -- . ':(exclude)vendor'
     } | bash "$C" -f -)
   ```

2. Specific files, or every file below a directory, such as a `ticket/*` report
   folder or `.tmp/*` evidence:

   ```bash
   bash "$C" ticket/<folder>/analysis_report.md
   find ticket/<folder> -type f | bash "$C" -f -
   ```

3. A commit message, from a draft file or an existing revision:

   ```bash
   bash "$C" --commit-message <message-file>
   jj log -r <revision> --no-graph -T description | bash "$C" --commit-message -
   git log --format=%B%n upstream/master..HEAD | bash "$C" --commit-message -
   ```

4. A pull request title:

   ```bash
   printf '%s\n' '<title>' | bash "$C" --label "PR title" -
   ```

## Read the results

Exit status: 0 clean, 1 findings, 2 usage or I/O error.

- A finding marked "Trojan Source risk" is an invisible, BiDi, or control
  character. Delete it, and report where the text came from when it was copied
  from an issue, web page, or tool output.
- Fix every finding in lines you added or changed. For pre-existing findings in
  a file you touched, fix them when the repository enforces an ASCII check in
  CI (a workflow running `ascii-checker.sh`); otherwise report them instead of
  rewriting unrelated lines.
- Files matching a repository's relaxed list (`.ascii-checker-relaxed-paths` or
  `scripts/development/ascii-checker-relaxed-paths.txt` at its root, such as
  `CHANGELOG/**` in repo/longhorn) accept non-ASCII text but still reject
  Trojan Source characters.
- `--commit-message` accepts non-ASCII contributor names in `Signed-off-by` and
  similar identity trailers.
- Binary files and symbolic links are skipped with a warning.

Done when every command exits 0, or each remaining finding is pre-existing and
reported.

`ascii_scanner.sh` keeps the former `--execute <path>` interface for older
commands and delegates to `ascii-checker.sh`.
