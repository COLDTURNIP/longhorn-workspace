# Force Push Policy (Detailed)

- Default: forbid force push.
- If absolutely required (e.g., after squash), only use `git push --force-with-lease` and only to personal `origin/<feature>`.
- jj equivalent: `jj git push --force-bookmark <bookmark>` (same scope restriction applies).
- Never force push to protected branches (main/master/release).
- Warn user before force; document reason in PR notes.

If root summary conflicts, root summary is authoritative.
