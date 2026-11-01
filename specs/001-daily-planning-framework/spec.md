# Feature Specification: Tefteri Daily Planning & Execution Framework

**Feature Branch**: `001-daily-planning-framework`

**Created**: 2026-11-01

**Status**: Draft

**Input**: User description: "Build tefteri, a planning and execution framework built around core daily work/life management concepts: task management, events and calendar, and note-taking (daily TODO notes, documentation, and structured step-by-step processes and checklists). Users bring their own existing task manager, calendar and note-taking apps and, from inside tefteri, manage tasks, see and update calendar entries, schedule tasks on the calendar (writing date/time changes back to the task manager), and keep notes about tasks in daily or custom notes. UIs have a sync button. Work and life items are explicitly separable (all / life only / work only). Daily planning and execution view plus weekly, monthly and annual views to break long-term goals into smaller chunks and schedule granular tasks. Multiple users, each with their own items and connected apps. Long-term plans (e.g. annual resolutions) and evaluation of past plans (end-of-year summaries, retrospectives)."

## Clarifications

### Session 2026-11-01

- Q: Which task manager, calendar and note-taking apps must tefteri support in its first version? → A: One app per kind: Vikunja (tasks), Google Calendar (calendar, including both personal/family calendars, such as the shared family calendar, and company/workspace accounts), and Trilium Next (notes).
- Q: When the same item has been changed both in tefteri and in the connected app since the last sync, how should tefteri resolve it? → A: Ask the user per conflict, showing both versions.
- Q: Where should tefteri's own planning data (goals, plans, work/life labels, reviews) live? → A: tefteri's own store is the source of truth for it; retrospectives are also written to Trilium Next as notes.
- Q: How do people sign in and get their own account on a tefteri installation? → A: Admin-created accounts with username and password, plus optional sign-in through an external SSO/OIDC identity provider (e.g. Authelia). The first admin is created at deployment from a pre-computed password hash; raw passwords are never accepted by configuration.
- Q: When the user schedules a task at a time, should tefteri also create a Google Calendar event? → A: No. Scheduling only sets the task's date/time in Vikunja; tefteri's calendar view shows scheduled tasks alongside Google Calendar events.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Connect my existing apps and see everything in one place (Priority: P1)

A user connects their existing task manager, calendar and note-taking app to tefteri. Their tasks, calendar entries and notes appear inside tefteri, and a sync action refreshes them from the connected apps.

**Why this priority**: Everything else depends on tefteri showing the user's real data. Without it there is no product.

**Independent Test**: Connect one app of each kind, press sync, and verify that the items shown match those in the source apps.

**Acceptance Scenarios**:

1. **Given** a user with no connected apps, **When** they connect a task manager, a calendar and a note-taking app with valid credentials, **Then** their tasks, calendar entries and notes appear in tefteri.
2. **Given** items were changed directly in a connected app, **When** the user presses sync, **Then** those changes appear in tefteri and the user sees when the last successful sync happened.
3. **Given** a connected app is unreachable, **When** the user presses sync, **Then** they see which app failed and why, and data from the other apps is still synced.

---

### User Story 2 - Daily planning and execution (Priority: P1)

Each day the user opens a daily view that combines that day's calendar entries, tasks due or scheduled, and the day's TODO note. They plan the day, work through tasks, mark them done, and jot notes against tasks as they go.

**Why this priority**: The daily view is the core "plan and execute" loop that delivers the main value.

**Independent Test**: Open the daily view for today, create, complete and delete a task, and add a note on it. Verify the changes appear in the connected apps after sync.

**Acceptance Scenarios**:

1. **Given** a connected task manager, **When** the user adds, edits, completes or deletes a task in tefteri, **Then** the change is reflected in the task manager.
2. **Given** a task shown in the daily view, **When** the user adds a note about it, **Then** the text is saved in that day's note (or a chosen custom note) in the note-taking app and linked to the task.
3. **Given** a day with no TODO note yet, **When** the user opens the daily view, **Then** a daily note is created on first use or offered to the user.

---

### User Story 3 - Schedule tasks on the calendar (Priority: P1)

The user views their calendar and places tasks from their task manager onto it as time blocks by dragging or choosing a time. They can also view and edit existing calendar entries.

**Why this priority**: Turning a to-do list into a realistic schedule is the key planning capability.

**Independent Test**: Schedule an unscheduled task at a time slot, then verify the task's date/time is updated in the task manager and the entry appears in the calendar.

**Acceptance Scenarios**:

