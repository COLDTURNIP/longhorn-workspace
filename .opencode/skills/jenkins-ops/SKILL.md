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
- Inspect live parameter definitions and the private dry-run launch plan before mutation.
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

All three approved jobs expose `SEND_SLACK_NOTIFICATION` as a Boolean and `NOTIFY_SLACK_CHANNEL` as a String. When `JENKINS_NOTIFY_SLACK_CHANNEL` is nonempty, `trigger_job.sh` validates that live contract and automatically overrides both parameters, forcing notifications on for that channel in dry-run and execute modes. The wrapper rejects caller-supplied overrides for either managed parameter. When the variable is unset or empty, it adds neither override and preserves Jenkins defaults.

`ssh_job_host.sh` additionally requires:

- `JENKINS_SSH_IDENTITY_FILE`: readable regular private identity path; an absolute path or a path beginning with `~/` is accepted
- `JENKINS_SSH_USER`: remote login user

Scripts never source `.env`. If a wrapper exits 3 for a missing variable and workspace `.env` exists, rerun the same wrapper in one Bash process without printing the file or any value:

```bash
bash -c 'set -a; . ./.env; set +a; exec "$@"' bash .opencode/skills/jenkins-ops/scripts/list_jobs.sh
```

Pass another wrapper and every original argument after the `bash` sentinel. They remain an argument array; never interpolate them into the `bash -c` program. Do not paste a token into a command or modify `.env`.

After the user adds or changes `JENKINS_NOTIFY_SLACK_CHANNEL` in `.env`, restart the harness so future processes inherit it, or use the same-shell reload form above for the trigger wrapper. The agent must not edit `.env` or print the configured channel.

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
3. Run `trigger_job.sh <alias> [key=value ...]` without `--execute`. This fetches live definitions again, validates exact `key=value` inputs, automatically applies Slack notification parameters when `JENKINS_NOTIFY_SLACK_CHANNEL` is nonempty, and returns a private launch-plan path without POSTing.
4. Review effective values, `source` fields, choices, warnings, and the source relationship. With a configured channel, require `SEND_SLACK_NOTIFICATION=true` and both notification parameters to have `source:"override"`. Never pass those managed parameters manually, or override password, sensitive-name, or unsupported parameter types.
5. If and only if the user requested mutation, rerun the same validated inputs with `--execute`.
6. Report the queued state and queue ID. Stop. Do not monitor implicitly.

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
- It applies the same exact complete-line IPv4 validation used by inspection and SSH resolution.
- Zero valid hosts means provisioning is still pending. Exactly one means `READY`. Multiple valid hosts fail immediately with exit 2.
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
2. Run `ssh_job_host.sh --resolve-only <alias> <build>` first. It accepts only one exact, valid `controlplane_public_ip = "<IPv4>"` console candidate. Zero or multiple candidates stop with exit 2.
3. Do not paste the resulting target file, IP address, identity path, user value, or raw console line into chat.
4. Prefer a bounded remote-command argument array:

```bash
.opencode/skills/jenkins-ops/scripts/ssh_job_host.sh regression 123 -- sudo systemctl status k3s
```

5. For an interactive session, invoke the no-command wrapper in a PTY-capable harness call. The wrapper adds remote `-tt` itself.
6. Never invoke `ssh` directly, accept a user-supplied host, use `eval`, or reconstruct the wrapper's command.

The wrapper safely expands a leading `~/` against `HOME` without `eval`, validates the resolved regular file, and passes that resolved path to `ssh -i`. Other `~user` shorthand is rejected. It uses `-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null` as explicitly selected, which disables host authenticity verification. It never reads or copies the identity contents.

## Exit Codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 2 | Usage, input, unsupported parameter, or build-evidence validation failure |
| 3 | Missing environment variable, command, SSH configuration, or local private-storage prerequisite |
| 4 | Jenkins transport, HTTP, permission, or response-schema failure |
| 5 | Queue cancellation or timeout |
| 6 | Completed non-success Jenkins build |
| 7 | SSH connection or remote-command failure |

A POST transport failure has an uncertain trigger outcome. Inspect the Jenkins queue before any manual retry; never blindly retry the trigger.

## Rationalizations and Counters

| Rationalization | Required response |
|---|---|
| "The deadline justifies direct curl." | Refuse direct HTTP; wrappers are mandatory under urgency. |
| "Known parameters make live review unnecessary." | Fetch live definitions and inspect the dry-run launch plan before POST. |
| "The full log avoids missing evidence." | Structured reports first; enforce the 200-line read, 20-line quote, and 300-character limits. |
| "Any plausible address is good enough." | Resolve through the wrapper and require exactly one validated console IPv4. |
| "Direct SSH is faster." | Resolve-only first, then use the same wrapper for command or interactive access. |
| "Printing variables will debug missing env." | Name only the missing variable; never print values or `.env`. |

## Red Flags

Stop and return to the wrapper workflow if any proposed action includes:

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
- Reading console before structured reports or quoting private evidence paths into chat.
- Downloading every artifact instead of one explicitly selected relative path.
- Running direct SSH, adding a host argument, or manually copying the wrapper's trust-bypass flags.
