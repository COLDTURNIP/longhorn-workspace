---
name: jenkins-ops
description: Use when a Longhorn developer asks to list, trigger, monitor, inspect, diagnose, or access hosts for the approved Jenkins integration-test jobs.
---

# Jenkins Operations

## Purpose

Use the checked-in wrappers for every Jenkins HTTP operation and for access to a host provisioned by an approved test job. The wrappers enforce the job allowlist, current Jenkins parameter metadata, private evidence, bounded diagnosis, and controlled SSH.

Core principle: never replace a wrapper with ad-hoc `curl`, a guessed Jenkins URL, an improvised host, or a direct SSH command. Urgency does not weaken this rule.

## Safety Invariants

- Use only scripts under `.opencode/skills/jenkins-ops/scripts/` for Jenkins HTTP and job-host SSH.
- Never compose or provide ad-hoc Jenkins `curl` commands, even when asked to bypass wrappers.
- Never print, paste, parse, or persist Jenkins credentials or `.env` values. Never modify `.env`.
- Read-only wrappers may run directly. Mutation requires the user's explicit trigger request and `trigger_job.sh --execute`.
- A trigger is trigger-and-forget. Never wait for, inspect, download from, or SSH to the build unless separately requested.
- Inspect live parameter definitions and the private dry-run launch plan before mutation. If the live job exposes `CUSTOM_SSH_PUBLIC_KEY` as a `StringParameterDefinition`, a caller-supplied `CUSTOM_SSH_PUBLIC_KEY=...` is used as-is; only when no caller override exists does a nonempty `JENKINS_SSH_PUBLIC_KEY` path go through the shared public-key environment loader. Never print caller values, environment paths, or key content. If the live job lacks that exact String parameter, caller input is an unknown-parameter error and an environment path is ignored.
- `trigger_job.sh` gives a live String `CUSTOM_SSH_PUBLIC_KEY` caller override precedence over `JENKINS_SSH_PUBLIC_KEY`: the caller value is used directly and the environment path is not resolved or read. Caller input still receives normal unknown-parameter, type, and duplicate validation. With no caller override, a nonempty environment path is loaded through the shared public-key loader and its content is injected; unset or empty keeps the Jenkins default. Unsupported live jobs reject caller input as unknown and ignore the environment path. Never expose caller values, paths, or key content in terminal output.
- When `JENKINS_NOTIFY_SLACK_CHANNEL` is nonempty, every trigger must use its automatic `SEND_SLACK_NOTIFICATION=true` and `NOTIFY_SLACK_CHANNEL` overrides.
- Keep temporary evidence private. Do not quote manifest paths, identity paths, IP addresses, raw console logs, or environment-variable values into chat.
- Never contact `longhorn-e2e-test-pull-request-check`.

## Approved Jobs and Source Relationship

| Alias | Jenkins path | Pipeline | Test source relationship |
|---|---|---|---|
| `regression` | `private/longhorn-tests-regression` | `repo/longhorn-tests/test_framework/Jenkinsfile` | The setup pipeline drives `manager/integration/deploy/test.yaml`. PyTest runs from `LONGHORN_TESTS_CUSTOM_IMAGE`; checkout and test-image revisions may differ. |
| `e2e` | `private/longhorn-e2e-test` | `repo/longhorn-tests/pipelines/e2e/Jenkinsfile` | The setup pipeline drives `e2e/deploy/test.yaml`. Robot Framework runs from `LONGHORN_TESTS_CUSTOM_IMAGE`; checkout and test-image revisions may differ. |
| `benchmark` | `private/longhorn-benchmark-test` | `repo/longhorn-tests/benchmark_test/Jenkinsfile` | The setup image copies the checkout and runs `benchmark_test/scripts/benchmark-test-setup.sh`, which uses checked-in kbench manifests. Source publishes no structured report or archived artifact. |

These aliases are exhaustive and ordered: `regression`, `e2e`, `benchmark`.

The e2e pipeline currently coerces effective Boolean `RUN_V2_TEST=false` to true. The wrapper refuses either an explicit false override or an omitted live false default with exit 2 and this warning:

