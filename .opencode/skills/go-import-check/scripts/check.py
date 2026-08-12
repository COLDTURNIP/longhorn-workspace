#!/usr/bin/env python3

import argparse
import subprocess
import sys
from pathlib import Path

EXCLUDED_PARTS = {"vendor", "generated", "dist"}


def workspace_root() -> Path:
    for parent in Path(__file__).resolve().parents:
        if (parent / ".opencode").is_dir() and (parent / "repo").is_dir():
            return parent
    raise RuntimeError("Longhorn workspace root not found")


def git_lines(repo: Path, *args: str) -> set[str]:
    result = subprocess.run(
        ["git", "-C", str(repo), *args],
        check=True,
        stdout=subprocess.PIPE,
        text=True,
    )
    return {line for line in result.stdout.splitlines() if line}


def eligible_go_file(path: str) -> bool:
    candidate = Path(path)
    return (
        candidate.suffix == ".go"
        and not any(part in EXCLUDED_PARTS for part in candidate.parts)
        and not candidate.name.startswith("zz_generated.")
    )


def changed_go_files(repo: Path) -> list[str]:
    has_head = subprocess.run(
        ["git", "-C", str(repo), "rev-parse", "--verify", "HEAD"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0
    changed = (
        git_lines(
            repo,
            "diff",
            "--diff-filter=ACM",
            "--name-only",
            "HEAD",
            "--",
            "*.go",
            ":!vendor/**",
        )
        if has_head
        else set()
    )
    untracked = git_lines(
        repo,
        "ls-files",
        "--others",
        "--exclude-standard",
        "--",
        "*.go",
        ":!vendor/**",
    )
    return sorted(path for path in changed | untracked if eligible_go_file(path))


def repository_paths(root: Path, requested: list[str]) -> list[Path]:
    if requested:
        repositories = []
        for value in requested:
            path = Path(value)
            if not path.is_absolute():
                path = root / path
            repositories.append(path.resolve())
        return repositories

    return sorted(
        path.resolve()
        for path in (root / "repo").iterdir()
        if path.is_dir() and (path / "go.mod").is_file() and (path / ".git").exists()
    )


def check_repository(checker: Path, repo: Path, files: list[str]) -> bool:
    relative_repo = repo.name
    if not files:
        return True

    print(f"Checking repo/{relative_repo}: {len(files)} Go file(s)")
    result = subprocess.run(
        [sys.executable, str(checker)],
        cwd=repo,
        input="\n".join(files) + "\n",
        text=True,
    )
    return result.returncode == 0


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Check changed Go imports in Longhorn workspace repositories."
    )
    parser.add_argument("repositories", nargs="*", help="repo/* paths to check")
    args = parser.parse_args()

    try:
        root = workspace_root()
        checker = root / "repo/longhorn-manager/.github/scripts/check_go_imports.py"
        if not checker.is_file():
            raise RuntimeError(f"import checker not found: {checker}")

        checked_repositories = 0
        checked_files = 0
        passed = True
        for repo in repository_paths(root, args.repositories):
            if not (repo / "go.mod").is_file() or not (repo / ".git").exists():
                raise RuntimeError(f"not a Go repository: {repo}")
            files = changed_go_files(repo)
            if not files:
                continue
            checked_repositories += 1
            checked_files += len(files)
            passed = check_repository(checker, repo, files) and passed

        if not passed:
            return 1
        print(
            f"Go import convention check passed for {checked_files} file(s) "
            f"in {checked_repositories} repository/repositories."
        )
        return 0
    except (OSError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"go-import-check: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
