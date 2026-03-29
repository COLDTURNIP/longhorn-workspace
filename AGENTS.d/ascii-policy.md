# ASCII-Only Policy (Detailed)

## Applies To
- Source code, comments, commit messages, docs, configs, scripts, logs.

## Forbidden
- Unicode letters, emojis, smart quotes, accented characters, non-ASCII symbols.

## Verification
```bash
# jj-first: detect changed files, then scan
if test -d .jj && command -v jj >/dev/null 2>&1; then
  jj diff --summary | grep -v '^D ' | cut -d' ' -f2-
else
  git diff --diff-filter=ACM --name-only HEAD
fi | xargs -I {} sh -c 'grep -P -n "[^\x00-\x7F]" "{}" && exit 1 || exit 0'
```

## Examples
- Correct:
```go
fmt.Println("hello world")
```
- Incorrect:
```go
fmt.Println("<non-ASCII>")
```

If root summary conflicts, root summary is authoritative.
