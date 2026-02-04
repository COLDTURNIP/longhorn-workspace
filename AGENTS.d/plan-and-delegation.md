# Plan and Delegation Guidance

## Scope and Roles
- This document defines the shared expectations for planning and delegation across the workspace.
- The orchestrator, planner, and plan reviewer must read and follow this document before acting on any plan, delegation prompt, or verification request.
- Keep communications grounded in scope, cite anchors, and avoid assumptions beyond the stated task boundaries.

## Atomic Delegation
- Each `delegate_task` call may target exactly one file change **or** one verification command; do not mix code edits and tests in a single delegation.
- When staying atomic, describe the single expected diff or outcome so an agent can comply without refusing.
- Use the checklist before issuing a delegation:
  - One file change OR one verification command only
  - No code edit + test/verification in the same prompt
  - Explicitly state the single outcome or diff being requested

## Plan Review Clarity
- Reviewers must ensure every plan step includes:
  1. An explicit action (what to do)
  2. A target path (file plus function/section anchor when applicable)
  3. Verification evidence (how success will be confirmed)
- Plans lacking any of the above must be flagged and clarified before approval.

## Examples
- Task: Update `repo/foo/bar.md` to document the new feature section.
- Expected outcome: Only `repo/foo/bar.md` gains the new section; no other files change.
- Must not: Do not bundle tests or other files in this delegation.

Notes: Do not edit `.sisyphus/plans/*` or other plan files unless you have explicit authorization to modify them.
