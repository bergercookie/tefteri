# Deployment

This guide is for administrators and developers. It shows how to set up tefteri for more than one user.
Tefteri reads its settings from environment variables that start with `TEFTERI_`. It also reads a `.env` file.

## Settings

| Variable | Default | Meaning |
| --- | --- | --- |
| `TEFTERI_ADMIN_USERNAME` | `admin` | Username of the first administrator. |
| `TEFTERI_ADMIN_PASSWORD_HASH` | none | Argon2 hash of the administrator password. You must set it. |
| `TEFTERI_SECRET_KEY` | none | Secret text of 16 characters or more. You must set it. |
| `TEFTERI_DATABASE_URL` | `sqlite+aiosqlite:///./tefteri.db` | Database address. |
| `TEFTERI_PUBLIC_URL` | none | Public base address of the server. |
| `TEFTERI_WEB_DIR` | none | Folder of the built web client. If you set it, the server gives the web client at `/`. |
| `TEFTERI_GOOGLE_CLIENT_ID` | none | Google OAuth client ID. |
| `TEFTERI_GOOGLE_CLIENT_SECRET` | none | Google OAuth client secret. |
| `TEFTERI_SESSION_LIFETIME_SECONDS` | `28800` | Session length. The default is 8 hours. |
| `TEFTERI_LOGIN_MAX_FAILURES` | `5` | Wrong passwords that cause a block. |
| `TEFTERI_LOGIN_WINDOW_SECONDS` | `900` | Time span in which tefteri counts the wrong passwords. |
| `TEFTERI_LOGIN_BLOCK_SECONDS` | `900` | Length of the sign-in block. |

The file `deploy/.env.example` lists the main variables. Copy it to `.env` and fill in the values.
Never commit real values to the repository.

## Create the first administrator

Tefteri does not accept a raw password in the settings. It accepts only an Argon2 hash.
If the hash is missing or not valid, the server refuses to start.

1. Run `just hash-password` in the repository root.
2. Type the password when the script asks for it.
3. Copy the hash that the script prints.
4. Set `TEFTERI_ADMIN_USERNAME` to the username that you want.
5. Set `TEFTERI_ADMIN_PASSWORD_HASH` to the hash.

The hash contains `$` characters. In a `.env` file for Docker Compose, put the hash between
single quotes, for example `TEFTERI_ADMIN_PASSWORD_HASH='$argon2id$v=19$...'`. Without the quotes,
Docker Compose changes the hash and the server refuses to start.

The administrator signs in with the password and then adds the other users. There is no self-registration.
The user guide `accounts-and-sign-in` shows the steps in the application.

## Secret key

Set `TEFTERI_SECRET_KEY` to a long random text. The minimum length is 16 characters.
Tefteri also uses this key to protect the app tokens that it stores.
If you change the key, the stored app tokens stop working. Users must connect their apps again.

## Database

Set `TEFTERI_DATABASE_URL` to one of these types of address:

- SQLite: `sqlite+aiosqlite:////data/tefteri.db`
- PostgreSQL: `postgresql+asyncpg://user:password@host:5432/tefteri`

SQLite is the default and is good for a small installation. Use PostgreSQL for a shared server.
Keep the database in a folder that you back up.

## Run the migrations

Run the migrations before the first start and after each update.

1. Go to the repository root.
2. Set the settings in your environment or in `.env`.
3. Run `just backend::migrate`.

## Google Calendar

Users who connect Google Calendar need an OAuth client.

1. Create an OAuth client in the Google Cloud console.
2. Add this redirect address to the client: `<public address>/api/v1/connections/google/callback`.
3. Set `TEFTERI_GOOGLE_CLIENT_ID` and `TEFTERI_GOOGLE_CLIENT_SECRET`.
4. Set `TEFTERI_PUBLIC_URL` to the public address, for example `https://tefteri.example.com`.

If you do not set `TEFTERI_PUBLIC_URL`, tefteri builds the redirect address from the incoming request.
This can give a wrong address behind a reverse proxy. The address in Google must match exactly.

## Sign-in and session settings

Sessions end after `TEFTERI_SESSION_LIFETIME_SECONDS` seconds. The default is 28800 seconds (8 hours).

Tefteri blocks an account when it sees `TEFTERI_LOGIN_MAX_FAILURES` wrong passwords inside
`TEFTERI_LOGIN_WINDOW_SECONDS` seconds. The block lasts `TEFTERI_LOGIN_BLOCK_SECONDS` seconds.
The defaults are 5 wrong passwords, 15 minutes and 15 minutes.

## Run tefteri in a container

The folder `deploy/` has the container files:

- `Dockerfile` builds the server image. The image runs the migrations at each start and then
  starts the server on port 8000. The server also gives the web client at `/`.
- `compose.yaml` starts the server. The `postgres` profile also starts PostgreSQL.
- `.env.example` is the template for the settings.
- `deploy.just` has the recipes. Call them as `just deploy::<recipe>`.

Tagged releases publish the image as `ghcr.io/bergercookie/tefteri:<version>` and
`ghcr.io/bergercookie/tefteri:latest`. The nightly build publishes
`ghcr.io/bergercookie/tefteri:nightly`.

To run the server with SQLite:

1. Copy `deploy/.env.example` to `deploy/.env`. Fill in the values.
2. Run `just deploy::build-image`, or set `TEFTERI_IMAGE` in `.env` to a published image.
3. Run `just deploy::up`.
4. Open `http://localhost:8000/health`. The answer is `{"status": "ok"}`.
5. Open `http://localhost:8000/` in your browser to use the web client.

`just deploy::build-image` builds the web client before the image. Thus it needs Flutter. Run it
in `devbox shell`.

The SQLite database is in the `data` volume, at `/data/tefteri.db`. Back up this volume.

To use PostgreSQL:

1. In `deploy/.env`, set `POSTGRES_PASSWORD`.
2. In `deploy/.env`, set `TEFTERI_DATABASE_URL` to
   `postgresql+asyncpg://tefteri:<POSTGRES_PASSWORD>@postgres:5432/tefteri`.
3. Run `just deploy::up-postgres`.

To stop the containers, run `just deploy::down`. The volumes stay.

To check an image, run `just deploy::smoke`. The recipe builds the image, starts it and checks
the health, the version, the web client and the sign-in. It also starts `compose.yaml` with a
`.env` made from `.env.example`, as `just deploy::up` does. It uses a different project name and
port, so it does not change a running installation. The CI runs this recipe for each pull request.

## Reverse proxy

Put a reverse proxy in front of tefteri to give users an HTTPS address.

1. Use HTTPS on the public address.
2. Send all requests to the tefteri server, including the paths that start with `/api/`.
3. Pass the original host name and protocol to tefteri.
4. Set `TEFTERI_PUBLIC_URL` to the public HTTPS address.
