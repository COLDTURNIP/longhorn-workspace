# Quickstart for OpenCode Beginners

## 0) Pre-requirements

Before you begin, ensure the following tools are installed and available in your environment:

- [npm](https://www.npmjs.com/) and [bun](https://bun.sh/)
- [git](https://git-scm.com/)
- [jq](https://stedolan.github.io/jq/)

You can verify installation with:

```sh
npm --version
bun --version
git --version
jq --version
```

This guide is intended for developers who are new to OpenCode and want to quickly start contributing to the Longhorn workspace.

## 1) Install OpenCode

Install OpenCode using one of the following commands:

```bash
curl -fsSL https://opencode.ai/install | bash
opencode --version
```

Then, configure your model provider using the setup wizard:

```bash
opencode auth login
```

## 2) Configure OpenCode and Install Oh-My-OpenCode

Configuration files are stored at:

- `~/.config/opencode/opencode.json`
- `~/.config/opencode/oh-my-opencode.json` (or `*.jsonc`)

A minimal `opencode.json` should include the `oh-my-opencode` plugin to enable agent provisioning:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "plugin": ["oh-my-opencode"],
  "share": "disabled"
}
```

A minimal `oh-my-opencode.jsonc` might look like this:

```jsonc
{
  "$schema": "https://raw.githubusercontent.com/code-yeongyu/oh-my-opencode/master/assets/oh-my-opencode.schema.json",
  "agents": {
    "agents": {
      "sisyphus": {
        // Main agent: interacts with users and delegates tasks to other agents
        "model": "github-copilot/claude-haiku-4.5",
      },
      "sisyphus-junior": {
        // Worker agent: executes tasks assigned by orchestrator agents like Sisyphus
        "model": "github-copilot/gpt-5.1-codex-mini",
      },
      "atlas": {
        // Orchestrator and progress tracker
        "model": "github-copilot/claude-haiku-4.5",
      },
      "prometheus": {
        // Planner: drafts plans using @plan syntax in Sisyphus conversations
        "model": "github-copilot/claude-haiku-4.5",
      },
      "metis": {
        // Consultant: clarifies requirements during planning
        "model": "github-copilot/claude-haiku-4.5",
      },
      "mumus": {
        // Reviewer: reviews plans
        "model": "github-copilot/gemini-3-flash-preview",
      },
      "oracle": {
        // Consultant: provides advice and answers
        "model": "github-copilot/gemini-3-flash-preview",
      },
      "librarian": {
        // Looks up documentation and open source code
        "model": "github-copilot/gemini-3-flash-preview",
      },
      "explore": {
        // Codebase exploration
        "model": "github-copilot/claude-haiku-4.5",
      },
      "frontend-ui-ux-engineer": {
        // Frontend development
        "model": "github-copilot/gpt-5-mini",
      },
      "document-writer": {
        // Writes documentation
        "model": "github-copilot/gpt-4.1",
      },
      "multimodal-looker": {
        // Handles multimodal (e.g., image/code) tasks
        "model": "github-copilot/gpt-4.1",
      },
      "hephaestus": {
        // Autonomous deep worker, goal-oriented execution
        "model": "github-copilot/claude-haiku-4.5",
      },
    },
    "categories": {
      // Assigns models to dynamic agent roles based on task category
      "visual-engineering": { "model": "github-copilot/gpt-4.1" },
      "ultrabrain": { "model": "github-copilot/claude-sonnet-4.5" },
      "artistry": { "model": "github-copilot/gpt-4.1" },
      "quick": { "model": "github-copilot/gpt-4.1" },
      "unspecified-low": { "model": "github-copilot/grok-code-fast-1" },
      "unspecified-high": { "model": "github-copilot/claude-sonnet-4.5" },
      "writing": { "model": "github-copilot/gemini-3-flash-preview" },
    },
  },
}
```

## 3) Clone the Workspace

Clone the repository and enter the workspace directory:

```bash
git clone https://github.com/COLDTURNIP/longhorn-workspace.git
cd longhorn-workspace
```

## 4) Install Project Skills

Immediately after cloning, run the interactive project installer:

```bash
npx skills add ./agent-skills
```

Choose only the skills you need, select OpenCode or your active harness, and
keep project scope. The CLI stages local-source content in the universal
`.agents/skills` cache and may create harness-specific links. It does not link
the installed content back to the maintained `agent-skills/` source, so rerun
the same add command whenever that source changes.

For a deterministic one-skill OpenCode/OMP refresh, run:

```bash
npx skills add ./agent-skills --skill <skill-name> --agent opencode --copy --yes
```

The `.opencode/skills` compatibility symlink exposes the universal cache to
OMP/Pi. Claude Code and Pi users who want harness-specific locations should
select their corresponding agent target in the interactive installer. Skill
documentation remains in `agent-skills/<skill-name>/SKILL.md`.

## 5) Initialize the Workspace

Before initialization, configure repository remotes in `repo/repo-list.json`.
Do this first, before running `/init-workspace` or the shell script.
This file controls `upstream` and optional `origin` URLs for each subrepo.

Quick start tip:

```bash
cp repo/repo-list.example.json repo/repo-list.json
# edit repo/repo-list.json for your environment
```

Start OpenCode in the root of the workspace:

```bash
opencode .
```

Ask the main agent (Sisyphus) to initialize the workspace:

```text
/init-workspace
```

Alternatively, you can run the initialization script directly:

```bash
bash scripts/init-workspace.sh
```

All Longhorn repositories will be cloned into the `repo/` directory, and architectural indices will be generated for codebase understanding.

The files under `.opencode/commands/` are thin OpenCode slash-command adapters,
so `/init-workspace`, `/repo-init`, and `/yaml-duplicate-key-check` remain
available. Their direct tool interfaces are:

```bash
bash scripts/init-workspace.sh
bash scripts/repo-init.sh
bash scripts/yaml-duplicate-key-check.sh <yaml-file>
```

## 6) Begin Development

You can now interact with OpenCode. For example, to get familiar with the codebase and start contributing to the Volume reconcile flow in `repo/longhorn-manager`, we might ask:

```text
Identify the 3 most important files for the Volume reconcile flow in repo/longhorn-manager. Explain each file's role and the best reading order.
```

Or, to plan a new feature:

```text
@plan read Github ticket https://github.com/longhorn/longhorn/issues/12396 and create a development plan. We may create a working branch "dev/issue-12396" for this task in the related repository. Please consider this when creating the plan.
```

For more information on using agents to plan and execute development tasks, see:

- [OpenCode documentation](https://opencode.ai/docs/overview)
- [Oh-My-OpenCode documentation](https://github.com/code-yeongyu/oh-my-opencode/blob/dev/docs/guide/overview.md)
