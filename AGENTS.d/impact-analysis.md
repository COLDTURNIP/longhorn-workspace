# Impact Analysis

## Layered Impact (summary)
- Layer 1: types, go-common-libs → impacts helpers, engines, managers
- Layer 2: backupstore, go-iscsi-helper, go-spdk-helper, sparse-tools → impacts engines
- Layer 3: longhorn-engine, longhorn-spdk-engine → impacts instance-manager
- Layer 4: instance-manager → impacts longhorn-manager → impacts share-manager

## go.mod Replace Cleanup
- No local replace paths in PRs. If used for dev, remove before merge: `go mod tidy` then verify `go.mod`/`go.sum`.

## Downstream Checklist
- After changing lower-layer repos, note which dependents need `go.mod` bumps (manager, engine, instance-manager, etc.).

## Version Coordination
- External dep bumps or CSI sidecars → update `repo/dep-versions/versions.json`.
