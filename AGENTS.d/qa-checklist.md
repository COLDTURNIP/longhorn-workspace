# QA Checklist

Use this before declaring work finished.

## ASCII Safety
- All ascii-scanner runs must use enforcing mode: add `--execute` to every invocation. Do not use dry-run for acceptance.
- Repo paths: run ascii-scanner only on files under `repo/<repo-name>/` that are added/modified. Skip vendor/ and generated paths. Use diff-filter=ACM so deletions do not trigger the scanner.
- Non-repo paths: scan the specific file(s) you touched directly.
```sh
# Repo paths (jj-first for workspace root; subrepos always use git)
# For subrepos under repo/<repo-name>/ (always git):
git -C "repo/<repo-name>" diff --diff-filter=ACM --name-only HEAD \
  | grep -Ev '^(vendor/|generated/|dist/|zz_generated\.)' \
  | xargs -r -I {} bash .opencode/skills/ascii-scanner/ascii_scanner.sh --execute "repo/<repo-name>/{}"

# For workspace-root files (jj-first):
if test -d .jj && command -v jj >/dev/null 2>&1; then
  jj diff --summary | grep -v '^D ' | cut -d' ' -f2-
else
  git diff --diff-filter=ACM --name-only HEAD
fi | xargs -r -I {} bash .opencode/skills/ascii-scanner/ascii_scanner.sh --execute "{}"

# Example: non-repo paths
bash .opencode/skills/ascii-scanner/ascii_scanner.sh --execute AGENTS.d/qa-checklist.md
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
- Type A/B native repos: run `make -C repo/<repo-name> build validate test`; current native repos usually invoke Docker Buildx/Dockerfile stages. Do not treat host `go test`/`go build` as final verification.
- Legacy Dapper repos: if the repo Makefile still uses `.dapper` and `Dockerfile.dapper`, follow that repo's Makefile.
- UI (longhorn-ui): run `npm install` when deps change, then `npm run build` and `npm test`.
- CSI sidecars: use each repo's Makefile/release-tools targets (e.g., build/test); avoid ad-hoc `go test`.

## PR Prep Smoke
- See `AGENTS.d/pr-workflow.md` for dry-run rebase/push/signoff checks.
- Ensure no AGENTS files are about to be committed:
  - git: `git diff --cached --name-only | grep -E '^AGENTS(\.d/|\.md$)'` should be empty.
  - jj: `jj diff --summary | cut -d' ' -f2- | grep -E '^AGENTS(\.d/|\.md$)'` should be empty. jj has no staging area; all tracked changes go into the next commit.
- If you touched Go repos, confirm go.mod/go.sum are clean (no local replace; tidy if needed per repo rules).

## YAML Duplicate-Key Gate
- Default policy: duplicate-key is forbidden.
- If YAML files are changed, you must check for duplicate keys before completion.
- Canonical command:
  ```sh
  bash .opencode/commands/yaml-duplicate-key-check.sh <yaml-file> [more-yaml-files...]
  ```
- If duplicate keys are required, document rationale, file/path scope, and checker output as evidence.
