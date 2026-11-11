# Feature Specification: Weekly Planning and Review with Milestone Projects

**Feature Branch**: `004-weekly-milestones` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "Change the existing weekly planning and look-back so that the unit of weekly commitment is a milestone project: a small project under a theme with a clear done-state, finishable in one week. The user commits up to three milestones (a warning, not a hard limit), picks tasks, and at the end of the week decides for each unfinished milestone whether to recommit it, park it, close it or decide later. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Does the weekly cap of three count milestone projects or themes, and is it hard? → A: It counts milestone projects and only warns. The server no longer rejects a fourth project.
- Q: Do weeks and months have their own goals? → A: No. Goals are an annual planning and review matter only. Months work on theme projects and weeks work on milestone projects. The weekly flow no longer asks for or reviews goals.
- Q: What counts as a completed milestone when some tasks were dropped? → A: A milestone is done when all its open tasks are closed or dropped, or when the user marks it done. Dropped tasks never block completion. At least one task must have been closed (not only dropped) for automatic completion. A milestone with no tasks is never done automatically.
- Q: What if the monthly focus (feature 007) does not exist yet? → A: The picker offers all themes, with no highlight and no "outside focus" tag. Once focus data exists, it is used.
- Q: Is the calendar used in planning? → A: No. It is out of scope.

### Session 2026-11-11 (cross-spec analysis)

- Q: Who owns the milestone completion data? → A: This feature. A milestone stores a done date and the theme it had at that moment. Features 007 and 008 read these two fields.
- Q: Is "outside focus" stored? → A: No. It is computed when read, from the monthly focus.
- Q: Which week belongs to which month? → A: The month of the Monday of that week.

## Terms used in this feature

Each term is also explained in the screens, at its first use.

- **Theme project**: a long-running project that holds related work. It is never committed to a week (feature 003).
- **Milestone project**: a small project under a theme with a clear done-state, finishable in one week. It is the unit of weekly commitment.
- **Done-state**: one sentence that says when the milestone is finished ("ship the login flow").
- **Parent theme**: the nearest ancestor project labelled theme. If there is none, the milestone is shown as "no theme".
- **Committed**: chosen for this week's plan. Open tasks of a milestone that were not picked are "not committed this week".
- **Parked**: a milestone state set by the park decision in the review. A parked milestone returns to the picker later.
- **Rollover**: a milestone recommitted for the next week because it was not finished.
- **Dropped task**: a task closed without completion.
- **Outside focus**: a milestone whose theme is not in the month's focus (feature 007). It is computed when read and never stored.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Commit milestone projects for the week (Priority: P1)

The user opens weekly planning. The picker lists milestone projects grouped by their parent theme. The user commits up to three milestones for the week. Each committed milestone is an existing one (active or parked) or a new one. Which projects the picker may offer is decided by feature 003 (eligible per 003): theme, maintenance, ignored and orphaned projects are never offered as something to commit.

**Why this priority**: This is the core of the feature. Without it the weekly plan still works on open-ended projects and nothing else in this feature has a meaning.

**Independent Test**: With a few themes and milestones classified (feature 003), open planning, commit two existing milestones, and check that they are stored for the week and that no theme, maintenance or ignored project was offered.

**Acceptance Scenarios**:

1. **Given** classified projects, **When** the user opens the weekly picker, **Then** only milestone projects that are eligible per 003 are offered, grouped under their parent theme, and parked milestones are included and marked as parked.
2. **Given** the user selects a milestone, **When** they commit the plan, **Then** the milestone is stored in the weekly commitment and its state is active.
3. **Given** a project labelled theme, maintenance or ignored, or an orphaned project, **When** the user opens the picker, **Then** it is not offered as a commitment (rules in feature 003).
4. **Given** a theme that has no milestones yet, **When** the user opens the picker, **Then** the theme is shown with an inline action to create a new milestone under it.
5. **Given** a milestone that has no parent theme, **When** the user opens the picker, **Then** it is listed under "no theme" and can be committed.
6. **Given** some projects are still unsorted, **When** the user plans, **Then** planning works and shows a quiet reminder, as in feature 003.
7. **Given** there are no milestones and no themes at all, **When** the user opens the picker, **Then** an empty state explains what a theme and a milestone are, with the inline actions "label a project as theme" and "create a theme", and the user can still finish planning with zero milestones.
8. **Given** a milestone is already committed in this week's plan, **When** the user looks for it in the picker, **Then** it is shown as already committed and cannot be added a second time.
9. **Given** a milestone was left with "decide later" in a review, **When** the user opens the picker, **Then** it shows a reminder that its decision is still open, and the user can still commit it.

