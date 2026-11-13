"""The annual review over the real server and a live task app (spec 008, T045)."""

import uuid

import pytest
from httpx import AsyncClient

from tefteri.api.routers.annual_review import AnnualReviewOut, NoteDeletedOut, NoteWriteOut

pytestmark = pytest.mark.live


async def test_annual_review_over_http(monthly_http_server: AsyncClient, real) -> None:
    api = monthly_http_server
    tag = uuid.uuid4().hex[:8]
    project = await real.client.put(
        f"{real.base}/projects", headers=real.headers, json={"title": f"Review theme {tag}"}
    )
    assert project.status_code == 201, project.text

    for year in (1999, 2101):
        invalid = await api.get(f"/annual-review/{year}")
        assert invalid.status_code == 422

    # A year with no stored data still opens.
    empty = await api.get("/annual-review/2024")
    assert empty.status_code == 200, empty.text
    body = AnnualReviewOut.model_validate(empty.json())
    assert body.empty is not None

    current = await api.get("/annual-review/2026")
    assert current.status_code == 200, current.text
    AnnualReviewOut.model_validate(current.json())

    future = await api.get("/annual-review/2028")
    assert future.status_code == 200
    assert AnnualReviewOut.model_validate(future.json()).empty.reason.value == "future_year"

    put = await api.put(
        "/annual-review/2024/notes", json={"goal_id": None, "body": "A note over HTTP."}
    )
    assert put.status_code == 200, put.text
    NoteWriteOut.model_validate(put.json())
    deleted = await api.delete("/annual-review/2024/notes")
    assert deleted.status_code == 200, deleted.text
    NoteDeletedOut.model_validate(deleted.json())
