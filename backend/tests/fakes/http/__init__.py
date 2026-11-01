"""Stateful fake HTTP servers (served through ``respx``) standing in for the real apps."""

from tests.fakes.http.base import FakeHttpServer
from tests.fakes.http.google_calendar import FakeGoogleCalendar
from tests.fakes.http.trilium import FakeTrilium
from tests.fakes.http.vikunja import FakeVikunja

__all__ = ["FakeGoogleCalendar", "FakeHttpServer", "FakeTrilium", "FakeVikunja"]
