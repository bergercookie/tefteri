# Feature Specification: Project Classification and Onboarding

**Feature Branch**: `003-project-classification` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "Label the user's existing task-manager projects as theme, milestone, maintenance or ignored, so that later planning cycles know which projects are long-running homes for work, which are finishable outcomes, which are routine, and which to hide. Tefteri guesses the labels and the user corrects them. The labels live only in Tefteri. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Does the weekly cap of three count milestone projects or themes, and is it hard? → A: It counts milestone projects and only warns. This is a rule of feature 004 and does not change this feature.
- Q: Are goals part of onboarding? → A: No. Goals are annual only and are made in annual planning (feature 006). Onboarding never links projects to goals.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Review and fix the guessed labels (Priority: P1)

The user has connected a task manager with many projects. Tefteri shows the whole project tree with each project already labelled. The default guess is that top-level projects are themes and everything below them is a milestone project. The user scans the tree, changes the labels that are wrong, and saves.

**Why this priority**: Every later cycle (weekly, monthly, annual) depends on knowing what each project is. Without labels, nothing else in the planning series can start.

**Independent Test**: Connect a task manager with a tree of at least three levels. Open the classification screen. Check that every project has a guessed label, change four of them, save, reload, and check that the saved labels are shown.

**Acceptance Scenarios**:

1. **Given** a connected task manager with a project tree, **When** the user opens classification for the first time, **Then** every project is shown in its tree position with a guessed label of theme or milestone.
2. **Given** a project that was committed in a past weekly plan, **When** the guess is made, **Then** its guessed label is milestone, even if it is at the top level.
3. **Given** a project the user relabels as maintenance, theme, milestone or ignored, **When** they save, **Then** the label is stored and shown on the next visit.
4. **Given** the user has not classified every project, **When** they leave the screen, **Then** the unclassified projects are kept in an "unsorted" group and nothing is blocked.

---

### User Story 2 - Flag routine work and hide dormant projects (Priority: P1)

The user marks the admin project (groceries, chores) and other standing routines as maintenance. They mark old or irrelevant projects as ignored. Ignored projects disappear from planning pickers. Maintenance projects stay visible for daily work but never appear as candidates for weekly commitment.

**Why this priority**: Without these two labels the statistics and the weekly cap in later features would count routine and dead projects as goal work.

**Independent Test**: Mark one project as maintenance and one as ignored. Open the weekly planning project picker. Check that neither is offered. Check that the maintenance project still shows its tasks in the daily view.

**Acceptance Scenarios**:

1. **Given** a project labelled ignored, **When** the user opens any planning picker, **Then** the project and its sub-projects are not listed.
2. **Given** a project labelled maintenance, **When** the user opens the weekly project picker, **Then** the project is not listed, and its open tasks still appear in the daily and planner views.
3. **Given** a project labelled ignored, **When** the next sync runs, **Then** the project is still synced and its label is kept. Ignoring hides it from planning only.
4. **Given** an ignored project, **When** the user relabels it, **Then** it returns to the pickers at once.

---

### User Story 3 - Labels survive renames, moves and disappearing projects (Priority: P1)

The user renames or moves a project in the task manager, or deletes or archives one. Tefteri keeps the label for the same project. A project that disappears is marked orphaned and is never silently deleted from Tefteri. The app does not fail on an orphaned project.

**Why this priority**: A classification that breaks when a name changes would lose the user's trust and corrupt later history.

**Independent Test**: Classify a project. Rename it in the task manager and sync: the label stays. Delete it in the task manager and sync: the project shows as orphaned with its label and history intact, and every screen still loads.

**Acceptance Scenarios**:

1. **Given** a classified project, **When** it is renamed directly in the task manager and a sync runs, **Then** the new title is shown and the label is unchanged.
2. **Given** a classified project, **When** it is moved to another parent and a sync runs, **Then** the label is unchanged and the tree shows the new position.
3. **Given** a classified project, **When** it disappears from the task manager and a sync runs, **Then** it is marked orphaned, keeps its label and history, and is hidden from planning pickers.
4. **Given** an orphaned project that reappears with the same project identity, **When** a sync runs, **Then** it is no longer orphaned.
5. **Given** an orphaned project referenced by a past weekly plan, **When** the user opens that plan, **Then** the page loads and shows the stored project name.

---

