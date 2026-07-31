"""Shared fixture factory for the test harness (spec FR-002 / D-006).

make_repo / make_consuming_repo build isolated, self-cleaning git-repo fixtures
under the system temp dir (never the working tree). The fault helper is
scope-capped (BC-3): only the faults item 0's own tests and proof-of-use need
(missing file, broken git) -- NOT a generic mutation/generative seam. Stdlib only.
"""
import pathlib
import shutil
import subprocess
import tempfile


class Fixture:
    """An isolated fixture directory with deterministic cleanup."""

    def __init__(self, path: str):
        self.path = pathlib.Path(path)

    def cleanup(self) -> None:
        shutil.rmtree(self.path, ignore_errors=True)

    def __enter__(self) -> "Fixture":
        return self

    def __exit__(self, *exc) -> None:
        self.cleanup()


def _git(args, cwd) -> None:
    subprocess.run(["git", *args], cwd=str(cwd), check=True, capture_output=True)


def make_repo(files=None) -> Fixture:
    """A temp git repo with one commit. `files` maps repo-relative path -> content."""
    root = tempfile.mkdtemp(prefix="thf-repo-")
    try:
        _git(["init", "-q"], root)
        _git(["config", "user.email", "t@example.invalid"], root)
        _git(["config", "user.name", "harness-test"], root)
        for rel, content in (files or {"README.md": "fixture\n"}).items():
            p = pathlib.Path(root) / rel
            p.parent.mkdir(parents=True, exist_ok=True)
            p.write_text(content, encoding="utf-8")
        _git(["add", "-A"], root)
        _git(["commit", "-q", "-m", "init"], root)
    except BaseException:
        shutil.rmtree(root, ignore_errors=True)  # no temp leak on git failure
        raise
    return Fixture(root)


def make_consuming_repo(files=None) -> Fixture:
    """A repo that carries a minimal .agent manifest skeleton (a consuming repo)."""
    base = {".agent/project-manifest.md": "# project-manifest\n"}
    base.update(files or {})
    return make_repo(base)


# --- minimal fault helper (BC-3: only what our own tests need) ---

def inject_missing_file(fixture: Fixture, rel: str) -> None:
    (fixture.path / rel).unlink()


def inject_broken_git(fixture: Fixture) -> None:
    """Corrupt .git/HEAD so `git rev-parse HEAD` (and friends) fail non-zero."""
    (fixture.path / ".git" / "HEAD").write_text("not-a-valid-ref\n", encoding="utf-8")
