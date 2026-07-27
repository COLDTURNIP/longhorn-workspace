---
name: design-qa-verification-steps
description: Use when drafting or reviewing Longhorn issue verification steps, manual test plans, or ready-for-testing instructions for QA.
---

# Purpose

Produce a verification plan that a QA engineer can execute without reconstructing the issue or guessing commands. Verify the fixed contract through observable cluster behavior, not implementation details.

# Concision contract

- Write a compact issue-comment test plan, not a production-grade automation framework.
- Keep the complete verification plan within 150 nonblank lines by default.
- Keep each step description to one short sentence, preferably 25 words or fewer.
- Include only issue-specific prerequisites, actions, assertions, and recovery. Omit RCA repetition, standard CLI inventories, generic permission lists, defensive state frameworks, and elaborate diagnostics.
- Limit every fenced code block to at most 9 content lines, excluding the fence delimiters.
- Put a longer script or manifest in a separate attachment. In the verification steps, name or link the attachment and show only its exact invocation plus the expected result or predicate. Never paste the attachment body into the plan.
- Place each step's fenced code block on the immediately following line with no blank line.
- Treat inline blocks as commands QA will paste into an interactive terminal. Exclude script setup such as `set -e`, `set -u`, `set -eu`, shebangs, and `umask`; put any required setup inside an attached script.

# Workflow

1. Ground the contract.
   - Read the issue, RCA, linked fixes, and relevant current code or documentation.
   - Summarize the fixed invariant, affected versions, data engine, feature flags, and platform constraints in terse Scope bullets.
   - Label unsupported facts as assumptions.
2. Choose coverage.
   - Include the shortest scenario that directly exercises the fixed invariant.
   - Add a negative, recovery, upgrade, scale, or regression scenario only when it protects a distinct issue contract.
   - Reuse an existing e2e test when it exercises the exact contract; provide its full invocation and prerequisites.
3. Make the platform decision described below.
4. Declare only issue-specific prerequisites before the scenarios.
   - State required cluster size, version or image, feature settings, external services, privileges, and destructive-test warning.
   - Define shared variables once. List installation details only for required non-common tools.
5. Write each scenario in the required Given-When-Then sequence.
6. Add cleanup, failure evidence, and explicit overall pass/fail criteria.
7. Apply every item in the Review checklist.

Completion criterion: a QA engineer can start from the declared environment, run every command in order, and determine pass or fail from stated predicates.

# Platform decision

Classify the issue before choosing infrastructure:

- Platform-independent: write Kubernetes-neutral steps. State that they apply to any supported Kubernetes environment and must be executable on at least RKE2 or K3s on Ubuntu, using AWS or Vagrant infrastructure. Do not require a specific option from that baseline.
- Platform-dependent: name the exact required distribution, operating system, cloud provider, architecture, kernel, runtime, or host facility, and explain which trigger or assertion depends on it.
- Unknown: preserve the neutral baseline and label the unverified dependency as an assumption rather than inventing a restriction.

A platform used in the original report is evidence of where the bug occurred, not proof that the verification requires that platform.

# Scenario structure

Use one numbered sequence per independently passable scenario. A scenario has exactly one `Given` precondition phase followed by one or more sequential `When`-`Then` behavior pairs:

1. `Given ...` establishes the precondition.
2. `And ...` adds preconditions.
3. `When ...` performs a behavior trigger.
4. `And ...` adds actions to that trigger.
5. `Then ...` verifies the resulting behavior.
6. `And ...` verifies additional outcomes or invariants.
7. Repeat `When ... [And ...] Then ... [And ...]` for each subsequent behavior that depends on the preceding result.

Rules:

- `And` extends the immediately preceding Given, When, or Then phase. It never changes phase.
- Hard Markdown rule: put the fenced code block directly after its step description with no intervening blank line.
- Complete each Then phase before starting the next sequential When phase.
- Every operative item includes a command, an exact attachment invocation, or an exact manual action with an observable postcondition.
- A Then item includes a machine-checkable assertion and the expected value or predicate. A diagnostic `kubectl get ... -o yaml` may accompany an assertion but does not replace it.
- Use bounded waits for asynchronous reconciliation. State what a timeout means.
- Keep all setup in the single Given phase, fault injection or user action in When, and observation only in Then.
- Split scenarios only when they require different initial environments or have independent pass/fail outcomes.

# Command rules

