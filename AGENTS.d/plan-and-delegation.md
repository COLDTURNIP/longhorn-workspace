# Plan and Delegation Guidance

## Scope and Roles
- The orchestrator, planner, and plan reviewer must read this document before acting on a plan or delegation prompt.

## Delegation Slices
- Delegate a cohesive outcome, including its implementation and verification when both are required.
- A slice must be executable by one worker without waiting for another worker; its acceptance must be independently checkable after parent integration.
- Split work by independently verifiable behavior or ownership boundary, not by individual file edits or commands.
- Every delegation prompt must explicitly allowlist the paths the worker may modify and the commands the worker may run.
- The allowlists must include everything needed to complete the slice and exclude unrelated paths and commands.
- Worker prompts must state the owning worker's design boundary and checkable acceptance criteria. The harness/orchestrator controls execution ownership, shared-tree integration, and final verification.
- In parallel work on a shared tree, workers defer validation checks until the parent has integrated all slices and runs the integrated verification.
- Keep path and command allowlists mandatory; do not add a bypass. Materially expanded scope returns to the parent for authorization before further changes.

## Plan Step Contract

For substantial implementation or handoff work, every plan step must contain
exactly these five labeled fields:
  - `Action`
  - `Target`
  - `Verify Command`
  - `Evidence Path`
  - `Done Criteria`
- `Action` states the outcome the step must produce and identifies the owning worker when delegation is used.
- `Target` is the explicit allowlist of paths the step may modify.
- `Verify Command` is a copy-paste-ready single-line command or valid heredoc. For read-only work, it may name the tool-based lookup or inspection instead; it must state any non-default environment assumptions.
- `Evidence Path` names the changed target, generated artifact, log, or `stdout/stderr` that records the result. A separate evidence file is required only when the verification command writes one.
- `Done Criteria` states the observable target state and verification result that constitute success.

Read-only investigation steps may use tool-based verification without the
substantial-work template, but must still state a checkable outcome, ownership,
and evidence sufficient to decide completion.

Reject a substantial-work step when a field is missing, the command cannot run
in the stated environment, verification writes outside `Target`, or the
evidence cannot decide `Done Criteria`.

Notes: Do not edit `.sisyphus/plans/*` or other plan files unless you have explicit authorization to modify them. Plan execution and state ownership belong to the harness; no plan step may weaken an allowlist.

