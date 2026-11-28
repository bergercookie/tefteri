"""``scripts/version.sh``: the next release version and the forms of a version."""

import os
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


def run(repo: Path, *args: str, version: str | None = None) -> str:
    env = {k: v for k, v in os.environ.items() if k != "TEFTERI_RELEASE_VERSION"}
    if version is not None:
        env["TEFTERI_RELEASE_VERSION"] = version
    return subprocess.run(
        ["bash", str(SCRIPT), *args], cwd=repo, env=env, check=True, capture_output=True, text=True
    ).stdout.strip()


def _tag(repo: Path, *names: str) -> None:
    for name in names:
        _git(repo, "tag", name)
    # A commit after the tags, so that HEAD itself has no version tag.
    _git(repo, "commit", "-q", "--allow-empty", "-m", "later")


def test_the_first_release_without_a_tag(repo: Path) -> None:
    assert run(repo, "next") == "0.0.1"


def test_the_patch_goes_up_by_one(repo: Path) -> None:
    _tag(repo, "v1.2.3")
    assert run(repo, "next") == "1.2.4"


def test_a_tag_without_a_patch_number_starts_at_patch_one(repo: Path) -> None:
    _tag(repo, "v3.3")
    assert run(repo, "next") == "3.3.1"


def test_a_tag_that_is_put_in_by_hand_sets_the_new_base(repo: Path) -> None:
    # The releases were 1.2.x. The person tags 1.3: the next release is 1.3.1, and then 1.3.2.
    _tag(repo, "v1.2.0", "v1.2.7", "v1.3")
    assert run(repo, "next") == "1.3.1"
    _tag(repo, "v1.3.1")
    assert run(repo, "next") == "1.3.2"


def test_the_newest_is_the_highest_version_and_not_the_latest_tag(repo: Path) -> None:
    _tag(repo, "v1.10.0")
    _tag(repo, "v1.9.0")  # made later, but lower
    assert run(repo, "next") == "1.10.1"


def test_the_v_is_optional_and_other_tags_are_ignored(repo: Path) -> None:
    _tag(repo, "2.0.4", "nightly", "nightly-0.3.0.abc1234.post5", "v9", "release-3", "v10.0.0-rc1")
    # "v9" has no minor number, so it is not a version. A version needs at least X.Y.
    assert run(repo, "next") == "2.0.5"


def test_head_that_has_a_version_tag_needs_no_release(repo: Path) -> None:
    _git(repo, "tag", "v1.2.3")
    assert run(repo, "next-outputs").splitlines() == [
        "needed=false",
        "version=1.2.4",
        "tag=v1.2.4",
    ]


def test_a_new_commit_needs_a_release(repo: Path) -> None:
    _tag(repo, "v1.2.3")
    assert run(repo, "next-outputs").splitlines() == [
        "needed=true",
        "version=1.2.4",
        "tag=v1.2.4",
    ]


def test_forms_of_the_release_version(repo: Path) -> None:
    assert run(repo, "release", version="1.5.0") == "1.5.0"
    assert run(repo, "release", "pep440", version="1.5.0") == "1.5.0"
    assert run(repo, "release", "flutter", version="1.5.0") == "1.5.0+1"  # one commit
    from packaging.version import Version

    assert str(Version("1.5.0")) == "1.5.0"


def test_release_without_a_version_reads_the_tag_at_head(repo: Path) -> None:
    with pytest.raises(subprocess.CalledProcessError):
        run(repo, "release")
    _git(repo, "tag", "v1.6.0")
    assert run(repo, "release") == "1.6.0"


def test_a_version_that_is_not_x_y_z_is_refused(repo: Path) -> None:
    for bad in ("1.5", "v1.5.0", "1.5.0.post1"):
        with pytest.raises(subprocess.CalledProcessError):
            run(repo, "release", version=bad)
