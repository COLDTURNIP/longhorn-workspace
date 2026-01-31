# AGENTS Subdocs Index

This directory holds detailed guidance referenced by the root `AGENTS.md`. The root file is the authoritative summary; if conflict arises, root wins. These subdocs provide expanded procedures and examples.

## Contents

- `pr-workflow.md` — PR preparation, rebase/squash/signoff, push policies, verification commands
- `qa-checklist.md` — ASCII scan, force-push scan, bash/shellcheck lint, build/test pointers
- `impact-analysis.md` — Dependency/layer impacts, go.mod replace cleanup, force/avoid duplicates
- `crd-helm.md` — CRD generation and Helm sync flow
- `context-hygiene.md` — Detailed anchor-first navigation guidance
- `build-contract.md` — Build/test contract per repo type
- `ascii-policy.md` — ASCII-only rules and examples

All paths are workspace-relative. Keep subdocs ASCII-only.
