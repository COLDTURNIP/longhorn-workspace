# Plan and Delegation Guidance

## Scope and Roles
- The orchestrator, planner, and plan reviewer must read this document before acting on a plan or delegation prompt.

## Delegation Slices
- Delegate a cohesive outcome, including its implementation and verification when both are required.
- A slice must be executable and verifiable by one worker without waiting for another worker.
- Split work by independently verifiable behavior or ownership boundary, not by individual file edits or commands.
- Every delegation prompt must explicitly allowlist the paths the worker may modify and the commands the worker may run.
- The allowlists must include everything needed to complete the slice and exclude unrelated paths and commands.

## Plan Step Contract
- Every plan step must contain exactly these five labeled fields:
  - `Action`
  - `Target`
  - `Verify Command`
  - `Evidence Path`
  - `Done Criteria`
- `Action` states the outcome the step must produce.
- `Target` is the explicit allowlist of paths the step may modify.
- `Verify Command` is a copy-paste-ready single-line command or valid heredoc. It names the interpreter and entrypoint and states any non-default environment assumptions.
- `Evidence Path` names the changed target, generated artifact, log, or `stdout/stderr` that records the result. A separate evidence file is required only when the verification command writes one.
- `Done Criteria` states the observable target state and verification result that constitute success.
- Reject a step when a field is missing, the command cannot run in the stated environment, verification writes outside `Target`, or the evidence cannot decide `Done Criteria`.

Notes: Do not edit `.sisyphus/plans/*` or other plan files unless you have explicit authorization to modify them.
