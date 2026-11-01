# Set up a development environment

This guide shows how to get the tools and run tefteri on your computer.

## Install the tools

Devbox gives you the same versions of the tools as the CI. The file `devbox.json` lists them,
and `devbox.lock` keeps the exact versions.

1. Install devbox. Follow the instructions on the devbox website.
2. Install Docker. Devbox does not give Docker. You need Docker for the image and for the
   PostgreSQL tests.
3. For the Linux desktop build, install the system packages in the README.
4. In the repository root, run `devbox shell`.
5. Run `just backend::install frontend::install`.

## Use just for every task

The root `justfile` is the only entry point. Do not call pytest, ruff, flutter or docker
directly. Run `just --list` to see the recipes.

Each folder has a module with its own recipes. Call a recipe as `just <module>::<recipe>`:

| Module | Examples |
| --- | --- |
| `backend` | `just backend::test`, `just backend::run`, `just backend::migrate`, `just backend::openapi` |
| `frontend` | `just frontend::test`, `just frontend::analyze`, `just frontend::build-linux` |
| `deploy` | `just deploy::build-image`, `just deploy::up`, `just deploy::smoke` |
| `docs` | `just docs::build`, `just docs::screenshots` |
| `packaging` | `just packaging::deb`, `just packaging::appimage`, `just packaging::apk` |

The root recipes `lint`, `test`, `build` and `run` call the module recipes.

## Run the server

1. Run `just hash-password`. Type a password. Copy the hash.
2. Set the settings. Refer to [Deployment](deployment.md).

   ```sh
   export TEFTERI_ADMIN_PASSWORD_HASH='<the hash>'
   export TEFTERI_SECRET_KEY='<16 or more characters>'
   ```

3. Run `just backend::migrate`.
4. Run `just run`. The server listens on `http://localhost:8000`.

## Run the client

The client reads the server address at build time. The default is
`http://localhost:8000/api/v1`.

1. Go to the `frontend` folder.
2. Run `flutter run -d linux`. For another server, add
   `--dart-define=TEFTERI_API=https://host/api/v1`.

This is the one place where you call `flutter` directly: `flutter run` is interactive and has
no `just` recipe.

## Check your change

Before you open a pull request, run these recipes:

1. `just lint`. It runs all checks in `.pre-commit-config.yaml`, including Vale for the prose.
2. `just test`. It runs the backend and the frontend tests.
3. `just docs::build`. It builds the documentation and fails on a warning.

Refer to [Tests](testing.md) for the test types.
