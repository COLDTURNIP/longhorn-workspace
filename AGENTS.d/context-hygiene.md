# Context Hygiene (Detailed)

1) Identify scope first: affected repo/controller/CRD. Use `repo-navigator`, `interaction-mapper`, indices before opening files.
2) Anchor, then explore: start from anchor file; navigate with `lsp_symbols`, `lsp_find_references`, or `ast_grep`. Avoid repo-wide scans unless anchors fail.
3) Apply repo-type policy: classify as Type A/B/C (see repo/AGENTS.md) and keep changes within allowed scope.
4) Record learnings: append to `.sisyphus/notepads/<plan-name>/` (learnings/issues/decisions/problems) to reduce reloading context.
5) Keep AGENTS local: root/repo AGENTS guide agents but must remain untracked; never stage or commit them.

If root summary conflicts with this file, root summary is authoritative.