---

### User Story 2 - Create a new milestone with a clear done-state (Priority: P1)

The user has a theme but no suitable milestone. From the picker they create a new milestone under that theme. The user must give it a name that states a done-state ("ship the login flow", not "work on auth"). The milestone is created with the shared rule "create project and label it" owned by feature 003 (task manager first, then the label in Tefteri) as a sub-project of the theme.

**Why this priority**: Milestones are invented during weekly planning. Without creating them, the user must leave Tefteri before every plan.

**Independent Test**: Choose a theme, create a milestone with a done-state, and check that it appears under the theme in the task manager, is labelled milestone in Tefteri, and is part of the week's commitment.

**Acceptance Scenarios**:

1. **Given** a theme, **When** the user creates a milestone with a name and a done-state, **Then** the task manager has a new sub-project under the theme, Tefteri labels it milestone, and it is added to the week's commitment.
2. **Given** the user leaves the done-state empty, **When** they try to create the milestone, **Then** creation is refused with a short hint and an example on how to word a done-state, and what the user typed is kept.
3. **Given** the task manager fails to create the project, **When** the user creates a milestone, **Then** nothing is recorded in Tefteri, the user sees an error, and what the user typed is kept so they can try again.
4. **Given** a milestone was created, **When** the user opens it later, **Then** its done-state is shown with it.

---

### User Story 3 - Pick or add tasks for the milestones (Priority: P1)

For each committed milestone the user picks tasks from a menu of its open tasks, and may add new tasks under it. The assembled list is the committed task list for the week. Tasks that the user does not pick stay in the milestone and are "not committed this week".

**Why this priority**: The committed task list is what daily execution and the weekly review measure.

**Independent Test**: Commit one milestone that has five open tasks, pick three, add one new task, commit, and check that the plan holds four committed tasks and two open tasks not committed this week, and that the new task exists in the task manager under the milestone.

**Acceptance Scenarios**:

1. **Given** a committed milestone with open tasks, **When** the user opens its task menu, **Then** its open tasks are listed and each can be selected.
2. **Given** the user adds a new task in the menu, **When** they commit, **Then** the task is created under the milestone in the task manager and is included in the committed list.
3. **Given** unselected tasks, **When** the user commits, **Then** they are not committed this week and remain open in the milestone, unchanged.
4. **Given** a milestone with no open tasks, **When** the user opens the menu, **Then** an empty state invites them to add the first task, with an inline "add task" field.

---

### User Story 4 - Go over the cap with a warning, and see milestones outside focus (Priority: P2)

The cap of three counts milestone projects. When the user commits a fourth, Tefteri shows a clear warning that the week is probably too full, and lets them continue. If monthly focus data exists (feature 007), the picker lists milestones under the month's focus themes first and highlights those themes. A milestone under a theme that is not in the focus is allowed and shown as "outside focus". If no focus data exists, all themes are offered equally and nothing is shown as outside focus. The month of a week is the month of its Monday, and that month's focus is the one used.

**Why this priority**: The cap and the focus guide the user but are not allowed to block them. The plan works without them.

**Independent Test**: Commit four milestones and check that a warning is shown and the plan is saved. With a monthly focus set, commit a milestone under a non-focus theme and check that it is shown as outside focus.

**Acceptance Scenarios**:

1. **Given** three milestones are committed, **When** the user adds a fourth, **Then** a warning states the count and the cap of three, and the user can still commit.
2. **Given** four milestones are committed, **When** the user removes one, **Then** the warning disappears.
3. **Given** a monthly focus exists, **When** the user opens the picker, **Then** the focus themes are shown first and highlighted.
4. **Given** a monthly focus exists, **When** the user commits a milestone under a theme that is not in the focus, **Then** it is shown as outside focus in the plan and in the review. If the focus changes later, the display changes with it, because nothing was stored.
5. **Given** no monthly focus data exists, **When** the user opens the picker, **Then** all themes are offered with no highlight and nothing is shown as outside focus.
6. **Given** maintenance projects exist, **When** the user commits any number of milestones, **Then** maintenance projects are never counted in the cap.
7. **Given** a week that starts on the last Monday of one month and ends in the next month, **When** the user plans it, **Then** the focus of the month of that Monday is used.

