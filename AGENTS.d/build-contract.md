# Build Contract (Detailed)

## Type A/B (Native Longhorn Components)
- Use Dapper via Make targets:
  - Build: `make`
  - Test: `make test`
  - Validate: `make validate`
  - Clean: `make clean`
- Do NOT run `go build`/`go test` directly on host.

## Type C (CSI Sidecars / Upstream)
- Do not assume Dapper. Check repo Makefile or release-tools.
- Minimal patching only; prefer upstream workflows.

## UI / Integration
- `longhorn-ui`: `npm install && npm run build`; tests: `npm test`.
- `longhorn-tests`: use pytest/runner.

If root summary conflicts, root summary wins.