1. **Given** an unscheduled task, **When** the user schedules it at a date and time, **Then** the task's date/time is written back to the task manager, no event is created in the calendar app, and the task appears in the calendar view next to the calendar entries.
2. **Given** a scheduled task, **When** the user moves it to another slot, **Then** the new date/time is written back.
3. **Given** an existing calendar entry, **When** the user edits or deletes it in tefteri, **Then** the change is applied in the calendar app.
4. **Given** a task is scheduled over an existing calendar entry, **When** the user confirms, **Then** the overlap is clearly shown.

---

### User Story 4 - Separate work and life (Priority: P2)

The user labels items (tasks, calendar entries, notes) as work or life, and can switch the whole app between "all", "life only" and "work only".

**Why this priority**: Explicit separation is a core requirement, but the app is usable without it.

**Independent Test**: With mixed items, switch the filter to "work only" and verify that only work items appear on every view; repeat for "life only".

**Acceptance Scenarios**:

1. **Given** items of both kinds, **When** the user selects "work only", **Then** all views show only work items.
2. **Given** a whole connected app or one of its lists/calendars/folders is assigned to work or life, **When** items sync, **Then** they inherit that label unless overridden individually.
3. **Given** an item has no label, **When** it appears in the app, **Then** it is shown under "all" and is visibly marked as unclassified.

---

### User Story 5 - Weekly, monthly and annual planning (Priority: P2)

Beyond the daily view, the user has weekly, monthly and annual views. In each, they set higher-level goals and break them into smaller chunks (annual → monthly → weekly → individual tasks), then schedule the resulting granular tasks.

**Why this priority**: This turns tefteri from a task list into a planning framework, but it builds on stories 1-3.

**Independent Test**: Create an annual goal, break it into monthly milestones and weekly tasks, schedule one, and verify the goal shows progress.

**Acceptance Scenarios**:

1. **Given** an annual goal, **When** the user breaks it into smaller goals or tasks, **Then** the hierarchy is visible and each child links to its parent.
2. **Given** goals broken into tasks, **When** tasks are completed, **Then** the goal's progress is shown in the weekly, monthly and annual views.
3. **Given** a weekly view, **When** the user drags a task from the week's plan onto a day, **Then** it is scheduled as in User Story 3.

---

### User Story 6 - Multiple users with their own data (Priority: P2)

Several people use the same tefteri installation. Each has their own account, connected apps, items, goals and plans, and cannot see anyone else's.

**Why this priority**: Required for shared deployments, but a single user can get full value without it.

**Independent Test**: Create two users with different connected apps and verify neither can see the other's data.

**Acceptance Scenarios**:

1. **Given** two users, **When** each signs in, **Then** each sees only their own items and connected apps.
2. **Given** a signed-out visitor, **When** they try to access any data, **Then** access is denied.
3. **Given** a fresh deployment configured with an admin username and password hash, **When** the admin signs in with the matching password, **Then** they can create further user accounts.
4. **Given** an SSO/OIDC provider is configured, **When** a user signs in through it, **Then** they land in their own tefteri account and see only their own data.

---

### User Story 7 - Long-term plans and retrospectives (Priority: P3)

The user writes long-term plans such as an annual resolution, and later reviews them. An end-of-period summary shows what was planned versus completed, and the user can write a retrospective.

**Why this priority**: High value for reflection, but it depends on the data from earlier stories.

**Independent Test**: With a plan from a past period that has some completed and some incomplete items, generate its summary and save a retrospective note.

**Acceptance Scenarios**:

1. **Given** a completed period (week, month or year), **When** the user opens its review, **Then** they see goals and tasks planned versus completed, and carried-over items.
2. **Given** a review, **When** the user writes a retrospective, **Then** it is saved as a note and linked to that period's plan.
3. **Given** past plans, **When** the user browses history, **Then** they can open any earlier plan and its review.

---

---

### User Story 8 - Documentation and process notes (Priority: P3)

Beyond daily notes, the user can create custom notes for documentation and for well-defined step-by-step processes, and link them to tasks so they are one click away while working.

**Why this priority**: Extends note-taking; not needed for the core loop.

**Independent Test**: Create a process note, link it to a task, open it from the task, and edit it; verify the note is saved in the note-taking app.

**Acceptance Scenarios**:

1. **Given** a connected note-taking app, **When** the user creates a documentation or process note in tefteri, **Then** it is saved in the note-taking app and appears in the notes list.
2. **Given** a task, **When** the user links a note to it, **Then** the note can be opened from the task and the task from the note.

---

### User Story 9 - Keyboard navigation (Priority: P2)

A user working at a keyboard can move between all views (daily, weekly, monthly, annual, goals, review, notes, settings) and trigger common actions (sync, switching the work/life filter) with keyboard shortcuts, without using a mouse or touch.

**Why this priority**: Fast navigation is essential to a daily planning tool people open many times a day; it is an explicit requirement.

**Independent Test**: From any view, reach every other view using only the keyboard, and open the shortcut help.

