"""pytest-alembic configuration: a throw-away synchronous SQLite database per test."""

from collections.abc import Iterator
from pathlib import Path

import pytest
from sqlalchemy import Engine, create_engine


@pytest.fixture
def alembic_config() -> dict[str, str]:
    """Locate the Alembic script directory relative to the backend root."""
    return {"script_location": str(Path(__file__).parents[2] / "migrations")}


@pytest.fixture
def alembic_engine(tmp_path: Path) -> Iterator[Engine]:
    """Provide an empty SQLite engine for the migration tests."""
    engine = create_engine(f"sqlite:///{tmp_path / 'migrations.db'}")
    yield engine
    engine.dispose()
