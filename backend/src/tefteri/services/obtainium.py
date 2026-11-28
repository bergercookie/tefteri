"""The Obtainium link that installs the Android app matching this server.

Obtainium is an Android app that installs and updates apps from their GitHub
releases. A link of the form ``obtainium://app/<json>`` adds an app to it. The
link made here is pinned to the release of the version that the server runs, so
the app and the server stay in step: after the server is updated, the new link
(shown in Settings) points at the new release.
"""

import json
import re
from dataclasses import dataclass
from urllib.parse import quote

import segno

APP_ID = "dev.bergercookie.tefteri"
"""The Android application id of the app."""

_STABLE = re.compile(r"^\d+\.\d+\.\d+$")
# A nightly package version: 1.4.0.post3+a1b2c3d (see scripts/version.sh).
_NIGHTLY = re.compile(r"^(\d+\.\d+\.\d+)\.post(\d+)\+([0-9a-f]+)$")


@dataclass(frozen=True)
class AppRelease:
    """The release of the Android app that matches a server version."""

    version: str
    """The server version, as the server reports it."""
    title: str
    """The title of the GitHub release, which tells releases apart."""
    prerelease: bool
    """True for a nightly build."""
    page_url: str
    """The page of the release on GitHub, or of the releases when it is not known."""


def release_for(version: str, repo: str) -> AppRelease | None:
    """Find the release that holds the app of server ``version``.

    Returns ``None`` when the server is not a published build (for example a
    development checkout), because no release matches it then.
    """
    base = f"https://github.com/{repo}"
    if _STABLE.match(version):
        return AppRelease(version, f"v{version}", False, f"{base}/releases/tag/v{version}")
    nightly = _NIGHTLY.match(version)
    if nightly:
        stable, post, short = nightly.groups()
        image = f"{stable}.{short}.post{post}"
        return AppRelease(version, f"Nightly {image}", True, f"{base}/releases/tag/nightly-{image}")
    return None


def obtainium_link(release: AppRelease, repo: str) -> str:
    """Build the ``obtainium://`` link that adds the app, pinned to ``release``."""
    owner = repo.split("/")[0]
    settings = {
        "includePrereleases": release.prerelease,
        "fallbackToOlderReleases": False,
        "filterReleaseTitlesByRegEx": "^" + re.escape(release.title).replace("\\ ", " ") + "$",
        "apkFilterRegEx": r"\.apk$",
        "autoApkFilterByArch": True,
        "trackOnly": False,
    }
    app = {
        "id": APP_ID,
        "url": f"https://github.com/{repo}",
        "author": owner,
        "name": "Tefteri",
        "preferredApkIndex": 0,
        "additionalSettings": json.dumps(settings, separators=(",", ":")),
    }
    return "obtainium://app/" + quote(json.dumps(app, separators=(",", ":")), safe="")


def qr_rows(text: str) -> list[str]:
    """Draw ``text`` as a QR code: one string of ``0`` and ``1`` per row, no quiet zone."""
    code = segno.make(text, error="m", micro=False)
    return ["".join("1" if cell else "0" for cell in row) for row in code.matrix]