**Acceptance Scenarios**:

1. **Given** any view, **When** the user presses the shortcut for another view, **Then** that view opens.
2. **Given** the user is typing in a text field, **When** they press a plain-key shortcut, **Then** the key is entered as text and no navigation happens.
3. **Given** any view, **When** the user opens the shortcut help, **Then** all shortcuts are listed.

---

### Edge Cases

- The same item is changed in tefteri and in the source app between syncs (conflict): the user is shown both versions and chooses which to keep; nothing is overwritten automatically.
- A connected app is unreachable or credentials have expired or been revoked: the user is told clearly which connection and why, the change is not applied or queued silently, other apps are unaffected, and the user can retry or reconnect.
- An item is deleted in the source app: it disappears from tefteri after sync and linked goals/notes show it as removed rather than breaking.
- A user connects several Google accounts at once (for example a personal account, a shared family calendar and a company account) and each keeps its own work/life assignment and sign-in status.
- A connected app does not support something tefteri offers (e.g. no time field on tasks): the user is told that the action is unavailable for that app instead of data being silently lost.
- Tasks scheduled across time zones, daylight-saving changes, all-day items and recurring entries behave consistently.
- The user connects several apps of the same kind (e.g. a work and a personal calendar).
- A very large number of items (thousands of tasks, years of notes) still displays and syncs usably.
- Deleting a goal that has linked tasks: the user chooses whether to keep or remove the linked tasks.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Users MUST be able to connect, view, and disconnect their own task manager, calendar and note-taking app, and MUST be able to connect more than one of each kind. The supported apps in v1 are Vikunja (tasks), Google Calendar (covering both personal/family calendars, including shared family calendars, and company accounts) and Trilium Next (notes).
- **FR-002**: Users MUST be able to create, view, edit, complete and delete tasks from within tefteri, with changes applied in the connected task manager.
- **FR-003**: Users MUST be able to view, create, edit and delete calendar entries from within tefteri, with changes applied in the connected calendar.
- **FR-004**: Users MUST be able to schedule a task on the calendar view, and the resulting date/time changes MUST be written back to the task manager. Scheduling MUST NOT create a separate event in the calendar app; the calendar view MUST display scheduled tasks together with calendar entries, visually distinguished.
- **FR-005**: Users MUST be able to read, create and append to daily notes and custom notes in their note-taking app from within tefteri, and link notes to tasks.
- **FR-006**: Every user interface MUST provide a sync action that refreshes tasks, calendar entries and notes from all connected apps, and MUST show the time and outcome of the last sync per connection.
- **FR-007**: The system MUST report sync failures per connection, without blocking other connections, and MUST NOT lose or silently overwrite user changes when sync fails or conflicts.
- **FR-008**: The system MUST detect conflicting changes between tefteri and a connected app and, for each conflict, show both versions and let the user choose which to keep. No conflict is resolved automatically.
- **FR-009**: Users MUST be able to classify tasks, calendar entries and notes as work or life, individually or by assigning a whole connected list, calendar or folder.
- **FR-010**: Users MUST be able to switch every view between all items, life items only, and work items only, and the choice MUST apply consistently to tasks, calendar entries and notes.
- **FR-011**: The system MUST offer a daily view combining the day's calendar entries, tasks and daily note, supporting both planning and execution.
- **FR-012**: The system MUST offer weekly, monthly and annual views for setting goals and plans for that period.
- **FR-013**: Users MUST be able to break goals into smaller goals and tasks across periods, see the hierarchy, and see progress roll up from tasks to goals.
- **FR-014**: Users MUST be able to schedule tasks derived from goals from any planning view.
- **FR-015**: The system MUST support multiple users, each with an independent account, connected apps, items, goals and plans; one user MUST NOT be able to access another's data.
- **FR-016**: Users MUST be able to create long-term plans (e.g. annual resolutions) and keep them after the period ends.
- **FR-017**: The system MUST produce a review of any past period showing planned versus completed goals and tasks, and let users record a retrospective linked to that plan. Saved retrospectives MUST also be written to the user's note-taking app as notes.
- **FR-018**: Users MUST be able to create documentation notes and step-by-step process notes, save them in the note-taking app, and link them to tasks.
- **FR-019**: Connected apps are assumed to be reachable. When one is not (unreachable, credentials expired or revoked), the system MUST say so clearly, naming the connection and the reason, MUST NOT apply or queue the user's change silently, and MUST let the user resolve it (retry, reconnect or fix the connection).
- **FR-020**: The set of supported apps MUST be extensible, so that supporting a new task manager, calendar or note-taking app does not change the user-facing behaviour described here.
- **FR-021**: Credentials and access tokens for connected apps MUST be stored securely and MUST NOT be visible to other users.
- **FR-022**: The initial administrator MUST be created at first deployment from deployment configuration that supplies a pre-computed password hash; the system MUST NOT accept or store a raw password in configuration. Open self-registration MUST NOT exist; only an administrator can create further accounts.
- **FR-023**: The system MUST support signing in through a configurable external SSO/OIDC identity provider (e.g. Authelia) in addition to username and password, and MUST be able to run with either method enabled alone.
- **FR-024**: The system MUST temporarily block further sign-in attempts after 5 consecutive failures for an account or source address within 15 minutes (for 15 minutes), and MUST expire sessions after a configurable period that defaults to 8 hours.
- **FR-025**: Every tagged release MUST produce downloadable Linux desktop packages (`.deb`, AppImage), an Android package and a server container image published to the project's container registry.
- **FR-026**: A nightly build MUST publish a container image reachable under a stable `nightly` tag, versioned as `<previous-stable-release>.<commit-hash>.post<N>`, where N counts nightly builds since that stable release. The nightly build also publishes the client packages to a rolling "nightly" pre-release.
- **FR-027**: Every change MUST be verified by an automated pipeline that runs the same lint, type, architecture-boundary and test checks developers run locally.
- **FR-028**: Users MUST be able to navigate between all views (daily, weekly, monthly, annual, goals, review, notes, settings) and trigger sync and the work/life filter switch using keyboard shortcuts on clients that have a keyboard. Shortcuts MUST be discoverable from within the app, MUST NOT interfere with typing in text fields, and MUST be documented.

