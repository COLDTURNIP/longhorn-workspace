# Plan and Delegation Guidance

## Scope and Roles
- This document defines the shared expectations for planning and delegation across the workspace.
- The orchestrator, planner, and plan reviewer must read and follow this document before acting on any plan, delegation prompt, or verification request.
- Keep communications grounded in scope, cite anchors, and avoid assumptions beyond the stated task boundaries.

## Atomic Delegation
- Each delegation is exactly one file change or one verification command.
- Do not bundle code edit plus test execution in one delegation prompt.
- State the exact expected diff or command outcome.

## Plan Step Contract
- Every plan step must include these fields:
  - `Action`
  - `Target`
  - `Verify Command`
  - `Evidence Path`
  - `Done Criteria`
- Missing any field is a plan rejection.
- `Verify Command` must declare:
  - interpreter (e.g., bash, python, go)
  - entrypoint (script, binary, or command)
  - environment assumption if not default
  - single-line or heredoc form, copy-paste ready
  - expected evidence path and success/fail criteria

## Plan Executability Checklist
- Command is single-line, copy-paste ready, or valid heredoc.
- Interpreter and entrypoint are explicit (e.g., bash, python, go, etc.).
- Environment assumption is stated if non-default.
- Evidence path and expected output are clear.
- Reviewer must check runtime feasibility, not just syntax.

Notes: Do not edit `.sisyphus/plans/*` or other plan files unless you have explicit authorization to modify them.
