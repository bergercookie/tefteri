"""Colors that an app gives to its projects and calendars."""

import re

_HEX = re.compile(r"^#?([0-9a-fA-F]{6})$")


def normalize_color(value: object) -> str | None:
    """Return ``value`` as ``#rrggbb`` in lower case, or ``None`` when it is not a color.

    Google sends ``#d50000``. Vikunja sends ``d50000`` (no ``#``), or an empty text for a project
    with no color. Anything else is left out, so that a client never gets a text that is not a
    color.
    """
    match = _HEX.match(value) if isinstance(value, str) else None
    return f"#{match.group(1).lower()}" if match else None
