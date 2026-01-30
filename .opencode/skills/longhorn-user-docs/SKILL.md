---
name: longhorn-user-docs
description: Version-aware workflow to read Longhorn user documentation from local website Markdown sources and longhorn.io/docs.
compatibility: opencode
metadata:
  repos: longhorn (website)
  doc_source_root: longhorn/website/content/docs
  url: https://longhorn.io/docs
  version_format: semver-without-v-prefix
  version_policy:
    development: latest-active-only
    troubleshooting: user-specified-or-latest
  latest_detection: semver-max-under-docs-root
  version_normalization:
    strip_v_prefix: true
    allow_major_minor_only: true
    major_minor_resolution: pick_max_micro_with_same_major_minor
  version: "1.2"
---

# Longhorn User Docs (Version-Aware)

## What I do
- Read Longhorn user documentation from local Markdown sources under `longhorn/website/content/docs`.
- Pick the correct docs version based on request intent:
  - Development: always use the latest active version.
  - Troubleshooting: use the user-provided version if present; otherwise use the latest active version.
- Normalize versions:
  - Strip `v` prefix (e.g. `v1.10.2` -> `1.10.2`).
  - Resolve `MAJOR.MINOR` (e.g. `1.10`) to `MAJOR.MINOR.<max-micro>` available in docs.

## When to use me
Use this skill when:
- You need operational guidance from Longhorn docs (installation, upgrade, settings, UI steps).
- You need troubleshooting guidance and must avoid mixing behaviors across versions.
- You need to update docs and should target the latest version docs.

Do NOT use this skill when:
- The question is about source code internals (controllers, CRDs generation, engine behavior).
- The question is about implementation details that are not documented in user docs.

## Documentation source layout

### Primary local source root
- Active versions:
  - `longhorn/website/content/docs/<version>/...`
- Archived versions:
  - `longhorn/website/content/docs/archives/<version>/...`

### Version naming
- Versions are directories like `1.11.0`, `1.10.2` (no `v` prefix).

### Common structure
- `_index.md` files define section entry points (Hugo).
- Content paths are typically lowercase with hyphens.
- Troubleshooting content usually lives under:
  - `<version>/troubleshoot/`
  - `<version>/v2-data-engine/troubleshooting.md`

## Version rules

### Step 1: Identify intent
- Development: feature behavior, docs update, recommended configuration for new work.
- Troubleshooting: incident triage, error logs, operational break/fix.

### Step 2: Determine version input
- Development:
  - Always use `<latest>`.
- Troubleshooting:
  - If the user provides a version string, use it (after normalization).
  - If not provided, use `<latest>`.

### Step 3: Normalize version (troubleshooting only, when provided)
Normalization rules:
- Strip a leading `v` (e.g. `v1.10.2` -> `1.10.2`).
- If version is `MAJOR.MINOR.PATCH`, use it as-is.
- If version is `MAJOR.MINOR` (e.g. `1.10`):
  - Resolve to `MAJOR.MINOR.<max-micro>` found under active docs.
  - If not found under active docs, try archives.

If a normalized version does not exist under both active docs and archives:
- Fall back to `<latest>` and clearly label it as fallback.

### Step 4: Latest version detection
Define `<latest>` as:
- The maximum semantic version directory directly under:
  - `longhorn/website/content/docs/`
- Ignore:
  - `archives/`
  - any non-semver entries (files or directories).

## Fallback behavior

### Troubleshooting version fallback order
1. `longhorn/website/content/docs/<normalized-user-version>/...`
2. `longhorn/website/content/docs/archives/<normalized-user-version>/...`
3. `longhorn/website/content/docs/<latest>/...` (explicitly warn this may differ)

### Development fallback order
1. `longhorn/website/content/docs/<latest>/...`

## Common operations

### List available documentation versions
Goal: identify `<latest>` and valid target versions.

Procedure:
1. Look under `longhorn/website/content/docs/`.
2. Collect directory names that match semantic version format:
   - `MAJOR.MINOR.PATCH` (digits and dots only, e.g. `1.11.0`).
3. Exclude:
   - `archives/`
   - any non-semver entries (files like `_index.md`, or directories that do not match `MAJOR.MINOR.PATCH`).
4. Sort the collected versions by semantic version order.
5. The maximum entry is `<latest>`.

Expected outcome:
- A list of active versions
- `<latest>` chosen as the semver maximum.

