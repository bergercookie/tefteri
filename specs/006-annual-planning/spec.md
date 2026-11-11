# Feature Specification: Annual Planning, Goals and Key Results

**Feature Branch**: `006-annual-planning` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "Let the user plan the year once, before it starts: write a few loose goals, give each goal one to three measurable key results, and link each key result to the theme projects that serve it. The links are kept per year as history, can be edited during the year, and missing links are flagged. Goals exist only at the annual level. Month and week goals leave the planning flow. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Do goals exist for months and weeks? → A: No. Goals are an annual planning and review thing. Months work on theme projects and weeks work on milestone projects. Month and week goals leave the flow. Existing month and week goal rows stay as read-only history.
- Q: What types can a key result have? → A: One type in this version: a number with a start value, a target and a deadline. Yes/no and count types come later.
- Q: How is a key result updated? → A: Manually by the user, always. A key result can also be marked as "automatic". Then an outside source can push a value to it. How the outside source gets the value is out of scope. This feature defines only the one way to push a value.
- Q: What happens when a key result is retired or re-linked in mid-year? → A: Both are allowed. They are recorded in history and never change stored snapshots.
- Q: Does onboarding create links? → A: No. Only annual planning creates links (feature 003, FR-018).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Write goals with key results (Priority: P1)

The user opens annual planning for the year. They write a few goals, each one a loose sentence such as "get better at open source". For each goal they add one to three key results. A key result has a metric ("stars on one repository"), a start value, a target, a deadline and a current value. The user saves, and the goals and key results are shown the next time they open the screen.

**Why this priority**: Goals and key results are the top of the chain that the monthly and annual cycles read. Nothing else in this feature works without them.

**Independent Test**: Open annual planning for a year with no goals. Add two goals. Give the first one two key results and the second one one key result. Save, reload, and check that all of it is shown, with each current value equal to its start value.

**Acceptance Scenarios**:

1. **Given** a year with no goals, **When** the user writes a goal and saves, **Then** the goal is stored for that year and shown on the next visit.
2. **Given** a goal, **When** the user adds a key result with a metric, a start value, a target and a deadline, **Then** it is stored, and its current value starts at the start value.
3. **Given** a goal that already has three key results, **When** the user tries to add a fourth, **Then** the add is refused with a message that the limit is three.
4. **Given** a goal with no key results, **When** the user views the screen, **Then** the goal is shown with a quiet note that it needs at least one key result. Saving is not blocked.
5. **Given** a key result with a target equal to its start value, **When** the user saves, **Then** the save is refused with a message that the target must differ from the start value.
6. **Given** a key result with a deadline outside the planning year, **When** the user saves, **Then** the save is refused with a message that the deadline must fall in that year.

---

### User Story 2 - Link key results to theme projects (Priority: P1)

For each key result the user picks one or more theme projects that serve it. One theme can serve several key results, and one key result can be served by several themes. The picker lists only theme projects. Links belong to the planning year.

**Why this priority**: The links connect the plan to real work. Monthly planning (feature 007) shows each theme with the key results it serves, so without links the chain from task to goal is broken.

**Independent Test**: With three theme projects and two key results, link theme A to both key results and theme B to the first one only. Save, reload, and check that the links are shown on both sides: each key result lists its themes and each theme lists its key results.

**Acceptance Scenarios**:

1. **Given** a key result, **When** the user opens the theme picker, **Then** only projects labelled theme are offered. Milestone, maintenance and ignored projects, and orphaned projects, are not.
2. **Given** a key result linked to two themes, **When** the user saves, **Then** both links are stored for that year.
3. **Given** a theme linked to two key results of different goals, **When** the user views either key result, **Then** the theme is shown on both.
4. **Given** a saved link, **When** the user removes it, **Then** it is no longer active, and the removal is kept in the history of the year.
5. **Given** a project the user has not yet classified, **When** the user opens the theme picker, **Then** it is not offered, and a quiet note says that unsorted projects can be classified first.

---

### User Story 3 - See which key results have no theme (Priority: P1)

A key result with no linked theme has no work behind it. The planning screen flags it, while it is still cheap to fix. The flag also shows when the only linked theme is later ignored or becomes orphaned.

**Why this priority**: A key result nobody works on is the most common way for a plan to fail quietly. The flag is the main guard.

**Independent Test**: Create a key result without links. Check that it is flagged. Link a theme and check that the flag goes. Label that theme as ignored and check that the flag returns with a reason.

