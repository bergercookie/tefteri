# Container deployment recipes. Call as `just deploy::<recipe>`.

# List the recipes of this module.
default:
    @just --list deploy

# Builds the web client first; the image serves it at /.
build-image:
    just frontend::build-web
    docker build -f Dockerfile -t tefteri:local ${TEFTERI_VERSION:+--build-arg TEFTERI_VERSION=$TEFTERI_VERSION} ..

up:
    docker compose -f compose.yaml up -d

up-postgres:
    docker compose -f compose.yaml --profile postgres up -d

down:
    docker compose -f compose.yaml --profile postgres down

# Build the image and run the smoke test against it (needs Docker).
smoke: build-image
    cd ../backend && TEFTERI_SMOKE_IMAGE=tefteri:local uv run pytest tests/smoke

# Tag the local image and push it to ghcr.io/bergercookie/tefteri (needs docker login).
push-image +tags:
    for tag in {{ tags }}; do docker tag tefteri:local "ghcr.io/bergercookie/tefteri:$tag" && docker push "ghcr.io/bergercookie/tefteri:$tag"; done
