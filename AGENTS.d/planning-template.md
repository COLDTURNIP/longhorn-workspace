# Planning Template

Copy one step block for each independently verifiable outcome. Contract rules live in `AGENTS.d/plan-and-delegation.md`.

## Step

- Action: <outcome to produce>
- Target: <explicit modification allowlist>
- Verify Command: <copy-paste-ready verification command>
- Evidence Path: <changed target, artifact, log, or stdout/stderr>
- Done Criteria: <observable target state and verification result>

## Example

- Action: Align the planning template with the authoritative step contract
- Target: `AGENTS.d/planning-template.md`
- Verify Command: `python3 -c "from pathlib import Path; lines = [line for line in Path('AGENTS.d/planning-template.md').read_text().splitlines() if line.startswith('- ')]; fields = ('Action', 'Target', 'Verify Command', 'Evidence Path', 'Done Criteria'); assert tuple(line[2:].split(':', 1)[0] for line in lines) == fields * 2"`
- Evidence Path: stdout/stderr
- Done Criteria: The template and example each contain all five fields in authoritative order, and the verification command exits 0