**Acceptance Scenarios**:

1. **Given** a key result with no links, **When** the user views the screen, **Then** the key result is flagged as having no theme.
2. **Given** a flagged key result, **When** the user links a theme, **Then** the flag disappears.
3. **Given** a key result whose only linked theme is now ignored or orphaned, **When** the user views the screen, **Then** the key result is flagged and the reason names the theme and its state.
4. **Given** a flagged key result, **When** the user saves the plan, **Then** the save is not blocked. The flag is a warning only.

---

### User Story 4 - Create a missing theme from the planning screen (Priority: P2)

While linking, the user finds that no suitable theme exists. They create a new theme project from the planning screen. It is created in the task manager, labelled as a theme, and offered at once in the picker.

**Why this priority**: It stops the user from leaving the screen in the middle of planning, but linking to existing themes already delivers value.

**Independent Test**: Open the picker, create a theme called "Open source", and check that it exists in the task manager, is labelled theme, and can be linked in the same session. Make the task manager refuse the creation and check that nothing is stored.

**Acceptance Scenarios**:

1. **Given** the theme picker, **When** the user creates a theme with a name, **Then** the project is created in the task manager as a top-level project, labelled theme, and offered in the picker.
2. **Given** the task manager rejects or fails the creation, **When** the user creates a theme, **Then** no project or label is stored and the user sees an error.
3. **Given** a name that already belongs to an existing theme, **When** the user creates it, **Then** the user is asked whether to link the existing theme instead.

---

### User Story 5 - Start a new year from last year's plan (Priority: P2)

When the user opens annual planning for a new year, last year's links are offered as editable suggestions. Last year's goals and unmet key results are shown for reference, and the user can copy a goal or key result into the new year with a click. Nothing is created until the user accepts it.

**Why this priority**: It saves the user from a blank page each year, and it keeps the plan honest about what was left unmet. The first year works without it.

**Independent Test**: With a stored plan for last year, open the new year. Check that suggestions are shown and that nothing is stored. Accept two, edit one, save, and check that only those are stored for the new year and that last year is unchanged.

**Acceptance Scenarios**:

1. **Given** a previous year with goals, key results and links, **When** the user opens a new year, **Then** the previous year's goals and key results are offered as suggestions, and no goal or link exists yet for the new year.
2. **Given** a suggested key result, **When** the user accepts it, **Then** a new key result is created for the new year with the old metric and target, a new start value, and a deadline moved into the new year, all editable before saving.
3. **Given** a suggested link whose theme is ignored or orphaned, **When** suggestions are shown, **Then** that link is not offered.
4. **Given** a new year, **When** the user dismisses all suggestions, **Then** they can start from a blank plan.
5. **Given** accepted suggestions, **When** the user saves, **Then** the previous year's data is unchanged.

---

### User Story 6 - Edit the plan during the year (Priority: P2)

Some key results turn out to be wrong. During the year the user can change a target or deadline, retire a key result, add one, re-link themes, or retire a whole goal. Every change is recorded in a history. A retired key result stays in the history and is no longer counted as active.

**Why this priority**: The decision is that plans are fixed before the year but editable later. Without history, the annual review (feature 008) could not tell why a key result changed.

**Independent Test**: Retire one key result and move a link from one theme to another. Open the history and check that both changes are listed with the date. Check that the retired key result is no longer shown as active but is still in the history.

**Acceptance Scenarios**:

1. **Given** an active key result, **When** the user retires it with an optional reason, **Then** it is marked retired with the date, and it is no longer flagged, counted or offered to other features as active.
2. **Given** an active link, **When** the user re-links the key result to another theme, **Then** the old link is ended with a date and a new link starts on that date.
3. **Given** a key result whose target is changed, **When** the user saves, **Then** the change is recorded with the old value, the new value and the date.
4. **Given** a retired key result, **When** the user restores it, **Then** it becomes active again and the restore is recorded.
5. **Given** a goal, **When** the user retires it, **Then** all its key results are retired with it, and each is recorded.
6. **Given** the history of a year, **When** the user opens it, **Then** every retirement, restore, re-link, target change and deadline change is listed in time order.

---

### User Story 7 - Update a key result's current value (Priority: P2)

The user enters a new current value for a key result by hand, with the date. Each value is kept in a series so later features can show movement. A key result can also be marked as automatic. For that case there is one defined way to push a value to it. If a value is pushed, it is stored in the same series and marked as automatic.