`Current pipelines/e2e/Jenkinsfile coerces RUN_V2_TEST=false to true; this wrapper refuses that effective value.`

## Environment

Jenkins wrappers read only process environment:

- `JENKINS_URL`
- `JENKINS_USER`
- `JENKINS_TOKEN`
- `JENKINS_NOTIFY_SLACK_CHANNEL`: optional Slack channel ID configured by the user in workspace `.env`
- `JENKINS_SSH_PUBLIC_KEY`: optional fallback path to a public-key file. It is resolved and read only when the caller did not supply `CUSTOM_SSH_PUBLIC_KEY` and the live job exposes that name as a Jenkins `StringParameterDefinition`; in that case it must name a readable regular nonempty public-key file. A leading `~/` is resolved against `HOME`, and other `~user` shorthand is rejected. Unset or empty preserves the Jenkins default, and an unsupported live parameter ignores the path.

`JENKINS_SSH_PUBLIC_KEY` is an optional fallback. A caller-supplied `CUSTOM_SSH_PUBLIC_KEY=...` takes precedence on a live String parameter, is used as-is, and prevents the environment path from being resolved or read. Without a caller override, a nonempty path is safely resolved, read through the shared public-key loader, and injected into dry-run plans and execute POSTs. For a supporting live job with no caller override and a nonempty fallback path, an unavailable, unreadable, non-regular, or empty file exits 3. If the live job does not expose that exact String parameter, caller input is an unknown-parameter error and the configured path is ignored. With no caller override and an unset or empty path, no key override is added and Jenkins defaults are preserved. Never print the caller value, path, or file content.

All three approved jobs expose `SEND_SLACK_NOTIFICATION` as a Boolean and `NOTIFY_SLACK_CHANNEL` as a String. When `JENKINS_NOTIFY_SLACK_CHANNEL` is nonempty, `trigger_job.sh` validates that live contract and automatically overrides both parameters, forcing notifications on for that channel in dry-run and execute modes. The wrapper rejects caller-supplied overrides for either managed parameter. When the variable is unset or empty, it adds neither override and preserves Jenkins defaults.

Host extraction in `inspect_build.sh`, `wait_for_job_host.sh`, and `ssh_job_host.sh` requires `python` for standard-library IP validation and canonicalization.

`ssh_job_host.sh` additionally requires:

- `JENKINS_SSH_IDENTITY_FILE`: readable regular private identity path; an absolute path or a path beginning with `~/` is accepted
- `JENKINS_SSH_USER`: remote login user

Scripts never source `.env`. `JENKINS_SSH_PUBLIC_KEY` is an optional fallback: unset or empty is valid and preserves Jenkins defaults, while a caller-supplied `CUSTOM_SSH_PUBLIC_KEY` bypasses path resolution and file reading. If a wrapper exits 3 for another missing required variable and workspace `.env` exists, rerun the same wrapper in one Bash process without printing the file or any value:

```bash
bash -c 'set -a; . ./.env; set +a; exec "$@"' bash .opencode/skills/jenkins-ops/scripts/list_jobs.sh
```

For a trigger, use the same-shell reload for both dry-run and (after private review) execute when loading workspace `.env`; it loads the optional fallback path without printing it. A caller-supplied `CUSTOM_SSH_PUBLIC_KEY=...` on a supported live String parameter is used as-is and prevents any path resolution or read. Without a caller override, a nonempty path is read through the shared public-key loader; an unsupported live parameter ignores the path. Pass caller inputs as separate arguments and keep their values private:

```bash
bash -c 'set -a; . ./.env; set +a; exec "$@"' bash .opencode/skills/jenkins-ops/scripts/trigger_job.sh e2e CUSTOM_TEST_OPTIONS="-i negative --exclude cluster"
bash -c 'set -a; . ./.env; set +a; exec "$@"' bash .opencode/skills/jenkins-ops/scripts/trigger_job.sh --execute e2e CUSTOM_TEST_OPTIONS="-i negative --exclude cluster"
```

