# Agent Interaction: Consult Timing and Precedence

## Planning Phase
During the Planning Phase, agents must consult `AGENTS.md` (root) first to ensure all workspace-wide rules and context are loaded. For engineering/build tasks, agents must then consult `repo/AGENTS.md` for repository-specific build contracts and dependency impacts. For issue/ticket/support-bundle work, agents must consult `ticket/AGENTS.md` for evidence collection and folder layout. Cross-reference to `AGENTS.d/plan-and-delegation.md` for atomic delegation and step contract rules; do not duplicate those procedures here.

## Review Phase
In the Review Phase, agents are required to review both `AGENTS.md` and the relevant subdocuments (`repo/AGENTS.md`, `ticket/AGENTS.md`, `AGENTS.d/plan-and-delegation.md`, `AGENTS.d/qa-checklist.md`) to validate that the plan aligns with workspace law and task-specific requirements. Any deviation or ambiguity must be escalated according to the guidance in `AGENTS.d/plan-and-delegation.md`.

## Coding Phase
Agents must follow the instructions and law defined in `AGENTS.md` and the relevant subdocuments during the Coding Phase. Implementation must strictly adhere to workspace and repository law, and any conflicts must be escalated as described below.

## Conflict and Precedence
If a conflict arises between `AGENTS.md` (root summary) and any `AGENTS.d` subdocument or repo/ticket-level AGENTS file, precedence is given to `AGENTS.md`. Agents must escalate unresolved conflicts to the orchestrator for resolution. Subdocuments in `AGENTS.d` provide detailed procedures, but the root summary in `AGENTS.md` is authoritative in all cases.

---

Refer to `AGENTS.d/plan-and-delegation.md` for step contract, delegation, and acceptance evidence rules. This document defines only consult timing and precedence for agent interaction.
