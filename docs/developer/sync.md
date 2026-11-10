# Sync and conflicts

Sync starts only when the user asks for it (the Sync button, F5, or `POST /sync`). The
`SyncService` reads every connection of the user, one after the other. It copies the items into
the cache tables (`tasks`, `calendar_entries`, `notes`).

## Sync flow

```mermaid
sequenceDiagram
  actor User
  participant API as api: POST /sync
  participant Sync as SyncService
  participant DB as Cache (database)
  participant App as Connected app
  User->>API: Sync
  API->>Sync: sync_all(user)
  loop each connection
    Sync->>DB: begin nested transaction (savepoint)
    Sync->>App: list containers and items
    alt the app answers
      App-->>Sync: items
      Sync->>DB: insert new rows, update changed rows
      Sync->>DB: mark missing rows deleted_remotely
      Sync->>DB: release savepoint
    else unreachable, expired credentials or other error
      App-->>Sync: error
      Sync->>DB: roll back to savepoint
    end
    Sync->>DB: store SyncRun and connection status
  end
  Sync-->>API: one result for each connection
  API-->>User: outcome, counts and reason for each connection
```

Each connection syncs inside its own savepoint. A failure rolls back only the changes of that
connection. The other connections still sync. The result names the connection and gives a
reason: `unreachable`, `auth_expired` or `error`. The connection status changes to `error` or
`needs_attention`.

The sync does not overwrite a row in the `conflict` state. The row stays as it is until the
user solves the conflict.

## The automatic sync

The server syncs all connections of all users at a regular interval
(`TEFTERI_SYNC_INTERVAL_MINUTES`, 60 by default; 0 turns it off). `BackgroundSync` in
`services/background_sync.py` does it. The lifespan of the app starts it as a task and cancels it at
shutdown.

- The first pass comes 30 seconds after the start. Then a pass comes at each interval.
- Each connection syncs in its own session and transaction. A failing connection, or a failing
  user, never stops the others.
- A connection with the status `needs_attention` is left out. A manual sync still tries it.
- `SyncService` takes a lock for each connection. A scheduled sync, a manual sync and a double
  click on Sync of the same connection run one after the other, never at the same time.
- Each pass deletes the records of syncs (`sync_runs`) that are older than 30 days.

The server is one process. If you run more than one, each one runs its own loop. Set the interval
to 0 on all but one.

## Times

The cache holds every time as UTC. SQLite drops the time zone of a stored time, so the sync
converts each time to UTC before it stores it (`mirror.to_utc`).

- A time with an offset, such as `2026-11-02T11:00:00+02:00`, is converted. A time without an
  offset but with a named zone (Google sends `timeZone`) takes the offset of that zone. A time
  with neither is UTC.
- An all-day event comes as dates. The sync puts it on the local days of the user: midnight in
  the time zone of the user, converted to UTC (`sync.anchor_all_day`).
- The API sends every time from the cache with its zone (`...Z`). Use the type `UtcDatetime` in
  `api/schemas.py` for every such time in a response. Without the zone, a browser reads the time
  as its own local time, and the client shows every time shifted by its offset from UTC.

## Writes from tefteri

A write (for example, change a task title) goes to the connected app first. The adapter sends
the version of the cached item. When the app accepts the change, tefteri updates the cache. When
the app is unreachable or refuses the change, tefteri changes nothing and returns the error.
Tefteri does not queue changes.

## Conflict flow

```mermaid
flowchart TD
  write[User changes an item in tefteri] --> send[Adapter sends the change with the cached version]
  send --> check{Did the item change in the app?}
  check -->|no| ok[App applies the change. Tefteri updates the cache.]
  check -->|yes: remote_conflict| record[Tefteri stores a Conflict with both versions]
  record --> mark[Item sync_state becomes conflict]
  mark --> skip[Sync does not overwrite the item]
  skip --> choose{User chooses on the Conflicts screen}
  choose -->|keep_local| push[Send the local version with the current app version]
  choose -->|keep_remote| pull[Copy the app version into the cache]
  push --> done[Item sync_state becomes synced. Conflict is resolved.]
  pull --> done
```

Tefteri never solves a conflict itself. The `Conflict` row keeps the two versions until the user
chooses one. Tasks and calendar entries use this flow. For a note, tefteri returns the
`remote_conflict` error and saves nothing. The user syncs and then makes the change again.
