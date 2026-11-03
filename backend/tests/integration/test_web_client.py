"""Serving the built web client at / next to the API."""

from collections.abc import Callable
from pathlib import Path

from httpx import ASGITransport, AsyncClient

from tefteri.config import Settings
from tefteri.main import create_app


async def test_serves_web_client_without_shadowing_the_api(
    make_settings: Callable[..., Settings], tmp_path: Path
) -> None:
    (tmp_path / "index.html").write_text("<html>tefteri</html>")
    (tmp_path / "main.dart.js").write_text("// app")
    app = create_app(make_settings(web_dir=tmp_path))
    async with (
        app.router.lifespan_context(app),
        AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as c,
    ):
        index = await c.get("/")
        assert index.status_code == 200 and "tefteri" in index.text
        assert (await c.get("/main.dart.js")).text == "// app"
        assert (await c.get("/health")).json() == {"status": "ok"}
        assert (await c.get("/api/v1/auth/me")).json()["code"] == "not_authenticated"


async def test_no_web_client_by_default(client: AsyncClient) -> None:
    assert (await client.get("/")).status_code == 404