Pass another wrapper and every original argument after the `bash` sentinel. They remain an argument array; never interpolate them into the `bash -c` program. Do not paste a token, public-key path, or public-key content into a command or modify `.env`.

After the user adds or changes `JENKINS_NOTIFY_SLACK_CHANNEL` or the optional fallback `JENKINS_SSH_PUBLIC_KEY` in `.env`, restart the harness so future processes inherit it, or use the same-shell reload form above for the wrapper. A direct caller `CUSTOM_SSH_PUBLIC_KEY` takes precedence without using that path. The agent must not edit `.env` or print the configured channel, public-key path, caller value, or file content.

## Quick Reference

| Request | Wrapper |
|---|---|
| List approved jobs | `list_jobs.sh` |
| Fetch live parameters | `get_job_parameters.sh <alias>` |
| Review a launch | `trigger_job.sh <alias> [key=value ...]` |
| Explicitly enqueue | `trigger_job.sh --execute <alias> [key=value ...]` |
| Get one build status | `get_build_status.sh <alias> <build>` |
| Wait for a queue item | `wait_for_build.sh <queue-id> [timeout-seconds]` |
| Wait for Terraform host readiness | `wait_for_job_host.sh <alias> <build> [timeout-seconds]` |
| Collect private failure evidence | `inspect_build.sh <alias> <build>` |
| Download one selected artifact | `get_artifact.sh <alias> <build> <relative-path>` |
| Resolve a job host | `ssh_job_host.sh --resolve-only <alias> <build>` |
| Access a resolved job host | `ssh_job_host.sh <alias> <build> [-- <command> [args...]]` |

Prefix each wrapper with `.opencode/skills/jenkins-ops/scripts/` when running from the workspace root.

## Trigger Workflow

1. Confirm the user explicitly requested a trigger. A request to review, diagnose, or show a command is not trigger authorization.
2. Run `get_job_parameters.sh <alias>`. It returns a private parameter-file path. Read that file locally; do not paste sensitive values or its path into chat.
3. Run `trigger_job.sh <alias> [key=value ...]` without `--execute`. This fetches live definitions again, validates exact `key=value` inputs, and returns a private launch-plan path without POSTing. On a live String `CUSTOM_SSH_PUBLIC_KEY` parameter, a caller-supplied key is validated normally and then used as-is; the `JENKINS_SSH_PUBLIC_KEY` path is not resolved or read. Without a caller override, a nonempty environment path goes through the shared public-key loader and its content is injected. An unset or empty path preserves Jenkins defaults. For an unsupported live parameter, caller input is an unknown-parameter error and the environment path is ignored. A supporting live job with no caller override and an unavailable, unreadable, non-regular, or empty fallback file exits 3.
4. Review effective values, `source` fields, choices, warnings, and the source relationship in the private launch plan. If a caller key was supplied on a supported live String parameter, confirm it is the `CUSTOM_SSH_PUBLIC_KEY` `source:"override"` value without exposing it and confirm the environment path was not read. Otherwise, when a nonempty fallback path is eligible, confirm its file content is the sole `CUSTOM_SSH_PUBLIC_KEY` source, also with `source:"override"`, without exposing the path or content. With no eligible source, confirm no key override is present. With a configured channel, require `SEND_SLACK_NOTIFICATION=true` and both notification parameters to have `source:"override"`. Never pass managed parameters manually, or override password, sensitive-name, or unsupported parameter types.
5. If and only if the user requested mutation, rerun the same validated inputs with `--execute`; the wrapper applies the same caller-first key handling. A caller key is used as-is and prevents fallback path resolution/read; otherwise an eligible nonempty fallback path is loaded privately and only its content is injected into the POST. Never print the caller value, path, or content.
6. Report the queued state and queue ID. Stop. Do not monitor implicitly.

With `JENKINS_SSH_PUBLIC_KEY` exported as a file path (or loaded through the same-shell reload above), it is only a fallback: a caller-supplied key wins on a live `CUSTOM_SSH_PUBLIC_KEY` String parameter, while no caller override allows the wrapper to read the path through the shared loader. An unset or empty path preserves Jenkins defaults; a live job without that parameter ignores the path and rejects caller input as unknown. Never add the managed parameter manually.
To exercise caller-first key handling, keep the caller value in a private shell variable and pass it as one argument; never print the variable or enable shell tracing:

```bash
.opencode/skills/jenkins-ops/scripts/trigger_job.sh e2e "CUSTOM_SSH_PUBLIC_KEY=$CALLER_SSH_PUBLIC_KEY"
.opencode/skills/jenkins-ops/scripts/trigger_job.sh --execute e2e "CUSTOM_SSH_PUBLIC_KEY=$CALLER_SSH_PUBLIC_KEY"
```

On a supported live String parameter, these caller values are used as-is and the environment fallback path is not resolved or read. Caller values, paths, and file content must remain out of terminal output.

Focused e2e example after explicit trigger authorization:

```bash
.opencode/skills/jenkins-ops/scripts/get_job_parameters.sh e2e
.opencode/skills/jenkins-ops/scripts/trigger_job.sh e2e CUSTOM_TEST_OPTIONS="-i negative --exclude cluster"
.opencode/skills/jenkins-ops/scripts/trigger_job.sh --execute e2e CUSTOM_TEST_OPTIONS="-i negative --exclude cluster"
```

The double quotes group the value as one shell argument; the quote characters are not included in the value sent to Jenkins.

Never replace these calls with direct HTTP, even under deadline pressure.

## Monitor Workflow

- Use `get_build_status.sh` for one known build.
- Use `wait_for_build.sh` only for a known positive queue ID. Default timeout is 600 seconds; valid explicit timeouts are 1 through 86400.
- Result `SUCCESS` exits 0. Queue cancellation or timeout exits 5. Any completed non-success Jenkins result exits 6.
- Monitoring never triggers, inspects, downloads, or accesses a host.

## Host Provisioning Wait

Use `wait_for_job_host.sh <alias> <build> [timeout-seconds]` when a known running build is still provisioning its Terraform control-plane host. This is a separately requested read-only action; never start it implicitly after a trigger.

- The default timeout is 900 seconds; explicit timeouts must be 1 through 86400.
- It fetches the console immediately, then polls every 15 seconds while no valid host is present.
- It applies the same exact complete-line validation used by inspection and SSH resolution: unquoted IPv4 or bracketed IPv6 only. Stored IPv6 hosts are canonical, lowercase, compressed, and have no brackets.
- Zero valid hosts means provisioning is still pending. Exactly one means `READY`. Multiple valid hosts, including mixed IPv4 and IPv6 candidates, fail immediately with exit 2.
- Success writes private mode-0600 JSON containing `job`, `build`, `host`, and `result:"READY"`, then prints only its path.
- Timeout writes equivalent private evidence with `host:null` and `result:"TIMEOUT"`, prints only its path, and exits 5.
- It does not require SSH configuration and never invokes SSH.

After a `READY` result, still run `ssh_job_host.sh --resolve-only <alias> <build>` before access. Keep both private result paths and the host value out of chat.

## Persistent Investigation Workspace

Do not create a `ticket/` folder merely to list, trigger, monitor, or inspect a build. Temporary wrapper evidence is the default.

When the user requests a persistent troubleshooting workspace, use the ticket-compatible format:

```text
ticket/jenkins_<alias>-<build-number>-job/
```

Treat `jenkins_<alias>` as the source organization, the numeric Jenkins build number as the ticket ID, and `job` as the description. `<alias>` must be `regression`, `e2e`, or `benchmark`. Regression and e2e build 11238 therefore remain distinct:

```text
ticket/jenkins_regression-11238-job/
ticket/jenkins_e2e-11238-job/
```

This preserves the workspace `${org}-${ticket_id}-${description}` convention while grouping investigations by Jenkins workflow. Do not omit the `job` description segment.

Initialize the normal ticket structure, including `logs/` and `repro/`. Persist downloaded console evidence at `logs/console.txt`, never at the ticket root. Obtain it through `inspect_build.sh`; do not add a direct Jenkins download command. Keep the workspace directory and evidence files private, and keep their paths and contents out of chat except for the bounded excerpts allowed below.