---

### User Story 5 - Weekly review: how the week went (Priority: P2)

At the end of the week the user opens the review (the look-back). It shows how many committed tasks were completed, how many milestones were finished, and the pace across the week. It shows how much of the completed work served the month's focus themes (when focus data exists). It also shows the work done outside the plan, using the weekly list owned by feature 005. The review does not ask about goals, because goals are reviewed only in the annual review.

**Why this priority**: The review gives the feedback that makes the cap and the done-states meaningful, but planning works without it.

**Independent Test**: Commit a plan, complete some committed tasks and some tasks outside the plan, then open the review and check the numbers and the lists.

**Acceptance Scenarios**:

1. **Given** a finished week, **When** the user opens the review, **Then** it shows committed tasks completed out of committed, milestones finished out of committed, and the pace per day.
2. **Given** a monthly focus exists, **When** the user opens the review, **Then** it shows the focus share: the share of completed committed tasks that are under focus themes.
3. **Given** no monthly focus exists, **When** the user opens the review, **Then** the focus measure is not shown.
4. **Given** tasks completed outside the commitment, **When** the user opens the review, **Then** they are shown with the weekly list from feature 005 (what is listed, how it is limited and how maintenance is treated are owned there).
5. **Given** the review is opened, **When** it loads, **Then** no goal questions or goal review steps are shown for the week.
6. **Given** no task was committed, **When** the user opens the review, **Then** the focus share and the completed-out-of-committed numbers are replaced by a short note, and no division by zero is shown.

---

### User Story 6 - Decide on every unfinished milestone (Priority: P1)

