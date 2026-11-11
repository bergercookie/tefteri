"""The classification service: tree, save, preview, undo, rename, create and label."""

import uuid

import pytest

from tefteri.domain.entities import Container
from tefteri.domain.enums import Capability, ProjectLabel
from tefteri.services.classification import Change, ProjectView
from tefteri.services.errors import BackendProblem, Conflict, Invalid, NotFound
from tests.integration.conftest import ProjectsEnv

T, M, R, X = (
    ProjectLabel.THEME,
    ProjectLabel.MILESTONE,
    ProjectLabel.MAINTENANCE,
    ProjectLabel.IGNORED,
)


async def _setup(env: ProjectsEnv) -> dict[str, uuid.UUID]:
    """Inbox (top), Website (top) with Launch and Docs inside, Garden (top); 3 open tasks."""
    await env.connect(
        Container("p2", "Website"),
        Container("p3", "Launch", "p2"),
        Container("p4", "Docs", "p2"),
        Container("p5", "Garden"),
        tasks={"p2": 2, "p5": 1},
    )
    return {name: row.id for name, row in (await env.rows()).items()}


async def _view(env: ProjectsEnv, name: str) -> ProjectView:
    async with env.db() as db:
        tree = await env.classification.tree(db, await env.user_id())
    return next(p for v in tree.connections for p in v.projects if p.row.name == name)


# -- the tree -----------------------------------------------------------------------------------


async def test_the_tree_shows_proposals_and_counts_unsorted_projects(env: ProjectsEnv) -> None:
    await _setup(env)
    async with env.db() as db:
        tree = await env.classification.tree(db, await env.user_id())
    assert tree.unsorted_count == 5
    (view,) = tree.connections
    assert (view.rename, view.restore) == (True, True)
    names = [p.row.name for p in view.projects]
    # Tree order: a project is followed by what is inside it.
    assert names == ["Garden", "Inbox", "Website", "Docs", "Launch"]
    website, launch = await _view(env, "Website"), await _view(env, "Launch")
    assert (website.proposal.label, website.proposal.reason) == (T, "top_level")
    assert (launch.proposal.label, launch.proposal.reason) == (M, "nested")
    assert launch.parent_id == website.row.id and launch.parent_theme_id == website.row.id
    assert website.parent_theme_id is None
    assert (website.open_tasks, website.subprojects) == (2, 2)
    assert website.unsorted and website.eligible and website.row.label is None


async def test_a_project_of_a_past_plan_is_proposed_as_milestone(env: ProjectsEnv) -> None:
    from datetime import date

    from tests.conftest import V1

    await _setup(env)
    garden = next(
        c
        for c in (await env.api.get(f"{V1}/weekly/{date(2030, 3, 4)}/candidates")).json()
        if c["name"] == "Garden"
    )
    past = date(2026, 11, 2)
    await env.api.post(
        f"{V1}/weekly/{past}/projects", json={"container_id": garden["container_id"]}
    )
    await env.api.post(f"{V1}/weekly/{past}/commit")
    view = await _view(env, "Garden")
    assert (view.proposal.label, view.proposal.reason) == (M, "was_committed")
    assert view.in_committed_plan


# -- saving, preview, history -------------------------------------------------------------------


