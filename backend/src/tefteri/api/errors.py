"""API error model ``{"detail": ..., "code": ...}``."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse
from starlette.exceptions import HTTPException as StarletteHTTPException


class ApiError(Exception):
    """An error with an HTTP status and a stable machine-readable code."""

    def __init__(
        self, status_code: int, code: str, detail: str, headers: dict[str, str] | None = None
    ) -> None:
        """Store status, code, message and optional headers."""
        super().__init__(detail)
        self.status_code = status_code
        self.code = code
        self.detail = detail
        self.headers = headers


def install_error_handlers(app: FastAPI) -> None:
    """Register handlers so every error uses the documented body."""

    @app.exception_handler(ApiError)
    async def _api_error(_: Request, exc: ApiError) -> JSONResponse:
        return JSONResponse(
            {"detail": exc.detail, "code": exc.code},
            status_code=exc.status_code,
            headers=exc.headers,
        )

    @app.exception_handler(StarletteHTTPException)
    async def _http_error(_: Request, exc: StarletteHTTPException) -> JSONResponse:
        return JSONResponse(
            {"detail": str(exc.detail), "code": f"http_{exc.status_code}"},
            status_code=exc.status_code,
        )