**Why this priority**: The monthly review (feature 007) updates key results and shows their movement. It needs the stored values and a way to enter them, but the plan itself works without them.

**Independent Test**: Enter two manual values for a key result on different dates and check that the current value is the latest and that both are kept. Mark another key result as automatic, push a value, and check that it is stored with the automatic mark and that a manual entry is still possible.

**Acceptance Scenarios**:

1. **Given** a key result, **When** the user enters a new current value with a date, **Then** the value is stored in the series and shown as the current value.
2. **Given** a key result with several values, **When** the user views it, **Then** the current value is the one with the latest date, and the progress is shown against its start value and target.
3. **Given** a key result marked automatic, **When** a value is pushed for it, **Then** the value is stored in the series, marked as automatic, and shown as current if it is the latest.
4. **Given** a key result marked automatic, **When** the user enters a value by hand, **Then** it is stored and marked as manual. Manual entry is always possible.
5. **Given** a value pushed for a key result that does not exist or is retired, **When** the push arrives, **Then** it is rejected and nothing is stored.
6. **Given** a value that is not a number, **When** it is entered or pushed, **Then** it is rejected with a message.

---

### User Story 8 - Goals become annual only (Priority: P1)

Goals no longer exist for months and weeks. The month and week views, the weekly planning flow and the look-back no longer offer to write, pick or review goals. Existing month and week goals are kept as read-only history. Existing annual goals move into the new annual plan, their old criteria text is offered as a suggestion for key results, and the tasks already linked to a goal keep their link.

**Why this priority**: The old goal model and the new annual plan cannot live side by side without confusing the user. This story keeps the user's data and removes the confusion.

**Independent Test**: With existing year, month and week goals, a task linked to a year goal and a stored weekly review that mentions a week goal, open the app after the change. Check that the year goal is in the annual plan, that month and week goals are shown only in a read-only history, that the task still shows its goal, and that the old review still loads.

**Acceptance Scenarios**:

1. **Given** an existing annual goal, **When** the user opens annual planning for that year, **Then** the goal is shown there with its text, and its old criteria text is offered as a suggestion for a key result.
2. **Given** a goal with criteria text, **When** the user accepts the suggestion, **Then** the text fills the metric field of a new key result for the user to complete. Nothing is stored until the user saves.
3. **Given** existing month and week goals, **When** the user opens the month view, the week view or the weekly planning flow, **Then** no goal is offered for picking, writing or review. The old goals are available in a read-only history.
4. **Given** a task linked to an annual goal, **When** the task is shown, **Then** the link is unchanged and the goal is shown.
5. **Given** a task linked to a month or week goal, **When** the task is shown, **Then** the link is kept and the goal is shown as history. The user can clear the link but cannot link new tasks to month or week goals.
6. **Given** a stored review that holds goal snapshots, **When** the user opens it, **Then** it loads unchanged.
7. **Given** the user wants to link a task to a goal, **When** they open the goal picker, **Then** only annual goals of the current year are offered.

---

### Edge Cases

