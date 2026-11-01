"""Run the migrations on a real PostgreSQL database (needs TEFTERI_TEST_POSTGRES_URL)."""

import os
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config

URL = os.environ.get("TEFTERI_TEST_POSTGRES_URL")

pytestmark = [
    pytest.mark.postgres,
    pytest.mark.skipif(URL is None, reason="TEFTERI_TEST_POSTGRES_URL is not set"),
]


def test_upgrade_head_then_downgrade_base(monkeypatch: pytest.MonkeyPatch) -> None:
    assert URL is not None
    monkeypatch.setenv("TEFTERI_DATABASE_URL", URL)
    config = Config(str(Path(__file__).parents[2] / "alembic.ini"))
    config.set_main_option("script_location", str(Path(__file__).parents[2] / "migrations"))
    command.upgrade(config, "head")
    command.downgrade(config, "base")
