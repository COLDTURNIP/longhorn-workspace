---
name: ticket-cleanup
description: >
  Use when asked to preview or delete outdated local ticket/ entries to reclaim
  disk space. Checks Longhorn GitHub issue status and recursive local inactivity
  before selecting entries for permanent deletion.
---

# Ticket cleanup

Use the bundled [ticket_cleanup.sh](ticket_cleanup.sh) as the implementation.
Run it only for an explicit cleanup request; designing or installing this skill
is not authorization to remove existing tickets.

## Workflow

1. Establish the ticket root and requested inactivity period. Default to the
   current workspace's `ticket/` and `90 days`; use the user's override when
   provided. Run `bash <skill-directory>/ticket_cleanup.sh --help` for supported
   arguments and prerequisites. Check GitHub authentication with
   `gh auth status --hostname github.com` if lookups fail.
2. Run a preview from the workspace root or a directory inside the workspace:

   ```bash
   bash agent-skills/ticket-cleanup/ticket_cleanup.sh --dry-run
   # Example override:
   bash agent-skills/ticket-cleanup/ticket_cleanup.sh --older-than '90 days' --dry-run
   ```

   These examples use the authoritative project source. When using an installed
   skill, substitute the script next to the loaded `SKILL.md`. Review every
   `WOULD_DELETE` entry and any `ERROR` lines before proceeding. Completion means
   the candidate list, cutoff, and failed checks are known, not that disk space
   has been reclaimed.
3. Present the candidates and obtain approval for permanent deletion at that
   root and age, unless the user already explicitly authorized that scope. Stop
   ticket writers and unmount anything inside the selected trees. Repeat the
   same invocation with `--delete` instead of `--dry-run` only after approval:

   ```bash
   bash agent-skills/ticket-cleanup/ticket_cleanup.sh --older-than '90 days' --delete
   ```

   The script rechecks GitHub status and recursive local timestamps immediately
   before each deletion. It does not consume a saved preview or make an atomic
   snapshot: the selection can change between runs. If approval is for an exact
   path list rather than the root/age policy, stop and reconcile any new
   candidates before deleting. Do not run concurrently with ticket updates.
4. Report the cutoff, deleted or would-delete paths, summary, and exit status.
   Exit 1 means some checks or removals failed; valid candidates may already
   have been removed. Inspect partial failures rather than broadening deletion.

## Selection and retention

- Only immediate files or directories whose names start with
  `^(longhorn|lh)[-_]([0-9]+)[-_]` are considered. Both prefixes map exclusively
  to issues at `https://github.com/longhorn/longhorn/issues/<number>`; mixed dash
  and underscore separators are accepted. Other names are untouched.
- A GitHub issue must be explicitly `closed`. Open issues, pull requests,
  missing issues, authentication/rate-limit/network failures, and unexpected
  responses are retained. GitHub operations are read-only.
- Inactivity is based on the newest **mtime** in the entire local tree,
  including the top-level entry, hidden descendants, directories, and symlinks
  themselves. This captures ordinary additions and removals as well as file
  edits; checking only the ticket directory or `description.md` is insufficient.
  Every timestamp must be strictly before the printed cutoff. The issue's
  closure time, access time, and Git history are not used.
- Default age is 90 elapsed days. UTC relative dates follow GNU `date`
  semantics; month and year overrides use calendar arithmetic, including
  end-of-month normalization.
- Top-level symlinks and special files are retained. Descendant symlinks are
  never followed; deleting a qualifying directory unlinks those symlinks but
  does not delete their targets. Unreadable trees and different-device subtrees
  fail closed. Same-device bind mounts are not detected, so unmount before use.
- Deletion is irreversible `rm`, including reports, reproduction resources,
  archives, and extracted logs. Back up material that must survive. Local checks
  and deletion are not atomic, even with the final rechecks.

## Offline verification

```bash
bash -n agent-skills/ticket-cleanup/ticket_cleanup.sh
bash agent-skills/ticket-cleanup/tests/test_ticket_cleanup.sh
```

Tests use a fake `gh` and temporary ticket trees; no real tickets or GitHub
resources are modified. Install the skill from its authoritative source with:

```bash
npx skills add ./agent-skills --skill ticket-cleanup
```
