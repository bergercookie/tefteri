"""The committed ``docs/openapi.json`` matches the API."""

from pathlib import Path

from tefteri.openapi import render

SNAPSHOT = Path(__file__).parents[3] / "docs" / "openapi.json"


def test_openapi_snapshot_is_up_to_date() -> None:
    assert SNAPSHOT.exists(), "docs/openapi.json is missing: run `just backend::openapi`"
    assert SNAPSHOT.read_text(encoding="utf-8") == render(), (
        "The API changed: run `just backend::openapi` and commit docs/openapi.json"
    )
