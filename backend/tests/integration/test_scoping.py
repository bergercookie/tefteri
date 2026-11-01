"""Repository user scoping."""

import uuid

from tefteri.db.base import Base
from tefteri.db.models.connection import Connection
from tefteri.db.models.user import User
from tefteri.db.repositories.connections import ConnectionRepository
from tefteri.db.session import create_engine, create_session_factory


async def test_repository_never_returns_other_users_rows() -> None:
    engine = create_engine("sqlite+aiosqlite:///:memory:")
    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    async with create_session_factory(engine)() as s:
        a, b = User(username="a"), User(username="b")
        s.add_all([a, b])
        await s.flush()
        repo_a, repo_b = ConnectionRepository(s, a.id), ConnectionRepository(s, b.id)
        mine = await repo_a.add(
            Connection(kind="tasks", provider="vikunja", display_name="V", user_id=uuid.uuid4())
        )
        assert mine.user_id == a.id  # owner is forced by the repository
        assert await repo_a.get(mine.id) is not None
        assert await repo_b.get(mine.id) is None
        assert list(await repo_b.list()) == []
    await engine.dispose()
