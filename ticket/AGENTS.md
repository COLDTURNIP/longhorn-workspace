# Ticket Management & Analysis Instructions (DRAFT update)

**Status**: Workspace-local. DO NOT commit.
**Scope**: All operations within the `ticket/` directory.

---

## 1. Ticket Folder Naming Standard

All folders in `ticket/` MUST be normalized to `${org}-${ticket_id}-${description}`.

**Mandatory Formatting Principles:**

1. **Ticket ID Extraction**: The numeric identifier (`ticket_id`) is the anchor of the folder name.
2. **Missing Organization**: If the folder name starts with a number (missing `org`), the `org` segment defaults to `unknown`.
    - *Example*: `1234-note` becomes `unknown-1234-note`.
3. **Missing Description**: If the folder name consists only of `org-id` or just `id`, the `description` segment defaults to `unknown`.
    - *Example*: `aaa-1234` becomes `aaa-1234-unknown`.
    - *Example*: `1234` becomes `unknown-1234-unknown`.
4. **Standard Mapping**:
    - `aaa-1234-note` -> `aaa-1234-note` (No change)

---

## 2. Internal Ticket Structure

Maintain the following structure for all tickets:

- `description.md`: Issue text and requirements.
- `logs/`: Diagnostic data landing zone.
    - `[anyname].zip` or `[anyname].tar.*`: Raw compressed bundles from user, any name allowed. Do not rename.
    - `extracted/`: Unpacked bundle content, must follow structured rules (see below).
- `analysis_report.md`: Technical analysis report.
- `repro/`: Reproduction resources.

### logs/extracted/ Organization (REQUIRED)
- Every archive file (zip, tar, etc) in `logs/` MUST be extracted into its own dedicated subdirectory in `logs/extracted/`, named after the archive file (without extension). Do NOT mix extracted content from multiple archives into one subfolder.
- Example:
    - `logs/support-prod-20260109.zip` → extract to `logs/extracted/support-prod-20260109/`
    - `logs/cluster-20260110_foo_bundle.tar.gz` → extract to `logs/extracted/cluster-20260110_foo_bundle/`
    - Always remove the archive file extension for the extract directory name.

### Example Directory Tree
```
ticket/org-10422-description/
  description.md
  logs/
    prod-bundle-20260109.zip
    old-prod-20260101.zip
    extracted/
      prod-bundle-20260109/
        resources/
        events/
      old-prod-20260101/
        ...
  analysis_report.md
  repro/
```

- Never store logs, bundle, or extracted content at the ticket root.
- Never extract anything directly into `logs/` or `logs/extracted/` without its own subfolder.
- Never merge content from separate bundles into the same extract folder.

---

## 3. Standard Ticket Analysis Workflow

### Step 1: Folder Sanitization
Before any analysis, run the sanitizer to normalize all ticket folders.
- **Invoke Skill**: `.opencode/skill/ticket-sanitizer/SKILL.md`

### Step 2: Support Bundle Processing
If there are any compressed bundles in `logs/` or referenced in `description.md`:
1. **Invoke Skill**: `.opencode/skill/support-bundle-analysis/SKILL.md`
2. **Action**: For every compressed bundle, extract to `logs/extracted/[archive_name_no_ext]/` strictly. Proceed with multi-layer diagnosis (Pod, Node, Storage, Network) referencing only within their respective extract directory.

### Step 3: Architecture & Code Alignment
- Always use skills like `repo-navigator` or `interaction-mapper` to anchor affected CRDs, controllers, and services before deep diving code.
- Perform root cause analysis using both `description.md` and extracted logs.
- Leverage specialized agents (librarian, explore) to focus on relevant areas.
- You MAY add a `notes.md` file at the ticket root to document analytical steps, interim findings, and reasoning during the investigation (optional, but RECOMMENDED for large, complex, or multi-phase tickets). For suggested structure and usage, see Section 5: "Analytical Notes (Best Practice)".


### Step 4: Documentation
- Synthesize findings into `analysis_report.md`.
- Follow the EVIDENCE-BASED ANALYSIS FORMAT below strictly.
- Attach only paths inside `logs/` or `logs/extracted/[archive]/` for any evidence reference.
- This report is used for any fix/coding action.

---

## 4. Evidence-Based Analysis Format

All `analysis_report.md` MUST follow this structure:

### I. Core Diagnostic Results
1. **Finding**: Clear statement of the anomaly or root cause.
2. **Evidence**: Direct references to log lines, code paths, function name, partial code blocks, pseudo-code, or spec violations, using relative file paths under the correct extract folder.
3. **Correlation**: Explanation of how the evidence justifies the finding.
4. **Conclusion**: Technical summary.

### II. Post-Investigation Insights (Strategic)
- **Unresolved Doubts & Risks**: Note unexplained anomalies or missing data.
- **Recommended Next Steps**: Suggest further traces, monitoring, log improvements where needed.
    - **Modification Proposal (NO CODE EDITING)**:
        * Describe the recommended logic change.
        * *Optional*: Provide **Pseudo-code** or a "Diff concept" describing the fix (e.g., "Add a check for `nil` before accessing `v.Status`").
        * *Constraint*: Do not write the actual Go code patch; describe the *intent*.
    - **Investigation Plan (If Incomplete)**:
        * List specific missing pieces of evidence.
        * Provide copy-pasteable commands for the user to gather this info.
- **Implementation Improvements**: (If confident) highlight specific logic/code patterns for improvement.

---

## 5. Analytical Notes (Best Practice)

- Use notes.md to record steps, reasoning, hypotheses, findings and cross-reference paths under logs/ or logs/extracted/.
- Template (if present):
```
## Summary
<short summary>

## Steps
<analysis stages ("extracted logs/cluster-prod-bundle.zip to logs/extracted/cluster-prod-bundle")>

## Findings
<events, facts from logs/extracted/[bundle]/...>

## Reasoning
<your logic/analysis>

## Recommendations
<future actions, follow-up investigation>
```
- Update the file as the investigation progresses.
- Every agent MUST append or update their own analytics for each significant step.
- All citations MUST use relative paths only, never absolute or OS-specific paths.

---

## 6. Forbidden Patterns
- Do not put logs, bundles, or any extracted content at the ticket root.
- Do not merge data from multiple compressed bundles into one extract directory.
- Do not create extract/, extracted/, output/, etc at the ticket root or directly underneath logs/.
- Do not rename user-provided bundle files except for technical/legal requirements.

---

