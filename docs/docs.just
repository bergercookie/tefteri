# Documentation recipes. Call as `just docs::build`.

build:
    uv run --with-requirements requirements.txt sphinx-build -W -b html . _build/html
