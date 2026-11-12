"""Map service errors to the API error model."""

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse

from tefteri.services.errors import (
    BackendProblem,
    Conflict,
    Invalid,
    NoSuchVersion,
    NotFound,
)

_STATUS = {
    "backend_unavailable": 502,
    "auth_expired": 502,
    "not_saved": 502,
    "not_supported": 409,
    "remote_conflict": 409,
}


def install_service_error_handlers(app: FastAPI) -> None:
    """Register handlers for ``BackendProblem``, ``NotFound``, ``Conflict`` and ``Invalid``."""

    @app.exception_handler(BackendProblem)
    async def _problem(_: Request, exc: BackendProblem) -> JSONResponse:
        return JSONResponse(
            {
                "detail": exc.message,
                "code": exc.code,
                "connection": exc.connection_name,
                **exc.extra,
            },
            status_code=_STATUS.get(exc.code, 502),
        )

    @app.exception_handler(NoSuchVersion)
    async def _no_such_version(_: Request, __: NoSuchVersion) -> JSONResponse:
        return JSONResponse(
            {"detail": "No such review version.", "code": "no_such_version"},
            status_code=404,
        )

    @app.exception_handler(NotFound)
    async def _not_found(_: Request, __: NotFound) -> JSONResponse:
        return JSONResponse({"detail": "Not found", "code": "not_found"}, status_code=404)

    @app.exception_handler(Conflict)
    async def _conflict(_: Request, exc: Conflict) -> JSONResponse:
        return JSONResponse({"detail": exc.message, "code": exc.code, **exc.extra}, status_code=409)

    @app.exception_handler(Invalid)
    async def _invalid(_: Request, exc: Invalid) -> JSONResponse:
        return JSONResponse({"detail": str(exc), "code": exc.code}, status_code=422)
