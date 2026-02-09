# Planning Template

Use this template when drafting execution plans for Longhorn workspace tasks.

## Plan Step Contract

Each plan step MUST include the following fields:

- Action: <single concrete action>
- Target: <single file path or command target>
- Verify Command: <single runnable command>
  - Must be executable by reviewer or automation.
  - Example for ASCII enforcement:
    bash .opencode/skills/ascii-scanner/ascii_scanner.sh --execute <path>
  - Example for YAML duplicate-key check:
    bash .opencode/commands/yaml-duplicate-key-check.sh <yaml-file> [more-yaml-files...]
- Evidence Path: <artifact path or command output location>

## Example Plan Step

- Action: Add ASCII enforcement to CI pipeline
- Target: .github/workflows/ci.yaml
- Verify Command: bash .opencode/skills/ascii-scanner/ascii_scanner.sh --execute .
- Evidence Path: evidence/ci-ascii-scan.log

## Notes
- All fields are required for every plan step.
- Verify Command must be copy-paste ready and declare any environment assumptions.
- Evidence Path must point to a reproducible artifact or output location.
- Do not reference non-existent documentation files.
