# Data Model: Tefteri

All user-owned entities carry `user_id`; every query is scoped by it (FR-015). IDs are UUIDs.
Timestamps are UTC with an explicit time zone on the user.

## User
- `id`, `username` (unique), `password_hash` (nullable for SSO-only users), `oidc_subject`
  (nullable, unique with issuer), `is_admin`, `timezone`, `created_at`, `disabled`.
- Rules: admin created from deployment config; only admins create users (FR-022).

## Connection
- `id`, `user_id`, `kind` (`tasks` | `calendar` | `notes`), `provider` (`vikunja` |
  `google_calendar` | `trilium`), `display_name`, `default_context` (`work` | `life`),
  `encrypted_credentials`, `settings` (e.g. base URL, selected calendars/projects),
  `status` (`ok` | `needs_attention` | `error`), `last_sync_at`, `last_sync_outcome`.
- Relationships: one user has many connections, several of each kind allowed (FR-001).
- Sub-scope: **SourceContainer** (`connection_id`, `remote_id`, `name`, `context` override)
  represents a Vikunja project, a Google calendar or a Trilium subtree so that a whole
  container can be labelled work or life (FR-009).

## Task (cached mirror)
- `id`, `user_id`, `connection_id`, `container_id`, `remote_id`, `title`, `description`,
  `status` (`open` | `done`), `due_at`, `scheduled_start`, `scheduled_end`, `all_day`,
  `context` (nullable override), `goal_id` (nullable), `remote_version` (etag/updated),
  `sync_state`, `deleted_remotely`.
- Effective context = task override, else container context, else connection default.
- Unique: (`connection_id`, `remote_id`).

## CalendarEntry (cached mirror)
- `id`, `user_id`, `connection_id`, `container_id`, `remote_id`, `title`, `start`, `end`,
  `all_day`, `recurrence` (opaque rule), `location`, `context` override, `remote_version`,
  `sync_state`.
- Scheduled tasks are displayed with calendar entries but never stored as one (spec clarification).

## Note (cached mirror)
- `id`, `user_id`, `connection_id`, `remote_id`, `kind` (`daily` | `custom` | `process` |
  `retrospective`), `title`, `body`, `note_date` (for daily), `context`,
  `remote_version`, `sync_state`.
- Link table **TaskNoteLink** (`task_id`, `note_id`, optional anchor).

## Goal
- `id`, `user_id`, `parent_id` (nullable, hierarchy), `period_type` (`year` | `month` |
  `week`), `period_start`, `title`, `description`, `context`, `status` (`active` | `done` |
  `dropped`), `progress` (derived from children and linked tasks).
- Rules: a child's period lies inside its parent's; deleting a goal asks whether to keep or
  delete linked tasks; progress roll-up is computed, not stored by hand (FR-013).

## Plan and PeriodReview
- **Plan**: `id`, `user_id`, `period_type`, `period_start`, `title`, `summary`; groups goals
  for one period (e.g. the annual resolution plan) and is kept after the period ends (FR-016).
- **PeriodReview**: `id`, `plan_id`, `generated_at`, `planned_count`, `completed_count`,
  `carried_over` (list of goal/task ids), `retrospective_note_id` (nullable).
- Rules: review data is computed from goals and tasks as of generation time and snapshotted;
  a retrospective is also written to the notes backend (FR-017).

## SyncRun and Conflict
- **SyncRun**: `id`, `user_id`, `connection_id`, `started_at`, `finished_at`, `outcome`,
  `counts` (created/updated/deleted), `error`.
- **Conflict**: `id`, `user_id`, `entity_type`, `entity_id`, `local_snapshot`,
  `remote_snapshot`, `created_at`, `resolved_at`, `resolution` (`keep_local` |
  `keep_remote`). An item with an open conflict is never overwritten (FR-008).

## State transitions
- Item `sync_state`: `synced` → `conflict` (remote changed since the cached version) →
  `synced` after the user's resolution; any → `deleted_remotely` after a sync that no longer finds
  it. A failed write to an unreachable app changes nothing locally and is reported to the user.
- Connection `status`: `ok` ↔ `needs_attention` (expired/revoked credentials) ↔ `error`
  (unreachable).
