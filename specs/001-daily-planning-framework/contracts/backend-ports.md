# Backend Port Contracts

Core code depends only on these interfaces (`tefteri.domain.ports`). Each adapter lives in
`tefteri.adapters.<name>` and is the only code that knows its app's API. `tach` forbids
imports from `domain`, `services` or `api` into a specific adapter and the reverse.

All methods are `async`. Adapters raise `BackendUnavailable`, `AuthExpired`,
`NotSupported(capability)` or `RemoteConflict` and never return partial silent failures.

## Common
- `capabilities() -> set[Capability]` e.g. `task_time`, `recurring`, `note_append`.
  Unsupported actions are reported to the user (spec edge case) instead of dropping data.
- `list_containers() -> list[Container]` (project, calendar or note subtree).
- `check_connection() -> ConnectionStatus`.

## TaskBackend (adapter: Vikunja)
- `list_tasks(container, since: Version | None) -> TaskPage`
- `get_task(remote_id)`, `create_task(draft)`, `update_task(remote_id, patch, expected_version)`,
  `delete_task(remote_id)`, `complete_task(remote_id)`.
- `set_schedule(remote_id, start, end, expected_version)` - writes the date/time to the task.

## CalendarBackend (adapter: Google Calendar)
- One backend instance per Google account credential; `list_containers()` returns that
  account's calendars (personal, shared family, company).
- `list_entries(container, from, to, sync_token | None) -> EntryPage`
- `create_entry`, `update_entry(remote_id, patch, expected_version)`, `delete_entry`.

## NoteBackend (adapter: Trilium Next)
- `list_notes(container, since)`, `get_note(remote_id)`, `create_note(draft)`,
  `update_note(remote_id, patch, expected_version)`, `delete_note(remote_id)`.
- `get_or_create_daily(date) -> Note`, `append(remote_id, text)`.

## Contract tests
A shared contract test suite is parametrised over every adapter against recorded HTTP
fixtures (and an in-memory fake used by services and e2e tests). A new adapter passes the same
suite without changes to core code (FR-020).
