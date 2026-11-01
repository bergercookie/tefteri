"""``scripts/version.sh``: nightly and release versions, all forms from the same inputs."""

import os
import re
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path(__file__).parents[3] / "scripts" / "version.sh"


def _git(repo: Path, *args: str) -> str:
    env = {
        **os.environ,
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@example.com",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@example.com",
    }
    return subprocess.run(
        ["git", *args], cwd=repo, env=env, check=True, capture_output=True, text=True
    ).stdout.strip()


@pytest.fixture
def repo(tmp_path: Path) -> Path:
    _git(tmp_path, "init", "-q")
    _git(tmp_path, "commit", "-q", "--allow-empty", "-m", "one")
    return tmp_path


def run(repo: Path, *args: str, tags: str = "", ref: str | None = None) -> str:
    env = {**os.environ, "TEFTERI_PUBLISHED_TAGS": tags}
    env.pop("GITHUB_REF_NAME", None)
    if ref is not None:
        env["GITHUB_REF_NAME"] = ref
    return subprocess.run(
        ["bash", str(SCRIPT), *args], cwd=repo, env=env, check=True, capture_output=True, text=True
    ).stdout.strip()


def test_first_nightly_without_a_release(repo: Path) -> None:
    sha = _git(repo, "rev-parse", "--short=7", "HEAD")
    assert run(repo, "nightly") == f"0.0.0.{sha}.post1"


def test_nightly_counts_posts_since_the_last_release(repo: Path) -> None:
    _git(repo, "tag", "v1.4.0")
    _git(repo, "commit", "-q", "--allow-empty", "-m", "two")
    sha = _git(repo, "rev-parse", "--short=7", "HEAD")
    tags = "\n".join(
        ["latest", "nightly", "1.3.0.aaaaaaa.post9", "1.4.0.bbbbbbb.post1", "1.4.0.ccccccc.post2"]
    )
    assert run(repo, "nightly", tags=tags) == f"1.4.0.{sha}.post3"
    assert run(repo, "nightly", "pep440", tags=tags) == f"1.4.0.post3+{sha}"
    assert run(repo, "nightly", "flutter", tags=tags) == "1.4.0+3"


def test_all_forms_come_from_the_same_inputs(repo: Path) -> None:
    _git(repo, "tag", "v2.0.1")
    tags = "2.0.1.abcdef0.post4"
    image = run(repo, "nightly", tags=tags)
    match = re.fullmatch(r"(\d+\.\d+\.\d+)\.([0-9a-f]{7})\.post(\d+)", image)
    assert match is not None
    stable, sha, post = match.groups()
    assert run(repo, "nightly", "pep440", tags=tags) == f"{stable}.post{post}+{sha}"
    assert run(repo, "nightly", "flutter", tags=tags) == f"{stable}+{post}"
    # The PEP 440 form is a valid Python version.
    from packaging.version import Version

    assert str(Version(f"{stable}.post{post}+{sha}")) == f"{stable}.post{post}+{sha}"


def test_tags_of_other_releases_do_not_count(repo: Path) -> None:
    _git(repo, "tag", "v1.4.0")
    tags = "1.4.00.aaaaaaa.post7\n11.4.0.aaaaaaa.post8\n1.4.0.post5"
    assert run(repo, "nightly", tags=tags).endswith(".post1")


def test_nightly_built_detects_the_current_commit(repo: Path) -> None:
    sha = _git(repo, "rev-parse", "--short=7", "HEAD")
    run(repo, "nightly-built", tags=f"0.0.0.{sha}.post1")  # exit code 0
    with pytest.raises(subprocess.CalledProcessError):
        run(repo, "nightly-built", tags="0.0.0.0000000.post1")


def test_release_version_from_the_tag(repo: Path) -> None:
    assert run(repo, "release", ref="v1.5.0") == "1.5.0"
    assert run(repo, "release", "pep440", ref="v1.5.0") == "1.5.0"
    assert run(repo, "release", "flutter", ref="v1.5.0") == "1.5.0+1"  # one commit
    _git(repo, "tag", "v1.6.0")
    assert run(repo, "release") == "1.6.0"
    with pytest.raises(subprocess.CalledProcessError):
        run(repo, "release", ref="master")


def test_a_failing_tag_lookup_stops_the_script(repo: Path, tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    gh = fake_bin / "gh"
    gh.write_text("#!/bin/sh\necho 'HTTP 401: Bad credentials' >&2\nexit 1\n")
    gh.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if k != "TEFTERI_PUBLISHED_TAGS"}
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    result = subprocess.run(
        ["bash", str(SCRIPT), "nightly"], cwd=repo, env=env, capture_output=True, text=True
    )
    assert result.returncode != 0 and result.stdout == ""
    assert "Bad credentials" in result.stderr


def test_an_unpublished_image_has_no_tags(repo: Path, tmp_path: Path) -> None:
    fake_bin = tmp_path / "bin"
    fake_bin.mkdir()
    gh = fake_bin / "gh"
    gh.write_text("#!/bin/sh\necho 'gh: Package not found. (HTTP 404)' >&2\nexit 1\n")
    gh.chmod(0o755)
    env = {k: v for k, v in os.environ.items() if k != "TEFTERI_PUBLISHED_TAGS"}
    env["PATH"] = f"{fake_bin}:{env['PATH']}"
    out = subprocess.run(
        ["bash", str(SCRIPT), "nightly"],
        cwd=repo,
        env=env,
        check=True,
        capture_output=True,
        text=True,
    ).stdout
    assert out.strip().endswith(".post1")
