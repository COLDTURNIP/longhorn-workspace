# Ticket Subtree Router

This file is authoritative for ticket layout and archive extraction under
`ticket/*`. Apply these invariants to every ticket directory.

## Ticket layout

Every ticket contains `description.md`: the problem description and
requirements.

Analysis tickets add:

- `logs/`: source archives and diagnostic material.
- `logs/extracted/`: extracted archive contents.
- `analysis_report.md`: the evidence-based analysis.
- `repro/`: reproduction resources.

The engineering skills add these when they need them, as described in
`docs/agents/issue-tracker.md`:

- `spec.md`: the spec.
- `issues/<NN>-<slug>.md`: one implementation or decision ticket per file.
- `map.md`: the wayfinder map.
- `research/<name>.md`: research notes.
- `drafts/<NN>-<slug>.md`: text for the user to post on GitHub.

A ticket with work in progress keeps `STATUS.md`, the first file a resuming
agent reads:

```markdown
# Status: <ticket folder>

Updated: <UTC time>
Last upstream check: <UTC time>
Tracked: longhorn/longhorn#<issue> longhorn/<repository>#<pr> ...

## Current state
## Next steps
## Live documents
```

- **Current state**: heads, PRs, merge state, verification results, decisions.
- **Next steps**: what is waiting, and on whom.
- **Live documents**: `path: purpose` for each file that is still current;
  older files stay in place as history.

Update `STATUS.md` at each milestone: a push, a verification result, a user
decision, an upstream change. `scripts/gh-activity.sh --status` reads its
`Tracked:` and `Last upstream check:` lines.

Every archive in `logs/` MUST have its own extraction directory at
`logs/extracted/<archive-name>/`. Here, `<archive-name>` is the archive
filename without its extension. Keep each archive's contents in its own
directory: bundles MUST NOT be merged, and extracted content MUST NOT be
placed directly in `logs/` or `logs/extracted/`.

## Description and analysis

A problem description is mandatory. Under `ticket/*`, use `description.md`
when it is present; ask for a description only when that file is absent or
insufficient.

`analysis_report.md` records, at minimum, **Finding**, **Evidence**,
**Correlation**, **Conclusion**, **Risks**, and **Next Steps**. Every evidence
citation MUST use a workspace-relative path. Analysis may propose changes or
describe intended fixes, but it MUST NOT implement code.

## Route specialized work

Use `skill://ticket-sanitizer` for ticket-folder naming and normalization
mechanics; keep those rules out of this router.

Use `skill://support-bundle-analysis` for support-bundle diagnosis mechanics.
Under `ticket/*`, it MUST follow this file's
`logs/extracted/<archive-name>/` location. Outside `ticket/*`, an explicit
destination or an already extracted location is sufficient; ask only when
neither is available.

For architecture and code alignment, use `skill://repo-navigator` when locating
code across repositories. Use `skill://interaction-mapper` for CRD, proto, or
controller relationships, or for Manager-to-Instance-Manager flows. Use both
only when both trigger sets apply; otherwise use only the skill matching its
trigger.