## Failure Inspection

1. Run `inspect_build.sh <alias> <build>`. It prints only a private manifest path.
2. Resolve every relative file entry against the manifest's containing private directory.
3. Inspect structured evidence first: `test-report.json` when JUnit exists, then `robot-report.json` when the exact Robot action exists. Missing optional reports are not errors.
4. Inspect `build.json`, `artifacts.json`, and `remote-hosts.json` as needed.
5. Only then read at most the final 200 console lines from `console.txt`.
6. In chat, quote at most 20 console lines. Truncate every quoted line to at most 300 characters.
7. Whenever more console or report evidence exists, end the excerpt with `[truncated; raw evidence remains in <temporary-directory>]`. Keep the actual private directory path out of chat; use that marker literally or describe the private evidence location without revealing it.
8. Do not hardcode or guess Longhorn failure signatures. Ground the diagnosis in structured and bounded evidence.
9. Use `get_artifact.sh` only after the user or investigation explicitly selects an artifact listed in `artifacts.json`.

Never paste an entire console log. Completeness pressure is not a reason to disclose unbounded evidence.

## SSH Troubleshooting

1. If Terraform provisioning is still in progress, run `wait_for_job_host.sh <alias> <build> [timeout-seconds]` and require a `READY` result.
2. Run `ssh_job_host.sh --resolve-only <alias> <build>` first. It accepts only one exact, valid console candidate: `controlplane_public_ip = "<IPv4>"` or `controlplane_public_ip = "[<IPv6>]"`. IPv6 must be bracketed in the console; the private target stores its canonical address without brackets. Zero or multiple candidates stop with exit 2.
3. Do not paste the resulting target file, IP address, identity path, user value, or raw console line into chat.
4. Prefer a bounded remote-command argument array:

```bash
.opencode/skills/jenkins-ops/scripts/ssh_job_host.sh regression 123 -- sudo systemctl status k3s
```

5. For an interactive session, invoke the no-command wrapper in a PTY-capable harness call. The wrapper adds remote `-tt` itself.
6. Never invoke `ssh` directly, accept a user-supplied host, use `eval`, or reconstruct the wrapper's command.

The wrapper safely expands a leading `~/` against `HOME` without `eval`, validates the resolved regular file, and passes that resolved path to `ssh -i`. Other `~user` shorthand is rejected. It uses `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` as explicitly selected, which disables host authenticity verification. For IPv6 it passes the validated address separately with `ssh -6 -l <user> <host>`, avoiding ambiguous `user@host` parsing. It never reads or copies the identity contents.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage, input, normal unknown/type/duplicate validation, unsupported caller-supplied parameter, or build-evidence validation failure. A supported caller `CUSTOM_SSH_PUBLIC_KEY` is used as-is; an unsupported live job reports that caller input as unknown and ignores any environment fallback path. |
| 3 | Missing required environment variable, command, SSH configuration, local private-storage prerequisite, or invalid configured public-key fallback file when caller input is absent and key injection is supported and enabled |
| 4 | Jenkins transport, HTTP, permission, or response-schema failure |
| 5 | Queue cancellation or timeout |
| 6 | Completed non-success Jenkins build |
| 7 | SSH connection or remote-command failure |

`JENKINS_SSH_PUBLIC_KEY` being unset or empty is not an error and does not exit 3; with no caller key, Jenkins defaults are preserved. A caller-supplied `CUSTOM_SSH_PUBLIC_KEY` on a supported live String parameter is used as-is and bypasses environment path resolution and file reading. A missing or non-String live parameter is nonfatal when no caller key is supplied: no key is set and the configured path is ignored. Caller input against an unsupported live parameter remains an unknown-parameter error (exit 2). An unreadable, non-regular, or empty fallback file exits 3 only when caller input is absent, the live parameter is supported, and the fallback path is nonempty.

A POST transport failure has an uncertain trigger outcome. Inspect the Jenkins queue before any manual retry; never blindly retry the trigger.