### User Story 4 - Rename a project from Tefteri (Priority: P2)

During classification the user renames a project. Tefteri writes the new name to the task manager first. Only if that succeeds does Tefteri show the new name. If the task manager refuses, the user sees an error and nothing changes in either place.

**Why this priority**: It saves a round trip to the task manager when tidying names, but classification works without it.

**Independent Test**: Rename a project in Tefteri and check the task manager shows the new name. Make the task manager refuse the change and check that Tefteri keeps the old name and shows an error.

**Acceptance Scenarios**:

1. **Given** a task manager that supports renaming, **When** the user renames a project in Tefteri, **Then** the task manager shows the new name and Tefteri shows it too.
2. **Given** the task manager rejects or fails the write, **When** the user renames a project, **Then** the old name remains in both places and the user sees an error.
3. **Given** a task manager that does not support renaming, **When** the user opens classification, **Then** the rename option is not shown.

---

### User Story 5 - Know what the connected task manager supports (Priority: P2)

When the user connects a task manager, Tefteri checks which capabilities it offers: nested projects, stable project identity, reading the full tree, creating and archiving projects, creating and moving tasks, renaming projects and completion times. A task manager that lacks a required capability is refused with a clear reason. A missing optional capability hides only the feature that needs it.

**Why this priority**: Later features create projects, move tasks and read completion times. Finding out at connect time is cheaper than failing in the middle of a planning session.

**Independent Test**: Connect a task manager that lacks renaming. Check that the connection works and that renaming is hidden. Connect one that lacks stable project identity. Check that the connection is refused with a reason.

**Acceptance Scenarios**:

1. **Given** a task manager that meets all required capabilities, **When** the user connects it, **Then** the connection succeeds and the result lists the capabilities found.
2. **Given** a task manager missing a required capability, **When** the user connects it, **Then** the connection is refused and the message names the missing capability.
3. **Given** a task manager missing an optional capability (move tasks, rename projects), **When** the user connects it, **Then** the connection succeeds and the features that need it are hidden.

---

### User Story 6 - New projects are proposed later (Priority: P3)

New projects appear in the task manager after onboarding. On the next sync Tefteri proposes a label for each one and gently nudges the user to confirm it. The user can open classification again at any time.

**Why this priority**: Keeps the labels current without a big re-onboarding, but the first labelling already delivers value.

**Independent Test**: After classification, add a project in the task manager and sync. Check that it appears in the unsorted group with a proposed label and a nudge, and that planning is not blocked.

**Acceptance Scenarios**:

1. **Given** a new project appears, **When** a sync runs, **Then** the project is shown in the unsorted group with a proposed label.
2. **Given** unsorted projects exist, **When** the user plans a week, **Then** planning works and shows a quiet reminder that some projects are unsorted.
3. **Given** all projects are classified, **When** the user opens classification again, **Then** they can change any label.

---

### Edge Cases

