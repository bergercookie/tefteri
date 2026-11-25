"""A 404 from an app is its own error, not a failure to reach the app."""

import httpx
import pytest

from tefteri.adapters.http import request
from tefteri.domain.errors import BackendError, RemoteGone


async def test_a_404_answer_means_the_item_is_gone() -> None:
    transport = httpx.MockTransport(lambda _: httpx.Response(404, json={"message": "nope"}))
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(RemoteGone):
            await request(client, "GET", "http://app/api/v1/tasks/3495")


async def test_a_gone_item_is_still_a_backend_error() -> None:
    transport = httpx.MockTransport(lambda _: httpx.Response(404))
    async with httpx.AsyncClient(transport=transport) as client:
        with pytest.raises(BackendError):
            await request(client, "GET", "http://app/x")
