# Container deployment recipes. Call as `just deploy::<recipe>`.

build-image:
    docker build -f Dockerfile -t tefteri:local ..

up:
    docker compose -f compose.yaml up -d

up-postgres:
    docker compose -f compose.yaml --profile postgres up -d

down:
    docker compose -f compose.yaml --profile postgres down
