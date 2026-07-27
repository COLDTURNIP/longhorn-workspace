---
name: commit-message
description: Use when drafting, reviewing, amending, or creating a Git or Jujutsu commit message for a Longhorn workspace change. Enforces the Conventional Commit header, verified issue key as the first body line, explanatory body, and repository-required DCO signoff.
---

# Purpose

Produce a commit message that is traceable to a verified issue and conforms to the target repository's commit and DCO policy. This skill is authoritative for commit-message content; VCS-specific skills remain authoritative for Git or Jujutsu commands.

# Message contract

Use this exact layout:

```text
<type>(<optional-scope>): <description>

<verified-issue-key>

<what changed and why>

Signed-off-by: <verified name> <verified email>
```

Rules:

- Follow Conventional Commits and the target repository's commitlint configuration for the header.
- The first non-empty line after the header MUST be the verified issue key.
- Separate the header, issue key, explanatory body, and trailers with one blank line.
- Keep the header concise, imperative, and free of a trailing period.
- Explain the behavioral change and reason. Do not merely list files or repeat the header.
- Keep the complete message ASCII-only.
- For changes committed in `repo/*`, include the DCO `Signed-off-by` trailer required by `repo/AGENTS.md`.
- Outside `repo/*`, include signoff only when the applicable repository guidance requires it.
- Use a verified contributor identity. Never invent a name or email address.

# Workflow

1. Establish the commit target.
   - Identify the exact repository receiving the commit.
   - Read its applicable agent guidance and commitlint configuration.
   - Inspect the complete diff so the message covers every included change.

2. Verify the issue before drafting.
   - Prefer an issue URL explicitly supplied by the user or recorded in the ticket description.
   - Resolve the issue through `issue://<owner>/<repo>/<number>` or read the supplied GitHub URL.
   - Confirm that the issue exists and that its repository and number match the intended change.
   - Treat branch names, bookmarks, ticket folder names, and existing commit text as hints, not proof.
   - If available evidence identifies multiple issues or no issue, ask the user for the corresponding issue URL before drafting.

3. Derive the issue key from the verified issue.
   - `https://github.com/longhorn/longhorn/issues/12345` becomes `longhorn-12345`.
   - `https://github.com/rancher/suse-storage-mgmt/issues/123` becomes `suse-storage-mgmt-123`.
   - For another tracker or repository, use its documented project key. If none is documented, ask the user rather than inventing one.

4. Draft the header from the diff.
   - Select the type from the actual change and target commitlint rules, commonly `fix`, `feat`, `refactor`, `test`, `docs`, `build`, `ci`, or `chore`.
   - Use an optional scope only when it names a stable affected area such as `security`, `volume`, or `controller`.
   - Describe the primary observable change, not the ticket title or implementation mechanics.

5. Draft the body and trailer.
   - Put the verified issue key on the first non-empty body line.
   - Add a separate paragraph stating what changed and why it is correct.
   - Add the verified `Signed-off-by` trailer when required.

6. Validate before presenting or applying.
   - Confirm the header matches `<type>[optional scope]: <description>`.
   - Confirm the first non-empty body line exactly equals the verified issue key.
   - Confirm the key maps back to the verified issue URL.
   - Confirm the message describes the full diff and contains only ASCII.
   - Confirm trailer spelling, capitalization, name, and email.
   - When asked only to draft, return the message without executing a VCS command.

Completion criterion: the message can be copied verbatim, its first body line resolves to the confirmed issue, it describes the full diff, and it satisfies the target repository's signoff policy.

# Example

Verified issue: `https://github.com/longhorn/longhorn/issues/12345`

```text
fix(security): prevent unauthorized volume secret access

longhorn-12345

Authorize the request before loading the volume encryption secret.

Signed-off-by: Raphanus Lo <yunchang.lo@suse.com>
```