### Resolve a MAJOR.MINOR version to the max micro (patch)
Goal: normalize user input like `1.10` to `1.10.<max-micro>`.

Inputs:
- `user_version`: may be `v1.10.2`, `1.10.2`, or `1.10`.

Procedure:
1. Normalize prefix:
   - If `user_version` starts with `v`, strip it.
2. If `user_version` is `MAJOR.MINOR.PATCH`, use it as-is.
3. If `user_version` is `MAJOR.MINOR`:
   - Scan active versions under `docs/` and select all versions whose prefix matches `MAJOR.MINOR.`.
   - Choose the maximum `PATCH` within that set.
   - If none found under active versions, repeat the scan under `docs/archives/`.
4. If still not found:
   - Fall back to `<latest>` and label as fallback.

Example:
- Available active versions include: `1.10.0`, `1.10.1`, `1.10.2`
- User provides: `v1.10`
- Normalization:
  - strip `v` -> `1.10`
  - resolve -> `1.10.2`

### Find troubleshooting sections within a version
Goal: quickly locate the most likely troubleshooting pages.

Procedure:
- Check these paths first (if they exist):
  - `.../<version>/troubleshoot/`
  - `.../<version>/v2-data-engine/troubleshooting.md`
- Then expand by reading section `_index.md` files to discover links.

## Guardrails

### Do not mix versions
- Never combine steps, settings, or UI screenshots from different doc versions in a single answer.
- If you must compare versions, explicitly separate content by version blocks:
  - "Version A: ..."
  - "Version B: ..."
- When you detect conflicting guidance across versions:
  - prefer the selected version (exact or latest)
  - mention that other versions differ and provide the alternative as a separate note

### Always include version context in the answer
For any doc-based answer, include:
- "Docs version: <version> (<reason>)"
- "Source: longhorn/website/content/docs/<version>/..." (or `archives/<version>`)

Minimum requirement:
- At least one source path must be included per answer when the guidance is taken from docs.

### Troubleshooting default-to-latest must be explicit
If the user did not provide a version for troubleshooting:
- Always add a line:
  - "Docs version: <latest> (no user version provided; default to latest)"
- Avoid wording that implies it is an exact match to the user's environment.

### Version normalization rules are mandatory
- Always strip a leading `v` from user-provided versions.
- If the user provides `MAJOR.MINOR` only:
  - always resolve to `MAJOR.MINOR.<max-micro>` using available directories
  - do not guess micro numbers that do not exist in the docs tree

### If exact version docs are missing
When the user specifies a version but it is not found:
1. Try `docs/<version>/`
2. Try `docs/archives/<version>/`
3. Fall back to `<latest>`

In this case, always include:
- A clear fallback statement
- A warning that behaviors and UI steps may differ

### Keep answers aligned with docs scope
- Prefer procedural steps and configuration guidance that are explicitly documented.
- If the docs do not cover the needed detail:
  - say it is not documented in user docs
  - suggest what to verify (e.g. actual Longhorn version, UI state, setting values, logs)
  - avoid inventing undocumented flags or settings

## Response templates (version annotation)

### Development (always latest)
- "Docs version: <latest> (development rule: latest)"
- "Source: longhorn/website/content/docs/<latest>/..."

### Troubleshooting with user-provided version (exact)
- "Docs version: <normalized> (user-specified)"
- "Source: longhorn/website/content/docs/<normalized>/..."
- If using archives:
  - "Source: longhorn/website/content/docs/archives/<normalized>/..."

### Troubleshooting with user-provided MAJOR.MINOR (resolved)
- "Docs version: <resolved> (resolved from <major.minor>)"
- "Source: longhorn/website/content/docs/<resolved>/..."
- If resolved from archives:
  - "Source: longhorn/website/content/docs/archives/<resolved>/..."

### Troubleshooting without user version (use latest)
- "Docs version: <latest> (no user version provided; default to latest)"
- "Source: longhorn/website/content/docs/<latest>/..."

### Troubleshooting fallback to latest (not found)
- "Docs version: <latest> (fallback; requested version <normalized> not found under docs/ or archives/)"
- "Warning: behaviors and UI steps may differ across versions."
- "Source: longhorn/website/content/docs/<latest>/..."

## References
- https://longhorn.io/docs
- Local docs root: `longhorn/website/content/docs`