In the review, each unfinished milestone gets a decision. The four choices are: keep and recommit (it goes into next week's plan), keep but park (it gets the state parked and returns to the picker later), close and return its open tasks to the parent theme, or decide later. Closing a milestone moves its open tasks to the parent theme project and closes the milestone. Before the user confirms a close, the screen shows the number of tasks that will move and where they go, and the user confirms. A close can be undone by reopening the milestone. Decide later leaves the milestone unchanged and does not change its rollover count. If the task manager cannot move tasks, the close option is not shown. A finished milestone needs no decision.

**Why this priority**: This forces a conscious choice about scope and replaces the existing carry and backlog choices, without ever trapping the user in the review.

**Independent Test**: Review a week with four unfinished milestones. Recommit one, park one, close one, decide later on one. Check that the next week's plan holds the recommitted milestone, the parked one is in the picker as parked, the closed one has its open tasks back in the theme, and the last one is unchanged and shows a reminder in the picker.

**Acceptance Scenarios**:

1. **Given** an unfinished milestone, **When** the user chooses keep and recommit, **Then** it is added to the next week's commitment and its rollover count goes up by one.
2. **Given** an unfinished milestone, **When** the user chooses keep but park, **Then** its state becomes parked, it is shown as parked in the picker, and its rollover count is unchanged.
3. **Given** an unfinished milestone with a parent theme, **When** the user chooses close and return tasks, **Then** the screen shows "N open tasks will move to <theme>" and asks to confirm. After the user confirms, the tasks move, the milestone is closed, and it no longer appears in the picker.
4. **Given** an unfinished milestone with no parent theme, **When** the user opens the decision, **Then** the close option is not offered and a line says why ("no theme to return the tasks to"), with an inline action to label a project as theme.
5. **Given** a task manager that cannot move tasks, **When** the user opens the decision, **Then** the close option is not shown.
6. **Given** the move of tasks fails part way, **When** the user chooses close, **Then** the milestone stays unclosed, the tasks already moved are reported, and the user can try again.
7. **Given** unfinished milestones without a choice, **When** the user tries to finish the review, **Then** the review names them and offers "decide later for all of these" in one action. Nothing else blocks the user.
8. **Given** a milestone that was finished during the week, **When** the user opens the review, **Then** it is shown as done and needs no decision.
9. **Given** the user chooses decide later, **When** the review is saved, **Then** the milestone state and rollover count are unchanged, and the next picker shows a reminder on it.
10. **Given** a milestone was closed by a close and return, **When** the user reopens it from the review or from the history, **Then** it is active again, the tasks that were moved are moved back where they were not changed since, and any that could not be moved back are listed. This never blocks the reopen.

---

### User Story 7 - Rollover count, expected rollover and re-scope nudge (Priority: P2)

Each recommit is a rollover and raises the milestone's rollover count. When recommitting, the user can mark that rollover event as expected ("this was bigger than a week"). The marker belongs to that one event. A nudge to re-scope the milestone (shrink it, split it, or close it) appears after two consecutive unmarked rollovers. A marked rollover never triggers a nudge and ends the run of unmarked ones.

**Why this priority**: It makes oversized milestones visible, but the weekly flow works without it.

**Independent Test**: Recommit a milestone twice without the marker and check that the nudge appears. Recommit another once with the marker and check that no nudge appears.

**Acceptance Scenarios**:

1. **Given** a milestone recommitted for the first time, **When** the user confirms, **Then** its rollover count is 1 and no nudge is shown.
2. **Given** a milestone whose last rollover was unmarked, **When** the user recommits it again without the marker, **Then** the rollover count is 2 and a nudge asks the user to re-scope it.
3. **Given** the user marks a recommit as expected, **When** the milestone is recommitted, **Then** that rollover event is stored with the marker and no nudge is shown for it.
4. **Given** the last two rollovers are unmarked, **When** the user ignores the nudge, **Then** the user can still commit the milestone.
5. **Given** a milestone that is finished, **When** the user opens it later, **Then** its final rollover count and the marker of each rollover are kept as history.
6. **Given** a parked milestone, **When** the user commits it again later, **Then** the rollover count continues from its earlier value. Parking does not reset it and does not count as a rollover.
7. **Given** rollovers unmarked, marked, unmarked, **When** the user recommits again without the marker, **Then** no nudge is shown, because the two latest unmarked rollovers are not consecutive.

---

### User Story 8 - Existing carry and backlog choices move to the new decisions (Priority: P2)

The existing look-back asks, per project, whether leftover work is carried to next week or sent back to the backlog. These choices are mapped onto the new decisions. Carry becomes keep and recommit. Backlog becomes keep but park. Plans saved before this feature are still readable and show their old choice under the new names.

**Why this priority**: Without a mapping, old weekly plans would break or confuse the user.

**Independent Test**: Open a weekly plan saved before this feature that has one project carried and one sent to the backlog. Check that the plan loads and shows them as recommitted and parked.

**Acceptance Scenarios**:

1. **Given** a saved plan with a project marked carry, **When** the user opens it, **Then** it is shown as keep and recommit.
2. **Given** a saved plan with a project marked backlog, **When** the user opens it, **Then** it is shown as keep but park.
3. **Given** a saved plan whose projects were never labelled milestones, **When** the user opens it, **Then** the page loads and shows the stored project names and states, and the project is not changed.
4. **Given** a past plan, **When** the user opens it, **Then** its stored data is not changed by this feature.

---

### Edge Cases

- A committed milestone becomes orphaned during the week: it is kept in the plan with its stored name, shown as orphaned, and excluded from decisions that need the task manager (close and move). The user can still choose to park, recommit or decide later.
- A committed milestone is relabelled as theme or maintenance during the week: it stays in the plan for that week and is shown with a notice. It is not offered in the next picker as a milestone.
- All tasks in a milestone are completed before the end of the week: it is marked done at that moment (done date = the day its last task closed) and needs no decision at the review.
- A milestone has only dropped tasks left and at least one closed task: it is done by the completion rule, with a note that remaining tasks were dropped.
- A milestone has only dropped tasks and no closed task, or has no tasks at all: it is never done automatically. It stays unfinished and the user can still mark it done by hand.
- The user marks a milestone done by hand while it still has open tasks: the open tasks stay in the task manager under the done milestone and the user sees a notice. Nothing is moved or deleted. The done date is the day the user marked it, never the review day.
- A done milestone keeps the theme it had at the moment it was done. Swapping its theme later does not change that stored theme.
- The user commits the same milestone two weeks in a row without using the review: it counts as a rollover only when the review decision is made. Without a decision the rollover count does not change.
- The user closes a milestone whose parent theme is ignored or orphaned: the close option is hidden with a line saying why, because there is no valid place for the tasks.
- A plan with zero milestones: it is valid. The review shows only the work done outside the plan.
- The same milestone cannot be committed twice in one week. It can be committed in consecutive weeks, and in each week it is committed once.
- A week where the user commits a fourth milestone and finishes none: the review shows the warning history, not a block.
- A task manager that does not support moving tasks: the close option is hidden everywhere, and the other decisions work normally.
- A week that spans two months: the focus of the month of its Monday is used for the whole week.
- Existing month and week goals: they stay as read-only history and are not shown in the planning or review flow.
- The user chooses decide later on the same milestone several weeks in a row: nothing changes and no nudge is shown. The picker reminder stays until a real decision is made.

## Requirements *(mandatory)*

### Functional Requirements

**Planning**

- **FR-001**: The system MUST offer as candidates for weekly commitment only milestone projects that are eligible per feature 003. Theme, maintenance, ignored and orphaned projects MUST NOT be offered as commitments.
- **FR-002**: The system MUST group milestone candidates by their parent theme (the nearest ancestor labelled theme) and MUST show milestones with no parent theme in a "no theme" group.
- **FR-003**: The system MUST include parked milestones in the picker and mark them as parked.
- **FR-004**: The system MUST let the user commit milestones as the weekly commitment, and MUST store for each the milestone and its theme at the time. "Outside focus" MUST NOT be stored.
- **FR-005**: The cap of three MUST count milestone projects only. Maintenance projects and tasks MUST NOT count.
- **FR-006**: The system MUST NOT reject a commitment of more than three milestones. It MUST show a warning that states the count and the cap, and MUST remove the warning when the count is three or less. This replaces the existing hard limit, so existing tests that expect a rejection will change.
- **FR-007**: When monthly focus data exists, the system MUST show the focus themes first and highlight them, and MUST show a committed milestone under a non-focus theme as "outside focus". This status MUST be computed when it is read, from the monthly focus, and MUST NOT be stored.
- **FR-008**: When no monthly focus data exists, the system MUST offer all themes, MUST NOT highlight any, and MUST NOT show any milestone as outside focus.
- **FR-009**: The system MUST let the user create a new milestone under a theme. The user MUST give a name and a done-state, and the system MUST refuse an empty done-state.
- **FR-010**: Creating a milestone MUST follow the shared "create project and label it" rule owned by feature 003: create the sub-project under the theme in the task manager first, and only on success record the milestone label, the done-state and the commitment in Tefteri. On failure nothing is recorded and the user sees an error.
- **FR-011**: The system MUST store a milestone's done-state and show it wherever the milestone is shown in planning and review.
- **FR-012**: The system MUST let the user pick tasks from a menu of the milestone's open tasks, and add new tasks under the milestone. New tasks MUST be created in the task manager.
- **FR-013**: The system MUST store the committed task list per milestone. Open tasks that were not picked are "not committed this week". They MUST NOT be changed in the task manager.
- **FR-014**: A milestone MUST be committed at most once per week. It MAY be committed in consecutive weeks.
- **FR-015**: Weekly planning MUST NOT ask for, show or require goals. The weekly flow no longer includes goal selection or goal review. Existing month and week goals stay as read-only history. This changes existing behaviour, so the existing goal steps, their tests and their documentation change.

**Milestone state and completion**

- **FR-016**: The system MUST keep a state for each milestone: active, parked, closed or done. Parked is set only by the park decision in the review. A parked milestone that goes into a week's plan again (picked in the picker or recommitted) becomes active again.
- **FR-017**: A milestone MUST be considered done automatically when all its open tasks are closed or dropped AND at least one of its tasks was closed (completed). A milestone with no tasks, or with only dropped tasks, MUST NOT be done automatically. The user MAY always mark a milestone done by hand. Dropped tasks MUST NOT block completion.
- **FR-018**: When a milestone is marked done by hand while it has open tasks, the system MUST leave the tasks unchanged and show a notice.
- **FR-019**: The system MUST keep a rollover count for each milestone and MUST store the expected-rollover marker per rollover event (not one marker for the milestone). It MUST keep the count and the events as history after the milestone is done or closed.
- **FR-035**: When a milestone becomes done, the system MUST store its done date (the day its last task closed, or the day the user marked it done, never the review day) and the theme it had at that moment. Features 007 and 008 read these two fields. Later theme changes MUST NOT change them.

**Review**

- **FR-020**: The review MUST show committed tasks completed out of committed, milestones finished out of committed, and the pace across the week. When nothing was committed it MUST show a short note instead of ratios.
- **FR-021**: When monthly focus data exists, the review MUST show the focus share: the share of completed committed tasks that are under focus themes. When it does not exist, the review MUST NOT show this measure. The month of a week MUST be the month of its Monday.
- **FR-022**: The review MUST show the work done outside the plan using the weekly list defined by feature 005. This feature MUST NOT define the list limit or the treatment of maintenance tasks.
- **FR-023**: The review MUST offer one decision for each unfinished milestone: keep and recommit, keep but park, close and return its open tasks to the parent theme, or decide later. A finished milestone MUST NOT need a decision.
- **FR-024**: Keep and recommit MUST add the milestone to the next week's commitment, raise its rollover count by one and store a rollover event.
- **FR-025**: Keep but park MUST set the milestone state to parked, show it as parked in the picker, and leave its rollover count unchanged. Committing a parked milestone again MUST continue from its earlier rollover count.
- **FR-026**: Close and return tasks MUST first show the number of open tasks that will move and the theme they go to, and ask the user to confirm. After the confirmation it MUST move the milestone's open tasks to its parent theme project in the task manager, and MUST mark the milestone closed only after all moves succeed. If a move fails, the milestone MUST stay unclosed and the user MUST be told which tasks were moved so that retrying is safe.
- **FR-027**: The close option MUST be hidden when the task manager cannot move tasks (feature 003 capability check), when the milestone has no parent theme, or when the parent theme is ignored or orphaned. Where it is hidden, a short line MUST say why.
- **FR-028**: The system MUST NOT block the user from finishing a review. When unfinished milestones have no choice, it MUST name them and offer "decide later for all of these" in one action.
- **FR-029**: When recommitting, the user MUST be able to mark that rollover event as expected. An expected rollover MUST NOT cause a nudge.
- **FR-030**: The system MUST show a nudge to re-scope a milestone (shrink, split or close it) after two consecutive unmarked rollover events, and MUST NOT block the commitment. A marked rollover event ends the run of unmarked ones.
- **FR-031**: The existing carry choice MUST map to keep and recommit, and the existing backlog choice MUST map to keep but park. Plans saved before this feature MUST still open and show their choices under the new names, and MUST NOT be rewritten. This changes existing behaviour, so the existing look-back text, tests and documentation change.
- **FR-032**: Every screen and service in the weekly flow MUST work when a milestone or theme is orphaned and show the stored name.
- **FR-033**: The weekly planning flow MUST NOT break for users who have not classified their projects (feature 003). Unclassified projects are shown in an unsorted group with a way to label them as milestone from the picker.
- **FR-034**: The user documentation and the developer documentation MUST describe weekly planning and review with milestones, with screenshots made from fake data, in simplified technical English.
- **FR-036**: Decide later MUST leave the milestone state, its rollover count and its rollover events unchanged. The next picker MUST show a reminder on every milestone whose decision is still open, and MUST NOT block committing it.
- **FR-037**: A close and return MUST be undoable by reopening the milestone. Reopening MUST set the state back to active, move back the tasks of that close that were not changed since, and list any that could not be moved back. A failed move back MUST NOT block the reopen.
- **FR-038**: The month of a week MUST be the month of its Monday, for the focus used in planning and in the review.
- **FR-039**: Every picker and list in this flow that can be empty (milestones, themes, tasks) MUST offer an inline action in its empty state (create a milestone, "label a project as theme", "create a theme", add a task).
- **FR-040**: Each term in "Terms used in this feature" MUST be explained once, at its first use on the screen, in plain words.
- **FR-041**: Every destructive choice in this flow (close and return, mark done by hand) MUST show its effect before it is confirmed and MUST be undoable, or MUST say that nothing is moved or deleted.

### Key Entities *(include if feature involves data)*

- **Milestone project**: A project labelled milestone (feature 003) with extra planning data: done-state, state (active, parked, closed, done), rollover count, done date, theme at done, and a list of rollover events. It is kept after it is done or closed, as history.
- **Rollover event**: One recommit of a milestone, with its date and its own expected-rollover marker.
- **Weekly commitment**: The milestone projects and committed tasks of one week. It evolves the existing weekly plan and its project entries. Each entry holds the milestone, its theme at the time, the committed task ids and the review decision.
- **Review decision**: The choice made for one unfinished milestone in the weekly review: recommit, park, close or decide later. It includes the expected-rollover marker for a recommit. It replaces the carry and backlog choices.
- **Week review summary**: The numbers shown in the review: committed tasks completed, milestones finished, pace and focus share. The work done outside the plan comes from feature 005.
- **Theme project**: A project labelled theme (feature 003). It is the parent of milestones and is never committed. It receives the open tasks of a closed milestone.
- **Monthly focus (read only here)**: The themes chosen for the month (feature 007). This feature only reads it when it exists.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with classified projects can commit three existing milestones with tasks in under 5 minutes.
- **SC-002**: A user can create a new milestone with a done-state and have it committed in under 1 minute.
- **SC-003**: In 100% of tests, theme, maintenance, ignored and orphaned projects are never offered as weekly commitments.
- **SC-004**: In 100% of tests, a commitment of more than three milestones is saved and shows a warning. No commitment is rejected because of the cap.
- **SC-005**: A user can make a decision for every unfinished milestone in the review in under 30 seconds per milestone.
- **SC-006**: After the decisions are saved, 100% of recommitted milestones appear in the next week's commitment, 100% of parked milestones appear as parked in the picker, 100% of closed milestones have no open tasks left in them, and 100% of decide-later milestones are unchanged.
- **SC-007**: A milestone with two consecutive unmarked rollovers shows the nudge in 100% of tests, and no nudge appears after a marked rollover.
- **SC-008**: Every weekly plan saved before this feature opens without error and shows its old choices under the new names, in 100% of tests.
- **SC-009**: No weekly screen fails when a milestone or theme is orphaned, in 100% of tests.
- **SC-010**: With no monthly focus data, the weekly flow works end to end with no "outside focus" display and no focus measure.
- **SC-011**: In 100% of tests, a milestone that becomes done has a done date and a theme at done stored, and a milestone with no closed task is never done automatically.
- **SC-012**: In 100% of tests, a close and return shows the task count before it runs, and reopening restores the milestone to active.
- **SC-013**: In 100% of tests, a user can finish a review without making a real decision on any milestone, by using decide later.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral.
- Dependencies: feature 003 provides the labels (theme, milestone, maintenance, ignored), the label history, orphan handling, the capability check (including whether tasks can be moved), the eligibility rules for pickers and the shared "create project and label it" rule. This feature reads them and does not redefine them.
- Feature 007 (monthly focus) is read when it exists. Until then the picker offers all themes and the "outside focus" display and the focus measure are off. This feature does not create or edit monthly focus.
- Feature 005 owns the weekly "done outside the plan" list, its limit, the work categories and the treatment of maintenance work. This feature only shows that list in the review. "Off-plan" and "done outside the plan" mean only completed work that was not committed.
- Features 007 and 008 read the done date and the theme at done of a milestone. This feature owns them.
- Changes to existing behaviour (existing tests and documentation will change):
  - The weekly cap of three is no longer a hard limit. The server no longer rejects a fourth project. It is a warning on milestone count.
  - The unit of commitment changes from any project to a milestone project. Theme, maintenance and ignored projects are not offered.
  - The carry and backlog look-back choices are replaced by keep and recommit, keep but park, close and return tasks, and decide later. Old values are mapped on read and old rows are not rewritten.
  - Creating a sub-project during planning now creates a milestone with a done-state under a theme, and labels it.
  - Goals leave the weekly flow. Month and week goals, and the goal review inside the existing look-back, are no longer shown. Stored goal rows and past review records stay as read-only history. Goals are annual only (feature 006).
  - The weekly "done outside the plan" list follows feature 005, so the limit and the maintenance wording that were in the existing look-back are no longer defined here.
- The existing project picker, task menu, look-back page and history page are changed in place (evolve, do not rebuild).
- Pace across the week is calculated from task completion times and is a count of completions, never time spent.
- Out of scope: monthly and annual planning and review, key results, work-category statistics, calendar integration, quarterly checkpoints, and task managers without nested projects.