- A key result deadline that is today or in the past when the plan is saved: allowed if it is inside the planning year. The screen shows it as overdue.
- A key result whose target is lower than its start value (for example, reduce weight, or lower the error count): valid. Progress is measured towards the target in either direction.
- A current value that goes beyond the target: valid. Progress is shown as more than 100% and is not capped in the stored value.
- A goal with exactly three key results where the user wants a fourth: the user must retire or merge one. This keeps goals loose and few.
- A goal with no key results: shown with a quiet note, never blocked. The monthly flow (feature 007) shows it as having no measurable result.
- A theme that is relabelled milestone, maintenance or ignored after being linked: the link is kept in history but is shown as inactive, and the key result is flagged if no active theme is left. The theme is no longer offered in the picker.
- A theme that is orphaned: its links are kept and shown with the stored name, and the key result is flagged.
- Two key results with the same metric in the same goal: allowed. A quiet note suggests merging them.
- A planning year in the past: shown read-only. The user can still view the history but cannot add goals.
- A planning year in the future: allowed. The user may plan the next year in advance.
- A theme project that is linked but has no milestones: valid. Milestones are created later (feature 004).
- A value series with two values on the same date: the later one entered wins as current, and both are kept.
- Two users with different accounts: goals, key results and links are private to each user.
- Existing goals have no explicit deadline or numbers: they are moved over without key results, and the user is nudged to add some.
- A pushed value arrives for a key result that is not marked automatic: it is rejected, so a stray source cannot change a manual key result.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST store goals for one planning year only. A goal holds one text sentence, its year, its state (active or retired) and the date of its last change.
- **FR-002**: The system MUST let the user create, edit, retire and restore goals for the current or a future year.
- **FR-003**: The system MUST let each goal hold between zero and three active key results, and MUST refuse a fourth active key result with a clear message. A goal with zero key results MUST be shown with a quiet note and MUST NOT block saving.
- **FR-004**: A key result MUST hold a metric (text), a start value, a target, a deadline, a current value, an update source (manual or automatic) and a state (active or retired). The only value type in this version is a number.
- **FR-005**: The system MUST refuse a key result whose target equals its start value, whose values are not numbers, or whose deadline is outside the planning year of its goal.
- **FR-006**: The system MUST set the current value of a new key result to its start value and MUST keep a series of dated values for each key result, each marked manual or automatic.
- **FR-007**: The system MUST take the current value from the value with the latest date. For equal dates, the value entered last wins. All values MUST be kept.
- **FR-008**: The system MUST compute the progress of a key result from the start value, the current value and the target, in either direction, and MUST NOT cap the stored current value at the target.
- **FR-009**: The system MUST always allow the user to enter a value by hand, including for key results marked automatic.
- **FR-010**: The system MUST offer one defined way for an outside source to push a value to a key result marked automatic. A pushed value MUST be stored in the series with the automatic mark. A push MUST be rejected if the key result is not marked automatic, is retired, does not exist, belongs to another user or carries a value that is not a number. How an outside source obtains the value is out of scope.
- **FR-011**: The system MUST let the user link a key result to one or more theme projects, and a theme project to one or more key results. A link MUST belong to the planning year of the key result.
- **FR-012**: The theme picker MUST offer only projects labelled theme that are not orphaned and not under an ignored parent. It MUST NOT offer milestone, maintenance, ignored or unclassified projects.
- **FR-013**: The system MUST keep every link as history. Removing or replacing a link MUST end it with a date and MUST NOT delete it.
- **FR-014**: The system MUST flag every active key result that has no active link to a usable theme, where usable means labelled theme, not orphaned and not ignored. The flag MUST state the reason, and MUST NOT block any action.
- **FR-015**: The system MUST let the user create a new theme project from the planning screen. It MUST create the project in the task manager first and store the label only if that succeeds. On failure it MUST store nothing and show an error. This feature depends on the creation capability required by feature 003.
- **FR-016**: When the user opens a new planning year, the system MUST offer the previous year's links, goals and key results as editable suggestions. It MUST NOT create any goal, key result or link until the user accepts it. It MUST NOT offer a link to a theme that is ignored, orphaned or no longer labelled theme.
- **FR-017**: An accepted key result suggestion MUST create a new key result for the new year, with the old metric and target, a new start value and a deadline inside the new year, all editable before saving. The previous year's data MUST NOT change.
- **FR-018**: The system MUST let the user edit a goal's text, and a key result's metric, target, deadline and update source, at any time. It MUST let the user retire and restore a key result and a goal, with an optional reason.
- **FR-019**: The system MUST record every retirement, restore, link change, target change, deadline change and text change in a history with the date, the old value and the new value. The history MUST be shown per year, in time order.
- **FR-020**: Retiring or re-linking MUST NOT change any stored review snapshot. A retired key result MUST NOT be counted or offered as active, and MUST stay in the history.
- **FR-021**: Retiring a goal MUST retire all its active key results and record each one.
- **FR-022**: Goals MUST NOT be created, picked or reviewed for a month or a week. The month view, the week view, the weekly planning flow and the look-back MUST NOT offer goals.
- **FR-023**: Existing month and week goals MUST be kept unchanged as read-only history, available in one history view. They MUST NOT be deleted, and new tasks MUST NOT be linked to them.
- **FR-024**: Existing annual goals MUST become goals of the annual plan for their year, with their text kept. Their old criteria text MUST be offered as a suggestion for a key result metric and MUST NOT create a key result on its own.
- **FR-025**: Existing links between tasks and goals MUST be kept. A task linked to an annual goal MUST still show the goal. A task linked to a month or week goal MUST show it as history, and the user MUST be able to clear that link.
- **FR-026**: The goal picker for tasks MUST offer only active annual goals of the current year.
- **FR-027**: Stored review snapshots that contain goal data MUST load unchanged.
- **FR-028**: Onboarding and project classification MUST NOT create goals, key results or links (feature 003, FR-018). Only annual planning creates them.
- **FR-029**: Goals, key results, links, values and history MUST be private to the user who made them.
- **FR-030**: The system MUST expose the active key results, their links, current values and progress, and their flags, for the planning year, so that later features (monthly planning and review, annual review) can read them.
- **FR-031**: The user documentation and the developer documentation MUST describe annual planning, goals as annual only, and key results, with screenshots made from fake data, in simplified technical English. Existing documentation and tests that describe month or week goals MUST be updated.

