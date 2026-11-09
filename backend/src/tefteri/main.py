"""FastAPI application factory."""

from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from datetime import UTC, datetime
from importlib.metadata import PackageNotFoundError, version

import httpx
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from starlette.responses import Response
from starlette.types import Scope

from tefteri.adapters.google_calendar import GoogleCalendarBackend
from tefteri.adapters.trilium import TriliumNoteBackend
from tefteri.adapters.vikunja import VikunjaTaskBackend
from tefteri.api.errors import install_error_handlers
from tefteri.api.errors_map import install_service_error_handlers
from tefteri.api.routers import auth as auth_router
from tefteri.api.routers import calendar as calendar_router
from tefteri.api.routers import conflicts as conflicts_router
from tefteri.api.routers import connections as connections_router
from tefteri.api.routers import notes as notes_router
from tefteri.api.routers import planning as planning_router
from tefteri.api.routers import reviews as reviews_router
from tefteri.api.routers import settings as settings_router
from tefteri.api.routers import sync as sync_router
from tefteri.api.routers import tasks as tasks_router
from tefteri.api.routers import users as users_router
from tefteri.api.routers import views as views_router
from tefteri.api.routers import weekly as weekly_router
from tefteri.auth.service import AuthService
from tefteri.auth.throttle import LoginThrottle
from tefteri.config import Settings
from tefteri.db.base import Base
from tefteri.db.session import create_engine, create_session_factory, session_scope
from tefteri.domain.enums import ConnectionKind
from tefteri.security.crypto import TokenCipher
from tefteri.services.calendar import CalendarService
from tefteri.services.conflicts import ConflictService
from tefteri.services.connections import AdapterRegistry, ConnectionService
from tefteri.services.goals import GoalService
from tefteri.services.google_oauth import GoogleOAuth
from tefteri.services.notes import NoteService
from tefteri.services.projects import ProjectService
from tefteri.services.reviews import ReviewService
from tefteri.services.sync import SyncService
from tefteri.services.tasks import TaskService
from tefteri.services.users import UserService
from tefteri.services.weekly import WeeklyService


def default_registry(cfg: Settings, http: httpx.AsyncClient) -> AdapterRegistry:
    """Register the built-in adapters (Vikunja, Google Calendar, Trilium Next)."""
    registry = AdapterRegistry()
    registry.register(
        "vikunja",
        ConnectionKind.TASKS,
        lambda s, c: VikunjaTaskBackend(http, s["base_url"], c["token"], s.get("timezone", "UTC")),
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


class _WebFiles(StaticFiles):
    """The web client, served so that a browser never keeps an old copy of the app.

    The browser asks the server before it reuses a file (ETag). An update of the server then
    shows at once.
    """

    async def get_response(self, path: str, scope: Scope) -> Response:
        response = await super().get_response(path, scope)
        response.headers["Cache-Control"] = "no-cache"
        return response


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
    app.state.clock = lambda: datetime.now(UTC)
    app.state.session_factory = factory
    app.state.auth_service = auth_service
    app.state.connection_service = connection_service
    sync_service = SyncService(connection_service)
    app.state.sync_service = sync_service
    task_service = TaskService(connection_service)
    app.state.task_service = task_service
    project_service = ProjectService(connection_service)
    app.state.project_service = project_service
    app.state.weekly_service = WeeklyService(
        task_service, connection_service, sync_service, project_service
    )
    app.state.goal_service = GoalService(task_service)
    app.state.calendar_service = CalendarService(connection_service)
    note_service = NoteService(connection_service)
    app.state.note_service = note_service
    app.state.review_service = ReviewService(note_service)
    app.state.conflict_service = ConflictService(connection_service)
    app.state.user_service = UserService()
    app.state.google_oauth = (
        GoogleOAuth(http, cfg.google_client_id, cfg.google_client_secret, cfg.secret_key)
        if cfg.google_client_id and cfg.google_client_secret
        else None
    )
    install_error_handlers(app)
    install_service_error_handlers(app)

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

    for r in (
        auth_router,
        connections_router,
        sync_router,
        tasks_router,
        calendar_router,
        notes_router,
        views_router,
        conflicts_router,
        planning_router,
        reviews_router,
        weekly_router,
        users_router,
        settings_router,
    ):
        app.include_router(r.router, prefix="/api/v1")
    # Mounted last so the API routes above take precedence over the files.
    if cfg.web_dir is not None:
        app.mount("/", _WebFiles(directory=cfg.web_dir, html=True), name="web")
    return app
