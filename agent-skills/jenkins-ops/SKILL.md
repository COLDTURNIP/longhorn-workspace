---
name: jenkins-ops
description: Use when a Longhorn developer asks to list, trigger, monitor, inspect, diagnose, or access hosts for the approved Jenkins integration-test jobs.
---

# Jenkins Operations

Use only `agent-skills/jenkins-ops/scripts/` for Jenkins HTTP operations and job-host SSH. The wrappers enforce the allowlist, live parameter metadata, private evidence, bounded diagnosis, and controlled access.

## Non-negotiables

- Never replace a wrapper with ad-hoc `curl`, a guessed Jenkins URL or host, direct `ssh`, or `eval`.
- Never contact `longhorn-e2e-test-pull-request-check`.
- Never print, paste, or persist credentials, `.env` values, public keys, or identity data. Never modify `.env`. Capture and read wrapper-returned private files locally when required, but never disclose their paths, IP addresses, or raw contents in chat or logs.
- Read-only wrappers may run directly. Mutation requires an explicit user trigger request and `trigger_job.sh --execute`.
- A trigger is trigger-and-forget. After enqueueing, stop. Monitoring, inspection, artifact download, host waiting, and SSH each require a separate request.
- Keep all temporary files private. Report conclusions and bounded excerpts, not raw evidence.

## Approved Jobs

| Alias | Jenkins path | Pipeline | Test source |
|---|---|---|---|
| `regression` | `private/longhorn-tests-regression` | `repo/longhorn-tests/test_framework/Jenkinsfile` | PyTest runs from `LONGHORN_TESTS_CUSTOM_IMAGE`; checkout and test-image revisions may differ. |
| `e2e` | `private/longhorn-e2e-test` | `repo/longhorn-tests/pipelines/e2e/Jenkinsfile` | Robot Framework runs from `LONGHORN_TESTS_CUSTOM_IMAGE`; checkout and test-image revisions may differ. |
| `benchmark` | `private/longhorn-benchmark-test` | `repo/longhorn-tests/benchmark_test/Jenkinsfile` | The setup uses the checkout and checked-in kbench manifests; no structured report or archived artifact is published. |

The aliases are exhaustive and ordered: `regression`, `e2e`, `benchmark`.

The e2e pipeline coerces effective `RUN_V2_TEST=false` to true. The wrapper rejects an explicit false override or an omitted live false default with exit 2:

`Current pipelines/e2e/Jenkinsfile coerces RUN_V2_TEST=false to true; this wrapper refuses that effective value.`

## Environment and Managed Overrides

Jenkins wrappers read `JENKINS_URL`, `JENKINS_USER`, and `JENKINS_TOKEN` from the process environment. Scripts never source `.env`.

Optional variables:

- `JENKINS_NOTIFY_SLACK_CHANNEL`: when nonempty, `trigger_job.sh` forces live `SEND_SLACK_NOTIFICATION=true` and `NOTIFY_SLACK_CHANNEL` overrides. Callers must not pass either managed parameter. Unset or empty preserves Jenkins defaults.
- `JENKINS_SSH_PUBLIC_KEY`: fallback path to a readable, regular, nonempty public-key file. The loader safely expands a leading `~/` against `HOME`; `~user` is rejected.
- `JENKINS_SSH_IDENTITY_FILE` and `JENKINS_SSH_USER`: required only by `ssh_job_host.sh`. The identity must resolve to a readable regular file; the wrapper safely expands a leading `~/`, and absolute paths are accepted.

`CUSTOM_SSH_PUBLIC_KEY` is governed by live parameter metadata:

| Live parameter and caller input | Result |
|---|---|
| Live String parameter plus caller value | Use the caller value as-is. Do not resolve or read `JENKINS_SSH_PUBLIC_KEY`. |
| Live String parameter, no caller value, nonempty fallback path | Privately load the file and inject its content; an invalid file exits 3. |
| Live String parameter, no caller value, empty or unset fallback | Preserve the Jenkins default. |
| Parameter missing | Caller input is unknown and exits 2; ignore the fallback path. |
| Parameter present but not String | Ignore the fallback path. Do not use it for a public key; any caller input is governed by normal live-type validation. |

Normal unknown-parameter, type, and duplicate validation still applies. Never expose the caller value, fallback path, or file content.

If required variables exist only in workspace `.env`, reload and execute in one Bash process without printing values:

```bash
bash -c 'set -a; . ./.env; set +a; exec "$@"' bash agent-skills/jenkins-ops/scripts/list_jobs.sh
```

Pass the wrapper and every original argument after the `bash` sentinel. Never interpolate arguments into the `bash -c` program. Restart the harness after changing `.env`, or use this same-shell form.

## Wrapper Reference

Prefix every wrapper with `agent-skills/jenkins-ops/scripts/` from the workspace root.

| Request | Wrapper |
|---|---|
| List approved definitions | `list_jobs.sh` |
| Fetch live parameters | `get_job_parameters.sh <alias>` |
| Review a launch | `trigger_job.sh <alias> [key=value ...]` |
| Enqueue after explicit authorization | `trigger_job.sh --execute <alias> [key=value ...]` |
| Get one build status | `get_build_status.sh <alias> <build>` |
| List recent builds | `list_builds.sh <alias> [count]` |
| Resolve queue ID to build | `resolve_build.sh <alias> <queue-id> [count]` |
| Wait for a queue item | `wait_for_build.sh <queue-id> [timeout-seconds]` |
| Wait for a provisioned host | `wait_for_job_host.sh <alias> <build> [timeout-seconds]` |
| Collect failure evidence | `inspect_build.sh <alias> <build>` |
| Download one selected artifact | `get_artifact.sh <alias> <build> <relative-path>` |
| Resolve a host | `ssh_job_host.sh --resolve-only <alias> <build>` |
| Access a host | `ssh_job_host.sh <alias> <build> [-- <command> [args...]]` |

