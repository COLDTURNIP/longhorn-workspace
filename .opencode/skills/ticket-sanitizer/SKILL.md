---
name: ticket-sanitizer
description: >
  Use when creating or renaming ticket folders, or when existing folders in ticket/
  do not follow the ${org}-${ticket_id}-${description} naming convention. Also use
  to initialize logs/ and repro/ subdirectories in a new ticket folder.
compatibility: opencode
metadata:
  version: "1.1"
  impact: Medium (Workflow Optimization)
  tags: ["automation", "organization", "sanitization", "naming", "initialization"]
---

# Skill: ticket-sanitizer

## Description

This skill enforces the standardized naming convention for ticket folders and prepares the internal directory structure. It also scans for potential diagnostic resources (support bundles) referenced in descriptions or present as files.

## When to Use

- Immediately after creating a new ticket folder.
- When existing ticket folders do not comply with the `${org}-${ticket_id}-${description}` format.
- To automatically initialize `logs/` and `extracted/` directories.
- To detect support bundle requirements specified in `description.md`.

## Usage

Run from the workspace root:

```bash
bash .opencode/skills/ticket-sanitizer/ticket_sanitizer.sh
```

> Note: The script now only warns (rather than failing) if the workspace git remotes are incomplete, so it can run immediately after cloning the workspace.

## Expected Outcomes

1. All folders in `@ticket/` renamed to follow lowercase `snake_case` with proper organization prefixes.
2. Standard sub-directories (`logs/`, `repro/`) created within each ticket folder.
3. Discovery of `supportbundle*.zip` or external bundle references in `description.md`.