### Key Entities *(include if feature involves data)*

- **Goal**: One loose sentence for one planning year, with its state (active or retired). Annual only. Holds up to three active key results.
- **Key result**: A measurable success criterion of a goal. Holds a metric, start value, target, deadline, current value, update source (manual or automatic) and state.
- **Key result value**: One dated entry in the series of a key result, with the number and a mark for manual or automatic. Gives the current value and the movement.
- **Key result to theme link**: A many-to-many link between a key result and a theme project, for one planning year. Holds the dates it started and ended. Kept as history.
- **Plan change**: One line of the history of a year, with the thing that changed, the old value, the new value, the date and an optional reason.
- **Planning year**: The annual cycle that goals, key results and links belong to.
- **Suggestion**: A proposed goal, key result or link taken from the previous year. It is shown to the user and is never stored until the user accepts it.
- **Legacy goal**: An existing goal row of a month or a week, kept as read-only history. Also, the old criteria text of an annual goal, offered as a suggestion.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can write three goals with two key results each and link them to existing themes in under 15 minutes.
- **SC-002**: 100% of active key results with no usable theme are flagged. A test that removes, ignores or orphans the last theme of a key result shows the flag every time.
- **SC-003**: After any retire, restore or re-link action, 100% of stored review snapshots are unchanged, and the history shows the change.
- **SC-004**: After the change, 100% of existing annual goals, month and week goals, goal-task links and stored reviews are still available, and no data is lost. A test on a copy of real data confirms the counts before and after.
- **SC-005**: In 100% of tests no month, week or weekly planning screen offers to write, pick or review a goal.
- **SC-006**: At the start of a new year, the user sees last year's links as suggestions within 2 seconds, and 0 items are stored until the user accepts them.
- **SC-007**: A pushed value for an automatic key result is shown as the current value within 5 seconds, and rejected pushes (wrong key result, wrong type, retired, not automatic) store nothing in 100% of tests.
- **SC-008**: A goal never has more than three active key results, in 100% of tests including concurrent saves.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral.
- This feature depends on feature 003. It uses the labels (theme and the others), the orphaned mark and the ignored rule, and the capability to create projects. A theme is usable only if it is labelled theme by feature 003.
- Features 007 (monthly planning and review) and 008 (annual review) read the goals, key results, links, values and history from this feature. They are not part of this feature. Feature 007 is where most key result updates will happen in practice.
- **Changes to existing behaviour.** Goals today have a period type of year, month or week, with a parent and a criteria text. After this feature, only year goals take part in planning. Month and week goal rows stay in storage as read-only history. The goal pickers, the month and week views, the weekly planning flow, the look-back and the Goals screen no longer offer to write, pick or review month or week goals. Existing tests and documentation that describe month or week goals will change. The existing Goals screen is replaced by the annual planning screen for the current plan, with a history view for old rows.
- Existing goal-to-task links (the goal on a task) are kept. Their meaning stays: a task can be linked to one goal. The goal picker offers annual goals only.
- The old criteria text of an annual goal is kept and offered as a suggestion for a key result metric. It is not converted automatically, because it is free text and cannot become a number safely.
- Existing weekly review snapshots that contain goal data are not rewritten.
- One key result type exists in this version: a number with a start value, a target and a deadline. Yes/no and count types come later.
- Automatic update sources are not built here. This feature defines a key result's source setting and one way to push a value. How a source such as a repository star count is obtained is a separate piece of work. Manual entry is always available.
- The default planning year is the calendar year. A different year start is out of scope.
- Retiring a key result frees a slot, so the three-key-result limit counts active key results only.
- Out of scope: quarterly checkpoints to rewrite goals, paired controllable key results, yes/no and count key result types, building automatic sources, calendar use in planning, monthly planning, the monthly and annual reviews, and connectors that lack nested projects.
