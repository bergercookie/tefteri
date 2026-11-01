"""Effective-context resolution: item override, then container, then connection default."""

import uuid

from tefteri.services.context import ContextFilter, ContextMaps

CONN, CONT = uuid.uuid4(), uuid.uuid4()


def maps(container: str | None) -> ContextMaps:
    return ContextMaps({CONT: container}, {CONN: "life"})


def test_item_override_wins() -> None:
    assert maps("work").effective("life", CONT, CONN) == ("life", "item")
    assert maps("life").effective("work", CONT, CONN)[0] == "work"


def test_container_beats_connection_default() -> None:
    assert maps("work").effective(None, CONT, CONN) == ("work", "container")


def test_connection_default_marks_the_item_unclassified() -> None:
    assert maps(None).effective(None, CONT, CONN) == ("life", "connection")
    assert maps(None).effective(None, None, CONN) == ("life", "connection")


def test_filter_matching() -> None:
    m = maps("work")
    assert m.matches(ContextFilter.ALL, None, CONT, CONN)
    assert m.matches(ContextFilter.WORK, None, CONT, CONN)
    assert not m.matches(ContextFilter.LIFE, None, CONT, CONN)