- A task manager with a flat project list and no nesting: all projects are guessed as themes. Parent and child relations are not available (the flat mapping fallback is out of scope).
- A project tree with hundreds of projects: the screen stays usable (grouped, collapsible, searchable).
- A parent labelled ignored with children labelled theme: the children are ignored in pickers as long as an ancestor is ignored. The screen warns about the conflict.
- A theme that has no children: it is valid. Milestones are created later during weekly planning.
- A milestone at the top level with no parent theme: it is valid and shown as "no theme". Feature 004 decides how it is planned.
- A project that was moved under a different parent while a classification save is in progress: the save uses the project identity, so it applies to the right project.
- Two users with different task-manager accounts: classification is per user and per connection.
- The existing "enabled" setting for a project (sync on or off): it keeps its meaning. Ignored is a separate planning label. A project can be enabled and ignored.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST store one label per project: theme, milestone, maintenance or ignored. A project with no label is unclassified.
- **FR-002**: The system MUST key every label on the stable identity of the project in the task manager and never on its name.
- **FR-003**: The system MUST NOT write labels, tags, fields or naming conventions to the task manager to record a classification.
- **FR-004**: The system MUST propose a label for each unclassified project. By default a top-level project is proposed as a theme and any deeper project as a milestone. A project that appears in a past weekly plan MUST be proposed as a milestone. The user MUST be able to override the proposal for any project.
- **FR-005**: The system MUST show the project tree with each project's label and let the user change the label of any project, one at a time or for a selection.
- **FR-006**: The system MUST keep unclassified projects in an "unsorted" group and MUST NOT block any planning action because projects are unsorted.
- **FR-007**: The system MUST exclude projects labelled ignored, and their descendants, from every planning picker, while continuing to sync them.
- **FR-008**: The system MUST exclude projects labelled maintenance from the weekly planning project picker, while still showing their tasks in the daily and planner views.
- **FR-009**: The system MUST reconcile projects on every sync: update titles and parents, add new projects as unclassified, and keep labels for projects that moved or were renamed.
- **FR-010**: The system MUST mark a project that disappears from the task manager as orphaned, keep its label and history, and MUST NOT delete it. This includes a project the user archives from Tefteri.
- **FR-011**: The system MUST clear the orphaned mark when a project with the same identity returns.
- **FR-012**: Every screen and service that reads projects MUST work when a project is orphaned and show the stored name.
- **FR-013**: When the user renames a project in Tefteri, the system MUST write the change to the task manager first and update its own record only if the write succeeds. On failure it MUST leave both unchanged and show an error.
- **FR-014**: A rename made directly in the task manager MUST appear as the new title on the next sync and MUST NOT change the label.
- **FR-015**: Each task-manager connector MUST declare its capabilities. When the user connects, the system MUST verify them and refuse a connector that lacks a required capability, with a message that names it.
- **FR-016**: The required capabilities are: nested projects with at least two levels (otherwise the connector is refused in this version), stable project identity, reading the full project tree and detecting deleted or moved projects, creating and archiving projects, creating tasks, and task completion timestamps. The optional capabilities are moving tasks and renaming projects. The system MUST hide a feature whose optional capability is missing.
- **FR-017**: The system MUST let the user open classification again at any time and MUST propose labels for projects that appeared after the last sync.
- **FR-018**: The system MUST NOT create links between projects and goals. Goals are created in annual planning only.
- **FR-019**: Labels MUST be private to the user who made them, per connection.
- **FR-020**: The user documentation and the developer documentation MUST describe classification, with screenshots made from fake data, in simplified technical English.

### Key Entities *(include if feature involves data)*

- **Project label**: The classification of one task-manager project for one user. It holds the project identity, the label (theme, milestone, maintenance, ignored or unclassified), whether the project is orphaned, and when the label was last changed.
- **Project**: A project that Tefteri already mirrors from the task manager, with its identity, title and parent. The label is attached to it by identity.
- **Connector capabilities**: The declared set of things a task-manager connector can do, with a flag for each as required or optional, and the result of the last check.
- **Classification proposal**: A suggested label with the reason for it (depth, has children, past weekly plan). It is shown to the user and is never stored as a label until the user confirms or saves.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with 100 projects can review and save a complete classification in under 10 minutes, starting from the proposals.
- **SC-002**: At least 80% of projects need no change from the proposal on a typical tree where top-level projects are long-running homes (checked on the demo data set).
- **SC-003**: After any rename, move or removal in the task manager and one sync, 100% of the remaining labels are still on the correct projects.
- **SC-004**: No screen fails when a project is orphaned. A test that removes a project referenced by a plan and a task passes on every screen that shows projects.
- **SC-005**: Ignored and maintenance projects never appear in the weekly project picker, in 100% of tests.
- **SC-006**: No label, field or tag is written to the task manager by classification. The contract tests for each connector confirm it.
- **SC-007**: Connecting a task manager that lacks a required capability is refused in under 5 seconds with a message that names the capability.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral. The capability table is part of the plan.
- Labels are stored in Tefteri's own database, keyed on the existing mirrored project record, which in turn holds the task manager's project identity.
- Milestone state (active, parked, closed, done), rollover and expected-rollover data belong to feature 004. This feature stores only the label.
- A "theme" label and a "milestone" label do not change what a project does in the task manager. They only change how Tefteri plans with it.
- The existing project setting "enabled" (sync on or off) is kept. "Ignored" hides a project from planning only and does not stop sync.
- Archiving a project from Tefteri (existing behaviour) now keeps its record and marks it orphaned, instead of removing it.
- Dependencies: the task-manager port and the Vikunja adapter gain a project rename operation and a capability check. These are part of this feature.
- Out of scope: linking projects to goals or key results, creating themes from the annual planning screen, milestone rules, statistics, and connectors that lack nested projects.