async def test_a_save_writes_labels_and_appends_history_with_one_batch(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        saved = await env.classification.save(
            db,
            user,
            [Change(ids["Website"], T), Change(ids["Launch"], M), Change(ids["Garden"], R)],
            source="suggestion",
        )
    assert saved.batch_id is not None
    assert saved.effect.changed == 3
    assert sorted(saved.effect.by_change) == [
        ("none", "maintenance", 1),
        ("none", "milestone", 1),
        ("none", "theme", 1),
    ]
    rows = await env.rows()
    assert (rows["Website"].label, rows["Launch"].label, rows["Garden"].label) == (
        "theme",
        "milestone",
        "maintenance",
    )
    entries = [h for n in ("Website", "Launch", "Garden") for h in await env.history(n)]
    assert {h.batch_id for h in entries} == {saved.batch_id}
    assert {h.source for h in entries} == {"suggestion"}
    assert (await _view(env, "Website")).unsorted is False

    # One more save of one label: a new entry, and the old one is not touched.
    async with env.db() as db:
        again = await env.classification.save(db, user, [Change(ids["Website"], X)])
    history = await env.history("Website")
    assert [h.label for h in history] == ["theme", "ignored"]
    assert history[0].from_at < history[1].from_at
    assert history[1].batch_id == again.batch_id != saved.batch_id


async def test_a_save_of_the_same_label_changes_nothing(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        await env.classification.save(db, user, [Change(ids["Website"], T)])
        again = await env.classification.save(db, user, [Change(ids["Website"], T)])
    assert again.batch_id is None and again.effect.changed == 0
    assert len(await env.history("Website")) == 1


async def test_dry_run_writes_nothing_and_returns_the_same_effect(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    changes = [Change(ids["Website"], T), Change(ids["Garden"], X)]
    async with env.db() as db:
        preview = await env.classification.save(db, user, changes, dry_run=True)
    assert preview.batch_id is None and preview.effect.changed == 2
    assert all(r.label is None for r in (await env.rows()).values())
    assert await env.history("Website") == []
    async with env.db() as db:
        real = await env.classification.save(db, user, changes)
    assert real.effect == preview.effect and real.batch_id is not None


async def test_the_effect_counts_projects_in_a_committed_plan(env: ProjectsEnv) -> None:
    from datetime import date

    from tests.conftest import V1

    ids = await _setup(env)
    found = (await env.api.get(f"{V1}/weekly/{date(2030, 3, 4)}/candidates")).json()
    garden = next(c for c in found if c["name"] == "Garden")["container_id"]
    await env.api.post(f"{V1}/weekly/{date(2026, 11, 2)}/projects", json={"container_id": garden})
    await env.api.post(f"{V1}/weekly/{date(2026, 11, 2)}/commit")
    async with env.db() as db:
        preview = await env.classification.save(
            db,
            await env.user_id(),
            [Change(ids["Garden"], X), Change(ids["Inbox"], X)],
            dry_run=True,
        )
    assert (preview.effect.changed, preview.effect.in_committed_plan) == (2, 1)


async def test_a_label_can_be_set_back_to_unclassified(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        await env.classification.save(db, user, [Change(ids["Garden"], X)])
        await env.classification.save(db, user, [Change(ids["Garden"], None)])
    assert (await _view(env, "Garden")).unsorted
    assert [h.label for h in await env.history("Garden")] == ["ignored", None]


async def test_unknown_ids_and_other_users_projects_are_not_found(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    async with env.db() as db:
        with pytest.raises(NotFound):
            await env.classification.save(db, await env.user_id(), [Change(uuid.uuid4(), T)])
        with pytest.raises(NotFound):
            await env.classification.save(db, uuid.uuid4(), [Change(ids["Garden"], T)])
        with pytest.raises(Invalid):
            await env.classification.save(db, await env.user_id(), [], source="robot")


# -- undo ---------------------------------------------------------------------------------------


async def test_undo_adds_entries_that_restore_the_earlier_labels(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        await env.classification.save(db, user, [Change(ids["Garden"], T)])
        second = await env.classification.save(
            db, user, [Change(ids["Garden"], X), Change(ids["Website"], M)]
        )
    assert second.batch_id is not None
    async with env.db() as db:
        assert await env.classification.undo(db, user, second.batch_id) == 2
    rows = await env.rows()
    assert (rows["Garden"].label, rows["Website"].label) == ("theme", None)
    # Nothing was edited or removed: the undo is new entries.
    assert [h.label for h in await env.history("Garden")] == ["theme", "ignored", "theme"]
    assert [h.source for h in await env.history("Garden")] == ["user", "user", "undo"]
    assert [h.label for h in await env.history("Website")] == ["milestone", None]


async def test_a_second_undo_of_the_same_batch_is_a_conflict(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        saved = await env.classification.save(db, user, [Change(ids["Garden"], T)])
    assert saved.batch_id is not None
    async with env.db() as db:
        await env.classification.undo(db, user, saved.batch_id)
    async with env.db() as db:
        with pytest.raises(Conflict) as caught:
            await env.classification.undo(db, user, saved.batch_id)
    assert caught.value.code == "already_undone"
    assert len(await env.history("Garden")) == 2
    async with env.db() as db:
        with pytest.raises(NotFound):
            await env.classification.undo(db, user, uuid.uuid4())
        with pytest.raises(NotFound):  # another user's batch
            await env.classification.undo(db, uuid.uuid4(), saved.batch_id)


# -- rename and create (FR-013, FR-024) --------------------------------------------------------


async def test_rename_writes_to_the_app_first_and_keeps_the_label(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        await env.classification.save(db, user, [Change(ids["Garden"], R)])
        renamed = await env.classification.rename(db, user, ids["Garden"], "  Allotment ")
    assert renamed.row.name == "Allotment" and renamed.row.label == "maintenance"
    backend = env.world.tasks["default"]
    assert "Allotment" in {c.name for c in backend.containers}
    await env.sync()
    assert "Allotment" in await env.rows() and "Garden" not in await env.rows()
    # The record of the cache agrees too (other screens read it).
    async with env.db() as db:
        from sqlalchemy import select

        from tefteri.db.models.connection import SourceContainer

        names = set((await db.execute(select(SourceContainer.name))).scalars())
    assert "Allotment" in names


async def test_a_failed_rename_keeps_the_old_name(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    backend = env.world.tasks["default"]
    backend.unavailable = True
    async with env.db() as db:
        with pytest.raises(BackendProblem) as caught:
            await env.classification.rename(db, user, ids["Garden"], "Allotment")
    assert caught.value.code == "backend_unavailable"
    backend.unavailable = False
    assert "Garden" in await env.rows()
    assert "Garden" in {c.name for c in backend.containers}
    backend.supported.discard(Capability.RENAME_PROJECTS)
    async with env.db() as db:
        with pytest.raises(BackendProblem) as unsupported:
            await env.classification.rename(db, user, ids["Garden"], "Allotment")
    assert unsupported.value.code == "not_supported"
    async with env.db() as db:
        with pytest.raises(Invalid):
            await env.classification.rename(db, user, ids["Garden"], "   ")


async def test_an_orphaned_project_cannot_be_renamed(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    backend = env.world.tasks["default"]
    backend.containers = [c for c in backend.containers if c.remote_id != "p5"]
    await env.sync()
    async with env.db() as db:
        with pytest.raises(NotFound):
            await env.classification.rename(db, await env.user_id(), ids["Garden"], "Allotment")


async def test_create_and_label_writes_the_app_first_then_the_label(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        made = await env.classification.create_and_label(
            db, user, env.connection_uuid(), "Open source", None, T
        )
        child = await env.classification.create_and_label(
            db, user, env.connection_uuid(), "Release 1", made.row.id, M
        )
    assert (made.row.label, made.row.parent_remote_id) == ("theme", None)
    assert child.parent_id == made.row.id and child.parent_theme_id == made.row.id
    assert {"Open source", "Release 1"} <= {c.name for c in env.world.tasks["default"].containers}
    history = await env.history("Release 1")
    assert [(h.label, h.source) for h in history] == [("milestone", "user")]
    await env.sync()  # the sync agrees and keeps the labels
    assert (await env.rows())["Open source"].label == "theme"
    assert ids  # the earlier projects are untouched


async def test_create_records_nothing_when_the_app_fails(env: ProjectsEnv) -> None:
    await _setup(env)
    user = await env.user_id()
    count = len(await env.rows())
    env.world.tasks["default"].unavailable = True
    async with env.db() as db:
        with pytest.raises(BackendProblem):
            await env.classification.create_and_label(
                db, user, env.connection_uuid(), "Open source", None, T
            )
    env.world.tasks["default"].unavailable = False
    assert len(await env.rows()) == count
    assert "Open source" not in {c.name for c in env.world.tasks["default"].containers}
    async with env.db() as db:
        with pytest.raises(Invalid):
            await env.classification.create_and_label(db, user, env.connection_uuid(), " ", None, T)


# -- archive and restore from tefteri (FR-010, FR-027) -----------------------------------------


async def test_archive_marks_the_project_orphaned_and_restore_brings_it_back(
    env: ProjectsEnv,
) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    backend = env.world.tasks["default"]
    async with env.db() as db:
        await env.classification.save(
            db, user, [Change(ids["Website"], T), Change(ids["Launch"], M)]
        )
        archived = await env.classification.archive(db, user, ids["Website"])
    assert archived.row.orphaned_reason == "archived" and archived.row.label == "theme"
    assert {c.name for c in backend.archived} == {"Website", "Launch", "Docs"}
    rows = await env.rows()
    assert {rows[n].orphaned_reason for n in ("Website", "Launch", "Docs")} == {"archived"}
    assert rows["Launch"].label == "milestone"  # the label of what was inside is kept too
    await env.sync()  # the app does not list them; the sync must not turn "archived" into "missing"
    assert (await env.rows())["Website"].orphaned_reason == "archived"

    async with env.db() as db:
        restored = await env.classification.restore(db, user, ids["Website"])
    assert restored.row.orphaned_reason is None and restored.row.label == "theme"
    rows = await env.rows()
    assert {rows[n].orphaned_reason for n in ("Website", "Launch", "Docs")} == {None}
    assert {c.name for c in backend.containers} >= {"Website", "Launch", "Docs"}
    assert backend.archived == []
    assert (await _view(env, "Website")).eligible


async def test_a_restore_that_the_app_cannot_do_changes_nothing(env: ProjectsEnv) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    backend = env.world.tasks["default"]
    async with env.db() as db:
        await env.classification.archive(db, user, ids["Garden"])
    backend.unavailable = True
    async with env.db() as db:
        with pytest.raises(BackendProblem):
            await env.classification.restore(db, user, ids["Garden"])
    backend.unavailable = False
    assert (await env.rows())["Garden"].orphaned_reason == "archived"
    backend.supported.discard(Capability.RESTORE_PROJECTS)
    async with env.db() as db:
        with pytest.raises(BackendProblem) as caught:
            await env.classification.restore(db, user, ids["Garden"])
    assert caught.value.code == "not_supported"
    assert (await env.rows())["Garden"].orphaned_reason == "archived"


async def test_only_an_archived_project_can_be_restored_and_a_live_one_archived(
    env: ProjectsEnv,
) -> None:
    ids = await _setup(env)
    user = await env.user_id()
    async with env.db() as db:
        with pytest.raises(Invalid):
            await env.classification.restore(db, user, ids["Garden"])  # it is live
    backend = env.world.tasks["default"]
    backend.containers = [c for c in backend.containers if c.remote_id != "p5"]
    await env.sync()
    async with env.db() as db:
        with pytest.raises(Invalid):
            await env.classification.restore(db, user, ids["Garden"])  # missing, not archived
        with pytest.raises(Invalid):
            await env.classification.archive(db, user, ids["Garden"])
