"""Write the OpenAPI document of the API: ``python -m tefteri.openapi <path>``.

``just backend::openapi`` writes ``docs/openapi.json``; a test fails when that file is out of
date.
"""

import json
import sys
from pathlib import Path
from typing import Any

from tefteri.auth.passwords import hash_password
from tefteri.config import Settings
from tefteri.main import create_app


def openapi_document() -> dict[str, Any]:
    """Return the OpenAPI document. The settings are placeholders; nothing connects."""
    settings = Settings(
        _env_file=None,
        admin_password_hash=hash_password("placeholder only"),
        secret_key="placeholder-secret-key",  # noqa: S106 - not a real secret
        database_url="sqlite+aiosqlite:///:memory:",
    )
    return create_app(settings).openapi()


def render() -> str:
    """Return the document as stable, indented JSON."""
    return json.dumps(openapi_document(), indent=2, sort_keys=True) + "\n"


def main() -> None:
    """Write the document to the path given on the command line."""
    if len(sys.argv) != 2:
        raise SystemExit("usage: python -m tefteri.openapi <output.json>")
    Path(sys.argv[1]).write_text(render(), encoding="utf-8")


if __name__ == "__main__":
    main()
