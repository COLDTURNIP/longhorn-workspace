# Ticket Management & Analysis Instructions

**Status**: Workspace-local. DO NOT commit.
**Scope**: All operations within the `ticket/` directory.

---

## 1. Ticket Folder Naming Standard

All folders in `ticket/` MUST be normalized to `${org}-${ticket_id}-${description}`.

### Mandatory Formatting Principles:

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
    - `supportbundle*.zip`: Raw compressed bundle.
    - `extracted/`: Unzipped bundle content.
- `analysis_report.md`: Technical analysis report.
- `repro/`: Reproduction resources.

---

## 3. Standard Ticket Analysis Workflow

### Step 1: Mandatory Sanitization
Before any analysis, run the sanitizer to normalize all ticket folders.
- **Invoke Skill**: Load `.opencode/skill/ticket-sanitizer/SKILL.md`.

### Step 2: Support Bundle Processing
If any `supportbundle*.zip` exists in `logs/` or is referenced in `description.md`:
1. **Invoke Skill**: Load `.opencode/skill/support-bundle-analysis/SKILL.md`.
2. **Action**: Extract data into `logs/extracted/` and proceed with multi-layer diagnosis (Pod, Node, Storage, Network).

### Step 3: Architecture & Code Alignment

Note: All architecture navigation (such as repo-navigator/interaction-mapper skill) is a workspace-wide engineering investigation standard. You should always apply this approach first during incident investigation, design, refactor, and debugging. See detailed guidelines and examples in the workspace root AGENTS.md.

1. **Root Cause Analysis**: Analyze the problem based on `description.md` and extracted logs to identify the failure point.

2. **Architectural Anchoring**:
   - **Primary Action**: Invoke the `repo-navigator` skill to map architectural relationships (CRDs, controllers, or service clients) related to the issue.
   - **Goal**: Establish technical context before diving into implementation details.

3. **Expert-Led Investigation**:
   - **Policy**: Prioritize collaboration over broad code scanning. Leverage specialized agents (e.g., `librarian` for definitions, `explore` for call-chains) to narrow down relevant areas.
   - **Efficiency**: Use agent-provided entry points to focus your direct code reading, minimizing unnecessary context bloating.

### Step 4: Analysis Report Generation

- **Action**: Synthesize findings into `analysis_report.md`.
- **Constraint**: You MUST strictly follow the **Evidence-Based Analysis** format defined in Section 4.
- **Persistence**: This report serves as the authoritative context for the subsequent "Coding/Fixing" phase.

---

## 4. Evidence-Based Analysis Format

All `analysis_report.md` files MUST adhere to the following structure:

### I. Core Diagnostic Results
1. **Finding**: A clear statement of the identified anomaly or root cause.
2. **Evidence**: Direct references to specific log lines, code paths, or behavioral spec violations.
3. **Correlation**: A logical explanation of how the evidence leads to the finding.
4. **Conclusion**: The definitive technical summary.

### II. Post-Investigation Insights (Strategic)
**The Agent must provide the following forward-looking perspectives:**

- **Unresolved Doubts & Risks**:
    - List any unexplained anomalies or lingering questions discovered during the investigation.
    - Highlight potential side effects or areas where data was insufficient for full certainty.
- **Recommended Next Steps**:
    - Suggest specific areas for further tracing or monitoring if the issue persists or recurs.
    - Propose additional data collection needs (e.g., "Add trace-level logging to the engine state machine").
- **Implementation Improvements**:
    - If you have **high confidence**, identify specific code segments or logic patterns that could be refactored or improved to prevent similar issues.
    - Focus on enhancing system resilience, readability, or architectural alignment.
