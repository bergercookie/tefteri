"""The Obtainium link for the Android app of this server's version."""

import json
from unittest.mock import patch
from urllib.parse import unquote

from httpx import AsyncClient

from tefteri.services.obtainium import obtainium_link, qr_rows, release_for
from tests.conftest import V1

REPO = "bergercookie/tefteri"


def _payload(link: str) -> dict[str, object]:
    assert link.startswith("obtainium://app/")
    body: dict[str, object] = json.loads(unquote(link.removeprefix("obtainium://app/")))
    return body


def test_a_stable_server_points_at_its_tagged_release() -> None:
    release = release_for("1.5.0", REPO)
    assert release is not None and not release.prerelease
    assert release.page_url == f"https://github.com/{REPO}/releases/tag/v1.5.0"
    app = _payload(obtainium_link(release, REPO))
    assert app["id"] == "dev.bergercookie.tefteri"
    assert app["url"] == f"https://github.com/{REPO}" and app["author"] == "bergercookie"
    settings = json.loads(str(app["additionalSettings"]))
    assert settings["filterReleaseTitlesByRegEx"] == r"^v1\.5\.0$"
    assert settings["includePrereleases"] is False


def test_a_nightly_server_points_at_its_nightly_release() -> None:
    release = release_for("1.4.0.post3+a1b2c3d", REPO)
    assert release is not None and release.prerelease
    assert release.title == "Nightly 1.4.0.a1b2c3d.post3"
    assert release.page_url.endswith("/releases/tag/nightly-1.4.0.a1b2c3d.post3")
    settings = json.loads(str(_payload(obtainium_link(release, REPO))["additionalSettings"]))
    assert settings["includePrereleases"] is True
    assert settings["filterReleaseTitlesByRegEx"] == r"^Nightly 1\.4\.0\.a1b2c3d\.post3$"


def test_a_development_build_has_no_release() -> None:
    assert release_for("unknown", REPO) is None
    assert release_for("0.1.0.dev0", REPO) is None


def test_the_qr_code_is_a_square_of_zeros_and_ones() -> None:
    rows = qr_rows("obtainium://app/x")
    assert len(rows) > 20 and all(len(r) == len(rows) for r in rows)
    assert set("".join(rows)) == {"0", "1"}


async def test_the_endpoint_gives_the_link_for_the_running_version(api: AsyncClient) -> None:
    with patch("tefteri.api.routers.android_app.version", return_value="1.5.0"):
        body = (await api.get(f"{V1}/me/android-app")).json()
    assert body["available"] is True and body["version"] == "1.5.0"
    assert body["obtainium_link"].startswith("obtainium://app/")
    assert body["release_url"].endswith("/releases/tag/v1.5.0")
    assert len(body["qr"]) > 20


async def test_the_endpoint_says_so_when_the_server_is_not_a_release(api: AsyncClient) -> None:
    with patch("tefteri.api.routers.android_app.version", return_value="0.1.0.dev1"):
        body = (await api.get(f"{V1}/me/android-app")).json()
    assert body["available"] is False and body["obtainium_link"] is None and body["qr"] == []


async def test_the_endpoint_needs_a_login(api: AsyncClient) -> None:
    anon = AsyncClient(transport=api._transport, base_url="http://test")  # noqa: SLF001
    assert (await anon.get(f"{V1}/me/android-app")).status_code == 401