## Rationalizations and Counters

| Rationalization | Required response |
|---|---|
| "The deadline justifies direct curl." | Refuse direct HTTP; wrappers are mandatory under urgency. |
| "Known parameters make live review unnecessary." | Fetch live definitions and inspect the dry-run launch plan before POST. |
| "The full log avoids missing evidence." | Structured reports first; enforce the 200-line read, 20-line quote, and 300-character limits. |
| "Any plausible address is good enough." | Resolve through the wrapper and require exactly one validated console IPv4 or bracketed IPv6 address. |
| "Direct SSH is faster." | Resolve-only first, then use the same wrapper for command or interactive access. |
| "Printing variables will debug missing env." | Name only the missing variable; never print values or `.env`. |
| "The public key is safe to paste or pass manually." | A direct caller `CUSTOM_SSH_PUBLIC_KEY=...` is supported on a live String parameter, takes precedence, and is used as-is without resolving or reading `JENKINS_SSH_PUBLIC_KEY`. Without a caller override, keep the optional fallback path in the process environment and let the shared loader read it privately; unsupported live jobs ignore the path and reject caller input as unknown. Normal unknown/type/duplicate validation still applies. Never print caller values, paths, or key content. |
| "The job alias tells me whether SSH key support exists." | Use live parameter metadata. A caller override works only for a live `StringParameterDefinition`; without one, a nonempty environment path is the fallback, an unset or empty path preserves Jenkins defaults, and an unsupported live parameter ignores the path. |

## Red Flags

Stop and return to the wrapper workflow if any proposed action includes:

- Attempting to bypass caller-first `CUSTOM_SSH_PUBLIC_KEY` handling: on a live String parameter, a caller value wins and is used as-is without resolving or reading `JENKINS_SSH_PUBLIC_KEY`; without a caller value, a nonempty environment path is the fallback; an unsupported live job reports caller input as unknown and ignores the path
- Skipping live capability validation or private launch-plan review before an eligible key injection
- Ad-hoc Jenkins `curl` or a manually assembled job URL
- Triggering without an explicit user request or without `--execute`
- Skipping live parameters or private launch-plan review
- Printing credentials, environment values, private paths, IPs, or identity information
- Pasting an entire console or exceeding the evidence bounds
- Guessing a host or invoking SSH before `--resolve-only`
- Retrying an uncertain POST
- Automatically monitoring or inspecting after a trigger

## Common Mistakes

- Treating regression/e2e checkout branches as the PyTest/Robot test-source revision. The custom test image is authoritative for those runners.
- Assuming `RUN_V2_TEST=false` is honored. The wrapper refuses it.
- Passing a Boolean as `TRUE`, `False`, or another spelling. Use lowercase `true` or `false`.
- Merging multiple `key=value` inputs into one shell string. Pass each as a separate quoted argument.
- Manually passing `SEND_SLACK_NOTIFICATION` or `NOTIFY_SLACK_CHANNEL` while `JENKINS_NOTIFY_SLACK_CHANNEL` is nonempty. Let the wrapper apply both.
- Assuming `CUSTOM_SSH_PUBLIC_KEY` is discarded or that the environment always wins. On a supported live String parameter, a caller argument takes precedence, is used as-is, and prevents environment path resolution and reading; normal unknown/type/duplicate validation still applies. Without a caller override, a nonempty environment path is the fallback. Unsupported jobs report caller input as unknown and ignore the path.
- Assuming the optional public-key environment variable contains key content rather than a path to a readable regular nonempty file; it is only a fallback when caller input is absent, unset or empty preserves Jenkins defaults, and an unsupported live parameter ignores the path. A leading `~/` is resolved against `HOME` and content is read privately through the shared loader.
- Forgetting that a newly added or changed `.env` key needs a same-shell reload or harness restart before triggering.
- Reading console before structured reports or quoting private evidence paths into chat.
- Downloading every artifact instead of one explicitly selected relative path.
- Running direct SSH, adding a host argument, or manually copying the wrapper's trust-bypass flags.
