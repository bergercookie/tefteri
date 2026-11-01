"""FastAPI application factory."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from importlib.metadata import PackageNotFoundError, version

import httpx
from fastapi import FastAPI

from tefteri.adapters.google_calendar import GoogleCalendarBackend
from tefteri.adapters.trilium import TriliumNoteBackend
from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.api.errors import install_error_handlers
from tefteri.api.routers import auth as auth_router
from tefteri.api.routers import connections as connections_router
from tefteri.api.routers import items as items_router
from tefteri.api.routers import sync as sync_router
from tefteri.auth.service import AuthService
from tefteri.auth.throttle import LoginThrottle
from tefteri.config import Settings
from tefteri.db.base import Base
from tefteri.db.session import create_engine, create_session_factory, session_scope
from tefteri.domain.enums import ConnectionKind
from tefteri.security.crypto import TokenCipher
from tefteri.services.connections import AdapterRegistry, ConnectionService
from tefteri.services.google_oauth import GoogleOAuth
from tefteri.services.sync import SyncService


def default_registry(cfg: Settings, http: httpx.AsyncClient) -> AdapterRegistry:
    """Register the built-in adapters (Vikunja, Google Calendar, Trilium Next)."""
    registry = AdapterRegistry()
    registry.register(
        "vikunja",
        ConnectionKind.TASKS,
        lambda s, c: VikunjaTaskBackend(http, s["base_url"], c["token"]),
    )
    registry.register(
        "google_calendar",
        ConnectionKind.CALENDAR,
        lambda _s, c: GoogleCalendarBackend(
            http, cfg.google_client_id or "", cfg.google_client_secret or "", c["refresh_token"]
        ),
    )
    registry.register(
        "trilium",
        ConnectionKind.NOTES,
        lambda s, c: TriliumNoteBackend(
            http, s["base_url"], c["token"], s.get("root_note_id", "root")
        ),
    )
    return registry


def create_app(
    settings: Settings | None = None,
    registry: AdapterRegistry | None = None,
    http_client: httpx.AsyncClient | None = None,
) -> FastAPI:
    """Build the application; settings, adapter registry and HTTP client are injectable."""
    cfg = settings or Settings()
    http = http_client or httpx.AsyncClient(timeout=20)
    engine = create_engine(cfg.database_url)
    factory = create_session_factory(engine)
    auth_service = AuthService(
        LoginThrottle(cfg.login_max_failures, cfg.login_window_seconds, cfg.login_block_seconds),
        cfg.session_lifetime_seconds,
    )

    connection_service = ConnectionService(
        registry or default_registry(cfg, http), TokenCipher(cfg.secret_key)
    )

    @asynccontextmanager
    async def lifespan(_: FastAPI) -> AsyncIterator[None]:
        if cfg.create_schema:
            async with engine.begin() as conn:
                await conn.run_sync(Base.metadata.create_all)
        async with session_scope(factory) as db:
            await auth_service.bootstrap_admin(db, cfg.admin_username, cfg.admin_password_hash)
        yield
        await engine.dispose()
        if http_client is None:
            await http.aclose()

    app = FastAPI(title="tefteri", lifespan=lifespan)
    app.state.settings = cfg
    app.state.session_factory = factory
    app.state.auth_service = auth_service
    app.state.connection_service = connection_service
    app.state.sync_service = SyncService(connection_service)
    app.state.google_oauth = (
        GoogleOAuth(http, cfg.google_client_id, cfg.google_client_secret, cfg.secret_key)
        if cfg.google_client_id and cfg.google_client_secret
        else None
    )
    install_error_handlers(app)

    @app.get("/health", tags=["meta"])
    async def health() -> dict[str, str]:
        """Liveness probe."""
        return {"status": "ok"}

    @app.get("/version", tags=["meta"])
    async def app_version() -> dict[str, str]:
        """Return the server version."""
        try:
            return {"version": version("tefteri")}
        except PackageNotFoundError:
            return {"version": "unknown"}

    for r in (auth_router, connections_router, sync_router, items_router):
        app.include_router(r.router, prefix="/api/v1")
    return app
