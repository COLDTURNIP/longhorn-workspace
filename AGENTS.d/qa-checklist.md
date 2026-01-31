# QA Checklist

Use this before declaring work finished.

## ASCII Safety
```sh
```

## Force-Push Scan (expect only force-with-lease and policy mentions)
```sh
```
Review hits; ensure defaults are forbid, and only `--force-with-lease` appears where gated.

## Shell Lint
```sh

## Build/Test Pointers (per repo type)
- Type A/B (Dapper): `make`, `make test`, `make validate`
- UI (longhorn-ui): `npm run build`, `npm test`
- CSI sidecars: use repo-specific Makefile/release-tools

## PR Prep Smoke
- See `AGENTS.d/pr-workflow.md` for dry-run rebase/push/signoff checks.
