# Longhorn Workspace Quickstart

This guide prepares a Longhorn multi-repository workspace for development with
an active coding harness of your choice.

## 1) Install prerequisites

Install the following tools and make sure they are available on your `PATH`:

- [Git](https://git-scm.com/), for cloning and managing repositories
- [Docker](https://docs.docker.com/get-docker/), for Dapper-based builds
- [Go 1.20 or newer](https://go.dev/doc/install), for native Go development
- [Node.js and npm](https://nodejs.org/en/download), for the Longhorn UI and
  the project skill installer
- [Python 3](https://www.python.org/downloads/), for Longhorn tests and workspace
  tooling
- [Make](https://www.gnu.org/software/make/), for repository build targets
- [Helm](https://helm.sh/docs/intro/install/), for chart validation
- [jq](https://jqlang.github.io/jq/download/), for JSON processing in scripts
- [Bun](https://bun.sh/), when working with tooling that uses Bun

Verify the installation with:

```bash
git --version
docker --version
go version
node --version
npm --version
python3 --version
make --version
helm version --short
jq --version
bun --version
```

Use the installation instructions for your operating system if a command is
missing. A Docker daemon must be running when you use Docker-based build
commands.

## 2) Clone the workspace

Clone the workspace repository and enter its root directory:

```bash
git clone https://github.com/COLDTURNIP/longhorn-workspace.git
cd longhorn-workspace
```

Run the remaining commands from this directory.

## 3) Install project skills

Install the maintained project skills immediately after cloning:

```bash
npx skills add ./agent-skills
```

The installer is interactive. Select only the skills you need, choose the
harness you currently use, and keep the installation at project scope. Selected
skills are staged in the universal `.agents/skills` directory. If the source
under `agent-skills/` changes, run the same command again to refresh the
installed skills.

Each maintained skill is documented at
`agent-skills/<skill-name>/SKILL.md`. The installed files are generated state;
make changes to the maintained source rather than editing the generated copy.

## 4) Configure repository remotes

Before initializing the workspace, configure `repo/repo-list.json`. This file
is the source of truth for the repositories to clone and their remotes.

If the file does not exist yet, copy the example and then edit it:

```bash
cp repo/repo-list.example.json repo/repo-list.json
```

For example:

```json
{
  "longhorn-manager": {
    "upstream": "https://github.com/longhorn/longhorn-manager.git",
    "origin": "git@github.com:your-github-id/longhorn-manager.git"
  },
  "types": {
    "upstream": "https://github.com/longhorn/types.git"
  }
}
```

Configuration rules:

- Each JSON key is the target path under `repo/`.
- Every entry requires an `upstream` value containing a complete Git URL.
- An `origin` value is optional and can point to your writable fork.
- Add or remove entries to match the repositories needed for your work.

## 5) Initialize the workspace

Preview the initialization actions first if desired:

```bash
bash scripts/init-workspace.sh --dry-run
```

Run the initialization:

```bash
bash scripts/init-workspace.sh
```

Initialization clones the configured repositories into `repo/`, applies their
`upstream` and optional `origin` remotes, configures local tracking branches,
and generates architectural indices for cross-repository navigation. Run it
again after changing `repo/repo-list.json` to apply the updated configuration.

Initialization evidence is written under `.agents/tmp/init-workspace`. The
workspace retains the five most recent evidence runs and prunes older runs.

### Direct alternatives

To initialize repositories without generating the workspace indices, run:

```bash
bash scripts/repo-init.sh
```

To check a YAML file for duplicate keys, run:

```bash
bash scripts/yaml-duplicate-key-check.sh repo/longhorn/chart/values.yaml
```

Replace the sample YAML path with another file when needed. These scripts are
direct interfaces and do not require a particular coding harness.

## 6) Begin development

Open the workspace root in your selected coding harness and ask it to inspect
the initialized repositories. For example:

```text
Identify the three most important files for the Volume reconcile flow in
repo/longhorn-manager. Explain each file's role and the best reading order.
```

For issue-driven work, provide the issue URL and the repositories involved,
then ask for a plan that identifies affected components, implementation steps,
and verification commands. Keep repository changes in the relevant directory
under `repo/`, and follow that repository's contribution instructions.