- Prefer short POSIX terminal commands. Use Python standard-library scripts as separate attachments when structured logic is clearer.
- A fenced code block contains at most 9 content lines. Count comments, blank lines, and output lines.
- Move any longer script or manifest to a separate attachment with a descriptive name. Show its exact invocation and expected result in the relevant step.
- Inline blocks are pasted into an interactive terminal: omit shebangs, `set -e`, `set -u`, `set -eu`, `umask`, functions, traps, and script argument parsing.
- `kubectl`, `jq`, `yq`, and `cut` are common allowed tools. Prefer them and shell built-ins over `awk`, `sed`, or platform-specific utilities.
- Keep inline commands direct; avoid persistence frameworks, custom polling libraries, and verbose error wrappers unless the fixed contract requires them.
- Omit shell prompt markers such as `$`. Put sample output in a separate fenced block, also limited to 9 content lines.
- Quote variable expansions and make heredoc interpolation intentional.
- Use `kubectl wait` or concise deadline polling. Avoid unbounded loops.
- Assert results with `test`, `jq -e`, or exact `jsonpath` comparisons.
- Include only preflight checks that protect an issue-specific prerequisite or destructive action.
- Keep credentials out of commands and output. Refer to pre-created Secrets or documented environment variables.
- SSH and interactive container access are allowed when host or process state is part of the contract. Identify the target with `kubectl`, give the exact `ssh` or `kubectl exec -it` command, say which terminal runs subsequent commands, and provide an exit or disconnect step.
- For every non-common third-party tool, provide before the scenarios:
  1. why it is required in one sentance;
  2. the supported version or version check;
  3. a copy-paste-ready installation command for the declared verifier environment.
- For an existing automated test, provide repository, revision or image assumption, runner, exact test selector, all required variables and excludes, and the output or exit status that means pass.
- Mark destructive actions clearly and scope them to a disposable QA cluster. Prefer reversible fault injection. Never hide manual recovery steps.

# Output template

Use this shape and remove sections that are genuinely inapplicable:

````markdown
## Verification steps

### Prerequisites

- <access, cluster size, images, storage, safety constraints>

#### Tool installation

<only non-common tools; purpose, version information (if dependes), install command>

```sh
LONGHORN_NAMESPACE=longhorn-system
TEST_NAMESPACE=qa-<issue>
TIMEOUT=300s
export LONGHORN_NAMESPACE TEST_NAMESPACE TIMEOUT
kubectl cluster-info
kubectl -n "${LONGHORN_NAMESPACE}" get pods
```

#### Attachments

- `<verify-issue.sh or manifest.yaml>`: <purpose; include only when an inline block would exceed 9 lines>

### Scenario: <behavior under verification, no blank lines between the code blocks and the items>

1. Given <precondition>
   ```sh
   <create or validate the precondition>
   ```
2. And <additional precondition>
   ```sh
   <command and preflight assertion>
   ```
3. When <trigger>
   ```sh
   <trigger command>
   ```
4. And <additional trigger action>
   ```sh
   <command>
   ```
5. Then <primary expected behavior>
   ```sh
   actual=$(kubectl ...)
   printf 'actual=%s\n' "${actual}"
   test "${actual}" = "<expected>"
   ```
6. And <additional invariant>
   ```sh
   kubectl wait ... --timeout="${TIMEOUT}"
   <machine-checkable assertion>
   ```
7. When <next sequential trigger, if applicable>
   ```sh
   <command that uses the preceding result>
   ```
8. Then <next expected behavior>
   ```sh
   <machine-checkable assertion>
   ```
````

# Review checklist

Before publishing the plan, verify all of the following:

- The fixed contract and every assertion are traceable to the issue, fix, current code, or documentation.
- Platform independence or dependency is explicit. Neutral plans preserve the RKE2/K3s, Ubuntu, AWS/Vagrant baseline without selecting one unnecessarily.
- Every scenario has one Given phase followed by one or more complete When-Then pairs, with optional And items in each phase.
- Every operative item is executable or gives an exact manual action and a verification command.
- Variables and placeholders are declared once, use consistent names, and contain no unexplained issue-specific values.
- Commands are copy-paste ready, bounded, quoted, and free of prompt markers.
- Each step's fenced code block immediately follows its description without a blank line.
- The plan has at most 150 nonblank lines unless a stated issue constraint makes that impossible.
- Every fenced code block has at most 10 content lines; longer logic is a named attachment with an exact invocation.
- Inline blocks contain terminal commands, not shell setup or script-control scaffolding.
- Step descriptions are short, and the plan omits duplicated context and production-grade defensive scaffolding.
- Then items assert observable behavior and name expected values; they do not rely only on visual YAML inspection.
- Non-common tools have installation and version information before the scenarios.
- Multi-terminal, SSH, and `kubectl exec -it` flows identify the target, terminal, and exit step.
- Cleanup reverses every test mutation, or retained resources are explicitly listed.
- Failure evidence is sufficient to distinguish a product failure from an environment, setup, or unrelated infrastructure failure.
- Pass and fail criteria cover every scenario and do not claim more platform or version coverage than the steps establish.