### Key Entities

- **User**: A person with their own account, connections, items, goals and plans.
- **Connection**: A user's link to an external task manager, calendar or note-taking app, with its sync status and its default work/life assignment.
- **Task**: A unit of work with title, status, optional due date/time and scheduled time, optional parent goal and linked notes; mirrors an item in the task manager.
- **Calendar Entry**: A time-based event mirrored from the calendar app; may be linked to a task.
- **Note**: A document in the note-taking app. Kinds: daily TODO note, custom/documentation note, process, retrospective.
- **Goal / Plan**: A high-level objective for a period (year, month, week) that can contain smaller goals and tasks and has progress.
- **Period Review**: A summary of planned versus completed items for a past period plus the user's retrospective.
- **Context (Work/Life)**: The classification of an item, used for filtering.
- **Sync Run**: One sync attempt for a connection, with time, outcome, counts and any error.
- **Conflict**: A change made both in tefteri and in the connected app; holds both versions until the user chooses which to keep.
- **Plan**: A period's collection of goals (e.g. the annual resolution plan), kept after the period ends.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new user can connect one app of each kind and see their data in under 10 minutes without help.
- **SC-002**: A sync of a typical personal account (up to 2,000 tasks, 1,000 calendar entries, 500 notes) completes in under 30 seconds.
- **SC-003**: Users can schedule an existing task on the calendar in under 15 seconds, and the change is visible in the source app after the next sync.
- **SC-004**: 100% of task, calendar and note changes made in tefteri are present in the connected app after sync, with no silent data loss in conflict and failure tests.
- **SC-005**: With a work-only or life-only filter active, 0 items of the other kind appear in any view.
- **SC-006**: A user can plan a full week (break a weekly goal into tasks and schedule them) in under 10 minutes.
- **SC-007**: No user can see another user's data in any access test.
- **SC-008**: At the end of a period, users can open a planned-versus-completed review in under 5 seconds, without compiling it by hand.
- **SC-009**: 90% of test users complete the daily plan-and-execute flow (view day, add task, schedule it, complete it, add a note) on the first attempt.
- **SC-010**: From any view, every other view is reachable using the keyboard alone in at most two key presses.

## Assumptions

- Initial scope covers exactly three apps: Vikunja for tasks, Google Calendar for calendar entries (personal/family and company accounts, possibly several at once), and Trilium Next for notes. Additional apps follow later under FR-020.
- The user's own apps remain the system of record for tasks, calendar entries and notes; tefteri's own store is the source of truth for goals, plans, work/life labels and reviews, and only retrospectives are additionally written to the note-taking app.
- Sync is user-triggered (sync button) in v1; automatic background sync is out of scope for v1.
- Connected services are assumed to be up and reachable. Offline editing and queued changes are out of scope for v1; when a service is down tefteri says so clearly and the user resolves it.
- Accounts are created by an administrator; there is no public self-registration. Sharing items between tefteri users and team features are out of scope.
- Work/life is a two-value classification in v1; custom categories are out of scope.
- Clients are provided for Linux desktop, Android and the web, usable on typical phone and desktop screens.
- Notifications and reminders are out of scope for v1; the connected apps provide their own.
