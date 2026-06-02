# Build Contract (Detailed)

## Type A/B (Native Longhorn Components)
- Use the repo Makefile as the authoritative interface. Current native repos usually delegate to Docker Buildx and Dockerfile stages:
  - Build: `make build`
  - Test: `make test`
  - Validate: `make validate`
  - CI/default: `make`
  - Clean: `make clean`
- Do NOT use host `go build`/`go test` as final verification. Quick local debugging is acceptable only when followed by the repo Make target.
- Do NOT assume all repos share the same targets. Inspect the local Makefile/Dockerfile before running uncommon commands.

## Legacy Dapper Repos
- If a repo still has `.dapper` Makefile targets and `Dockerfile.dapper`, use those Make targets until that repo is migrated.
- Dapper is no longer the default assumption for native Longhorn repos.

## Type C (CSI Sidecars / Upstream)
- Do not assume native Buildx targets. Check repo Makefile or release-tools.
- Minimal patching only; prefer upstream workflows.

## UI / Integration
- `longhorn-ui`: `npm install && npm run build`; tests: `npm test`.
- `longhorn-tests`: use pytest/runner.

If root summary conflicts, root summary wins.
