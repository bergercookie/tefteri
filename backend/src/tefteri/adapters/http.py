"""Shared HTTP helpers that map transport failures to domain errors."""

from typing import Any

import httpx

from tefteri.domain.errors import AuthExpired, BackendError, BackendUnavailable, RemoteConflict


async def request(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    *,
    ok_conflict_statuses: tuple[int, ...] = (409, 412),
    **kwargs: Any,
) -> httpx.Response:
    """Send a request and translate failures.

    Raises:
        BackendUnavailable: network error, timeout or a 5xx answer.
        AuthExpired: 401 or 403 answer.
        RemoteConflict: an answer in ``ok_conflict_statuses`` (version mismatch).
        BackendError: any other 4xx answer.
    """
    try:
        response = await client.request(method, url, **kwargs)
    except httpx.TransportError as exc:
        raise BackendUnavailable(f"cannot reach {url}: {exc}") from exc
    status = response.status_code
    if status in (401, 403):
        raise AuthExpired(f"credentials rejected by {url}")
    if status in ok_conflict_statuses:
        raise RemoteConflict(f"{method} {url} conflicts with the remote version")
    if status >= 500:
        raise BackendUnavailable(f"{url} answered {status}")
    if status >= 400:
        raise BackendError(f"{method} {url} answered {status}")
    return response
