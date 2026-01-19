---
name: ticket-sanitizer
description: Enforces standardized naming conventions (${org}-${ticket_id}-${description}) and initializes directory structures for ticket folders to ensure consistent task tracking.
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
bash .opencode/skill/ticket-sanitizer/ticket_sanitizer.sh
```

## Expected Outcomes

1. All folders in `@ticket/` renamed to follow lowercase `snake_case` with proper organization prefixes.
2. Standard sub-directories (`logs/`, `repro/`) created within each ticket folder.
3. Discovery of `supportbundle*.zip` or external bundle references in `description.md`.
