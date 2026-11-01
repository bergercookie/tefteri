# Add an adapter

An adapter connects tefteri to one app. It is the only code that knows the API of that app.
The core code uses only the ports. A new adapter needs no change in the core code.

## The three ports

The ports are in `tefteri.domain.ports`. All methods are `async`.

| Port | Use | Existing adapter |
| ---- | --- | ---------------- |
| `TaskBackend` | Tasks and task schedules | Vikunja |
| `CalendarBackend` | Calendar entries | Google Calendar |
| `NoteBackend` | Notes and daily notes | Trilium Next |

Each port extends `Backend`. `Backend` has three common methods:

- `capabilities()` returns the set of optional features that the app supports.
- `list_containers()` returns the projects, calendars or note subtrees.
- `check_connection()` returns a `ConnectionHealth` value.

Read `specs/001-daily-planning-framework/contracts/backend-ports.md` for the full list of methods.

## Capabilities

A capability is an optional feature. The `Capability` enum has `task_time`, `recurring` and `note_append`.

Return only the capabilities that the app supports. If the user asks for a missing capability,
raise `NotSupported` with that capability. Tefteri then tells the user that the action is not available.
Never drop the data without a message.

## Errors

Raise only these errors from `tefteri.domain.errors`:

| Error | When to raise it |
| ----- | ---------------- |
| `BackendUnavailable` | The network fails, a request times out or the app answers with a 5xx status. |
| `AuthExpired` | The app answers with a 401 or 403 status. |
| `NotSupported` | The app does not support the capability. |
| `RemoteConflict` | The `expected_version` does not match the version in the app. |

Use the helper `request` in `tefteri.adapters.http`. It maps transport failures and HTTP statuses to these errors.
An adapter must never return a partial result and hide a failure.

`check_connection()` does not raise these errors. It returns a status:

- `ok` when the app answers.
- `needs_attention` with the detail `auth_expired` when the app refuses the credentials.
- `error` with the detail `unreachable` when the app does not answer.

## The layering rule

The `tach` tool checks the module layers. The rules are in `tach.toml`.

- `tefteri.adapters` can import only `tefteri.domain`.
- `tefteri.domain`, `tefteri.services` and `tefteri.api` must not import a specific adapter.
- Only the top-level `tefteri` package can import `tefteri.adapters`.

Run `just` to check the layers before you commit. A broken rule fails the check.

## Write the adapter

1. Create the package `backend/src/tefteri/adapters/<name>/`.
2. Add `adapter.py` with a class that implements one port. Use the shared `httpx.AsyncClient` as an argument.
3. Add `__init__.py` that exports the class in `__all__`.
4. Map every HTTP failure to a domain error. Use the `request` helper.
5. Store the version of the remote item (an ETag or an update time) in the `version` field.
6. Raise `RemoteConflict` when `expected_version` is not the current version.
7. Return the right set from `capabilities()`.

## Test the adapter

### Shared contract suite

The file `backend/tests/integration/test_backend_contracts.py` holds the contract suite.
It runs the same tests on every adapter. The tests cover create, read, update, delete,
stale versions, daily notes and an unavailable app.

To add your adapter to the suite, add a factory to the right dictionary:

- `TASK_FACTORIES`
- `CALENDAR_FACTORIES`
- `NOTE_FACTORIES`

The key is the adapter name. The value is a function that returns a backend. The suite then runs all tests on it.
Do not change the shared tests to make an adapter pass. Fix the adapter.

### Recorded HTTP fixtures

Adapter tests do not call a real app. They use `respx` to answer the HTTP requests of `httpx`.

1. Add a test module in `backend/tests/integration/adapters/`. Name it `test_<name>.py`.
2. Write a JSON sample of each response that the app sends. Record it from a real app or copy it from the API documentation.
3. Mark each test with `@respx.mock`.
4. Register each route. For example, call `respx.get(url).respond(json=sample)`.
5. Call the adapter. Check the result and the request headers.
6. Test the failure cases. Answer with 401, 403, 409, 500 and a network error. Check that the adapter raises the right error.
7. Test pagination if the API has pages.

Look at `test_vikunja.py` for a complete example.

## Register the adapter

1. Write a factory function. It takes the connection settings and the decrypted credentials. It returns your backend.
2. Register the factory in `default_registry` in `backend/src/tefteri/main.py`. Give it a provider name and a kind (`tasks`, `calendar` or `notes`).
3. Store each secret in the credentials. The server encrypts them. Never put a secret in the settings.
4. Add recorded-HTTP tests in `backend/tests/integration/adapters/`.
5. Describe the new app in `docs/user/connect-apps.md`.
6. Run `just test` and `just lint`.

## Related pages

- [Architecture](architecture.md)
