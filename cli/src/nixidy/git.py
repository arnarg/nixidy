"""Helpers to fetch rendered manifests from a remote git branch."""

import shutil
import subprocess
import sys
import tarfile
import tempfile
from pathlib import Path

GIT = shutil.which("git") or "git"


def _require_git() -> None:
    if not shutil.which("git"):
        print(
            "error: git is required to diff against a branch but was not found in PATH",
            file=sys.stderr,
        )
        raise SystemExit(1)


def normalize_root(root: str) -> str:
    """Normalize a manifest root path for use as a git tree path.

    Git rejects a bare `.` in tree paths even though it
    is a valid root referring to the top of the tree, so empty and `.` segments
    are stripped.

    Example:

        normalize_root(".")           # ""
        normalize_root("./manifests/")  # "manifests"
        normalize_root("manifests/dev")  # "manifests/dev"
    """
    return "/".join(p for p in root.split("/") if p not in ("", "."))


def git_output(repo: Path, *args: str) -> str:
    return subprocess.check_output([GIT, "-C", str(repo), *args], text=True).strip()


def repo_root() -> Path:
    return Path(git_output(Path.cwd(), "rev-parse", "--show-toplevel"))


def remote_exists(repo: Path, remote: str) -> bool:
    result = subprocess.run(
        [GIT, "-C", str(repo), "remote", "get-url", remote],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def object_exists(repo: Path, object_name: str) -> bool:
    result = subprocess.run(
        [GIT, "-C", str(repo), "cat-file", "-e", object_name],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    return result.returncode == 0


def fetch(repo: Path, remote: str, branch: str) -> int:
    result = subprocess.run(
        [GIT, "-C", str(repo), "fetch", "--quiet", "--depth=1", remote, branch],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
    )
    if result.returncode != 0 and result.stderr:
        print(result.stderr, file=sys.stderr)
    return result.returncode


def extract_root(repo: Path, root: str) -> Path:
    """Extract FETCH_HEAD:<root> into a temporary directory and return its path."""
    tmp_dir = Path(tempfile.mkdtemp(prefix="nixidy-branch-diff-"))
    args = [GIT, "-C", str(repo), "archive", "FETCH_HEAD"]
    if root:
        args.extend(["--", root])
    archive = subprocess.Popen(args, stdout=subprocess.PIPE)
    if archive.stdout is None:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError("failed to read git archive output")
    try:
        with archive.stdout, tarfile.open(fileobj=archive.stdout, mode="r|") as tar:
            tar.extractall(tmp_dir, filter="data")
    except BaseException:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        archive.wait()
        raise
    if archive.wait() != 0:
        shutil.rmtree(tmp_dir, ignore_errors=True)
        raise RuntimeError("git archive failed")
    return tmp_dir
