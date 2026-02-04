# QA Checklist

Use this before declaring work finished.

## ASCII Safety
- Repo paths: run ascii-scanner only on files under `repo/<repo-name>/` that are added/modified. Skip vendor/ and generated paths. Use diff-filter=ACM so deletions do not trigger the scanner.
- Non-repo paths: scan the specific file(s) you touched directly.
```sh
git -C "repo/<repo-name>" diff --diff-filter=ACM --name-only HEAD \
  | grep -Ev '^(vendor/|generated/|dist/|zz_generated\.)' \
  | xargs -r -I {} bash .opencode/skills/ascii-scanner/ascii_scanner.sh "repo/<repo-name>/{}"

# Example: non-repo paths
bash .opencode/skills/ascii-scanner/ascii_scanner.sh AGENTS.d/qa-checklist.md
```

## Force-Push Scan (expect only force-with-lease and policy mentions)
```sh
git push --dry-run --force-with-lease
```
Review hits; ensure defaults are forbid, and only `--force-with-lease` appears where gated.

## Shell Lint
```sh
find . -name '*.sh' -not -path './repo/*/vendor/*' -print0 | xargs -0 shellcheck
```

## Test File Review
- If you modified any existing `*_test.go`, run the `check-test-diff` skill before pushing to catch accidental mass deletions.
- Keep this checklist high-level: do not duplicate the skill's implementation details here (see `.opencode/skills/check-test-diff/SKILL.md`).
- If there are many unrelated changes in test files, stop and reduce scope before continuing.

## Build/Test Pointers (per repo type)
- Type A/B (Dapper): run `make -C repo/<repo-name> build validate test`; this invokes Dapper by default--do not run `go test`/`go build` directly.
- UI (longhorn-ui): run `npm install` when deps change, then `npm run build` and `npm test` (no Dapper).
- CSI sidecars: use each repo's Makefile/release-tools targets (e.g., build/test); avoid ad-hoc `go test`.

## PR Prep Smoke
- See `AGENTS.d/pr-workflow.md` for dry-run rebase/push/signoff checks.
- Ensure no AGENTS files are staged: `git diff --cached --name-only | grep -E '^AGENTS(\.d/|\.md$)'` should be empty.
- If you touched Go repos, confirm go.mod/go.sum are clean (no local replace; tidy if needed per repo rules).
