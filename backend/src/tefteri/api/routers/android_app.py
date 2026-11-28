"""The link and QR code that install the Android app of this server's version in Obtainium."""

from importlib.metadata import PackageNotFoundError, version

from fastapi import APIRouter, Request
from pydantic import BaseModel

from tefteri.api.deps import SessionUser
from tefteri.services.obtainium import obtainium_link, qr_rows, release_for

router = APIRouter(prefix="/me/android-app", tags=["android-app"])


class AndroidAppOut(BaseModel):
    """How to install the Android app that matches this server."""

    version: str
    """The version of the server."""
    available: bool
    """False when the server is not a published build, so there is no release to point at."""
    release_url: str | None
    """The GitHub page of the release that holds the app."""
    obtainium_link: str | None
    """Opening it on the phone adds the app to Obtainium."""
    qr: list[str]
    """The QR code of ``obtainium_link``: one string of ``0``/``1`` per row; empty when n/a."""


@router.get("")
async def android_app(request: Request, user: SessionUser) -> AndroidAppOut:
    """Return the Obtainium link for the release that matches the server version."""
    del user  # any signed-in user may read it; the releases are public
    try:
        current = version("tefteri")
    except PackageNotFoundError:
        current = "unknown"
    repo = request.app.state.settings.release_repo
    release = release_for(current, repo)
    if release is None:
        return AndroidAppOut(
            version=current, available=False, release_url=None, obtainium_link=None, qr=[]
        )
    link = obtainium_link(release, repo)
    return AndroidAppOut(
        version=current,
        available=True,
        release_url=release.page_url,
        obtainium_link=link,
        qr=qr_rows(link),
    )
