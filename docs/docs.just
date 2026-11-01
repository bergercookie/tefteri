# Documentation recipes. Call as `just docs::build`.

build:
    uv run --with-requirements requirements.txt sphinx-build -W -b html . _build/html

# Regenerate the app screenshots in docs/images/ (run by hand, not in CI).
# TZ=UTC keeps the times in the images the same on every machine.
screenshots:
    cd ../frontend && TZ=UTC flutter test --update-goldens --tags screenshots test/screenshots

# Check required guides, toctree entries, image alt text and image files.
check:
    bash ../scripts/check_docs.sh