A queue ID identifies an enqueue operation; a build number identifies a run within one alias. Never use one as the other and never probe nearby build numbers.

- `list_builds.sh`: default count 25; range 1 through 100.
- `resolve_build.sh`: default count 50; range 1 through 100; exact Jenkins `queueId` only.
- `wait_for_build.sh`: default timeout 600 seconds; range 1 through 86400. Expired queue recovery searches at most 100 recent builds per approved job and requires exactly one match.
- `wait_for_job_host.sh`: default timeout 900 seconds; range 1 through 86400; polls every 15 seconds.

## Trigger Workflow

1. Confirm the user explicitly requested a trigger. Review, diagnosis, or a command preview is not authorization.
2. Run `get_job_parameters.sh <alias>`. Read its private parameter file locally.
3. Run `trigger_job.sh <alias> [key=value ...]` without `--execute`.
4. Privately review effective values, `source` fields, choices, warnings, source relationship, managed Slack overrides, and the SSH-key decision above.
5. Only for an explicit trigger request, rerun the same validated inputs with `--execute`.
6. Report queued state and queue ID, then stop.

Pass each `key=value` as a separate quoted argument. Booleans are lowercase `true` or `false`.

For `CUSTOM_TEST_OPTIONS`, use balanced raw double quotes to group values containing spaces or shell pattern characters. Backslashes are literal data. The wrapper rejects ambiguous pre-escaped quotes, inner literal double quotes, control characters, single quotes, command substitutions, shell operators, and unquoted expansion syntax.

```bash
agent-skills/jenkins-ops/scripts/trigger_job.sh e2e 'CUSTOM_TEST_OPTIONS=-t "Backup Listing With More Than 1000 Backups" --exclude "cluster" -v DATA_ENGINE:v2'
```

## Monitoring and Queue Recovery

- Use `get_build_status.sh` for one known build.
- Use `wait_for_build.sh` only for a known positive queue ID.
- Use `resolve_build.sh` for explicit expired-queue recovery. It matches `queueId` metadata exactly: one match exits 0, `NOT_FOUND` exits 5, malformed or duplicate correlation exits 4.
- Success exits 0; queue cancellation or timeout exits 5; completed non-success exits 6.
- Monitoring never triggers, inspects, downloads, waits for a host, or accesses a host.

## Host Wait and SSH

Host extraction requires `python` for validation and canonicalization. It accepts only exact complete lines in these forms: `controlplane_public_ip = "<IPv4>"` or `controlplane_public_ip = "[<IPv6>]"`. The second form is bracketed IPv6. Stored IPv6 is lowercase, compressed, and unbracketed. Zero candidates means pending or unavailable; exactly one is valid; multiple candidates exit 2.

For a separately requested provisioning wait, run `wait_for_job_host.sh`. It checks immediately, then polls every 15 seconds. It never invokes SSH. `READY` or `TIMEOUT` is written to private mode-0600 JSON; timeout exits 5.

Before any access, run `ssh_job_host.sh --resolve-only <alias> <build>`, even after `READY`. Keep the target path and host private. Then prefer a bounded argument array:

```bash
agent-skills/jenkins-ops/scripts/ssh_job_host.sh regression 123 -- sudo systemctl status k3s
```

Use a PTY-capable harness call for interactive access; the wrapper adds `-tt`. Never accept a user-supplied host or reconstruct the command. The wrapper intentionally uses `StrictHostKeyChecking=no` and `UserKnownHostsFile=/dev/null`; this disables host authenticity verification. IPv6 uses `ssh -6` with separate user and host arguments.

## Failure Inspection

1. Run `inspect_build.sh <alias> <build>` and keep the private manifest path out of chat.
2. Resolve relative entries against the manifest directory.
3. Inspect `test-report.json`, then `robot-report.json`, when present.
4. Inspect `build.json`, `artifacts.json`, and `remote-hosts.json` as needed.
5. Only then read at most the final 200 console lines from `console.txt`.
6. Quote at most 20 console lines in chat and truncate each to at most 300 characters.
7. When more evidence exists, append exactly `[truncated; raw evidence remains in <temporary-directory>]`; do not substitute the private path.
8. Diagnose from evidence, not guessed signatures. Use `get_artifact.sh` only for one explicitly selected entry from `artifacts.json`.

Never paste a complete console log.

## Persistent Investigation Workspace

Create no ticket for routine operations. When the user requests persistent troubleshooting, use:
The required schema is `ticket/jenkins_<alias>-<build-number>-job/`, where the alias is `regression`, `e2e`, or `benchmark`.


```text
ticket/jenkins_regression-11238-job/
ticket/jenkins_e2e-11238-job/
```

Initialize normal `logs/` and `repro/` directories. Persist console evidence from `inspect_build.sh` at `logs/console.txt`, never at the ticket root. Keep paths and raw contents private.

## Exit Codes and Retry Safety

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage, input, parameter, or evidence validation failure |
| 3 | Missing environment, command, private storage, SSH configuration, or eligible fallback-key file |
| 4 | Jenkins transport, HTTP, permission, schema, or queue-correlation failure |
| 5 | Queue cancellation, timeout, or no correlated build |
| 6 | Completed non-success build |
| 7 | SSH connection or remote-command failure |

A POST transport failure has an uncertain trigger outcome. Inspect the Jenkins queue before any manual retry; never retry blindly.

Stop and return to the documented wrapper flow if an action would skip live metadata or dry-run review, disclose private data, guess a build or host, bypass resolve-only, exceed evidence bounds, retry an uncertain POST, or perform an implicit follow-on action.
