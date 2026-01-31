# ASCII-Only Policy (Detailed)

## Applies To
- Source code, comments, commit messages, docs, configs, scripts, logs.

## Forbidden
- Unicode letters, emojis, smart quotes, accented characters, non-ASCII symbols.

## Verification
```bash
git diff --name-only | xargs -I {} sh -c 'grep -P -n "[^\x00-\x7F]" "{}" && exit 1 || exit 0'
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
