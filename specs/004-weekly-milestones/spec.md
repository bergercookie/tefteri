# Feature Specification: Weekly Planning and Review with Milestone Projects

**Feature Branch**: `004-weekly-milestones` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "Change the existing weekly planning and look-back so that the unit of weekly commitment is a milestone project: a small project under a theme with a clear done-state, finishable in one week. The user commits up to three milestones (a warning, not a hard limit), picks tasks, and at the end of the week decides for each unfinished milestone whether to recommit it, park it or close it. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Does the weekly cap of three count milestone projects or themes, and is it hard? → A: It counts milestone projects and only warns. The server no longer rejects a fourth project.
- Q: Do weeks and months have their own goals? → A: No. Goals are an annual planning and review matter only. Months work on theme projects and weeks work on milestone projects. The weekly flow no longer asks for or reviews goals.
- Q: What counts as a completed milestone when some tasks were dropped? → A: A milestone is done when all its open tasks are closed or dropped, or when the user marks it done. Dropped tasks never block completion.
- Q: What if the monthly focus (feature 007) does not exist yet? → A: The picker offers all themes, with no highlight and no off-plan tag. Once focus data exists, it is used.
- Q: Is the calendar used in planning? → A: No. It is out of scope.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Commit milestone projects for the week (Priority: P1)

The user opens weekly planning. The picker lists milestone projects grouped by their theme. The user commits up to three milestones for the week. Each committed milestone is an existing one (active or parked) or a new one. The picker never offers theme projects, maintenance projects, ignored projects or orphaned projects as something to commit.

**Why this priority**: This is the core of the feature. Without it the weekly plan still works on open-ended projects and nothing else in this feature has a meaning.

**Independent Test**: With a few themes and milestones classified (feature 003), open planning, commit two existing milestones, and check that they are stored for the week and that no theme, maintenance or ignored project was offered.

**Acceptance Scenarios**:

1. **Given** classified projects, **When** the user opens the weekly picker, **Then** only milestone projects are offered as commitments, grouped under their parent theme, and parked milestones are included and marked as parked.
2. **Given** the user selects a milestone, **When** they commit the plan, **Then** the milestone is stored in the weekly commitment and its state is active.
3. **Given** a project labelled theme, maintenance or ignored, or an orphaned project, **When** the user opens the picker, **Then** it is not offered as a commitment. Its milestones, if any, are still offered unless an ancestor is ignored.
4. **Given** a theme that has no milestones yet, **When** the user opens the picker, **Then** the theme is shown with an action to create a new milestone under it.
5. **Given** a milestone that has no parent theme (top level), **When** the user opens the picker, **Then** it is listed under "no theme" and can be committed.
6. **Given** some projects are still unsorted, **When** the user plans, **Then** planning works and shows a quiet reminder, as in feature 003.

---

### User Story 2 - Create a new milestone with a clear done-state (Priority: P1)

The user has a theme but no suitable milestone. From the picker they create a new milestone under that theme. The user must give it a name that states a done-state ("ship the login flow", not "work on auth"). The milestone is created in the task manager as a sub-project of the theme and is recorded in Tefteri with the label milestone.

**Why this priority**: Milestones are invented during weekly planning. Without creating them, the user must leave Tefteri before every plan.

**Independent Test**: Choose a theme, create a milestone with a done-state, and check that it appears under the theme in the task manager, is labelled milestone in Tefteri, and is part of the week's commitment.

**Acceptance Scenarios**:

1. **Given** a theme, **When** the user creates a milestone with a name and a done-state, **Then** the task manager has a new sub-project under the theme, Tefteri labels it milestone, and it is added to the week's commitment.
2. **Given** the user leaves the done-state empty, **When** they try to create the milestone, **Then** creation is refused with a short hint on how to word a done-state.
3. **Given** the task manager fails to create the project, **When** the user creates a milestone, **Then** nothing is recorded in Tefteri and the user sees an error.
4. **Given** a milestone was created, **When** the user opens it later, **Then** its done-state is shown with it.

---

### User Story 3 - Pick or add tasks for the milestones (Priority: P1)

For each committed milestone the user picks tasks from a menu of its open tasks, and may add new tasks under it. The assembled list is the committed task list for the week. Tasks that the user does not pick stay in the milestone and are not committed (parked).

**Why this priority**: The committed task list is what daily execution and the weekly review measure.

**Independent Test**: Commit one milestone that has five open tasks, pick three, add one new task, commit, and check that the plan holds four committed tasks and one parked task, and that the new task exists in the task manager under the milestone.

**Acceptance Scenarios**:

1. **Given** a committed milestone with open tasks, **When** the user opens its task menu, **Then** its open tasks are listed and each can be selected.
2. **Given** the user adds a new task in the menu, **When** they commit, **Then** the task is created under the milestone in the task manager and is included in the committed list.
3. **Given** unselected tasks, **When** the user commits, **Then** they are stored as parked for this week and remain open in the milestone.
4. **Given** a milestone with no open tasks, **When** the user opens the menu, **Then** an empty state invites them to add the first task.

---

### User Story 4 - Go over the cap with a warning, and see off-plan milestones (Priority: P2)

The cap of three counts milestone projects. When the user commits a fourth, Tefteri shows a clear warning that the week is probably too full, and lets them continue. If monthly focus data exists (feature 007), the picker lists milestones under the month's focus themes first and highlights those themes. A milestone under a theme that is not in the focus is allowed and tagged off-plan. If no focus data exists, all themes are offered equally and nothing is tagged off-plan.

**Why this priority**: The cap and the focus guide the user but are not allowed to block them. The plan works without them.

**Independent Test**: Commit four milestones and check that a warning is shown and the plan is saved. With a monthly focus set, commit a milestone under a non-focus theme and check that it is tagged off-plan.

**Acceptance Scenarios**:

1. **Given** three milestones are committed, **When** the user adds a fourth, **Then** a warning states the count and the cap of three, and the user can still commit.
2. **Given** four milestones are committed, **When** the user removes one, **Then** the warning disappears.
3. **Given** a monthly focus exists, **When** the user opens the picker, **Then** the focus themes are shown first and highlighted.
4. **Given** a monthly focus exists, **When** the user commits a milestone under a theme that is not in the focus, **Then** it is tagged off-plan in the plan and in the review.
5. **Given** no monthly focus data exists, **When** the user opens the picker, **Then** all themes are offered with no highlight and no off-plan tag.
6. **Given** maintenance projects exist, **When** the user commits any number of milestones, **Then** maintenance projects are never counted in the cap.

---

### User Story 5 - Weekly review: how the week went (Priority: P2)

At the end of the week the user opens the review (the look-back). It shows how many committed tasks were completed, how many milestones were finished, and the pace across the week. It shows how much of the completed work served the month's focus themes (when focus data exists). It also lists the tasks done outside the plan. The review does not ask about goals, because goals are reviewed only in the annual review.

**Why this priority**: The review gives the feedback that makes the cap and the done-states meaningful, but planning works without it.

**Independent Test**: Commit a plan, complete some committed tasks, some tasks outside the plan and one task in a maintenance project, then open the review and check the numbers and the lists.

**Acceptance Scenarios**:

1. **Given** a finished week, **When** the user opens the review, **Then** it shows committed tasks completed out of committed, milestones finished out of committed, and the pace per day.
2. **Given** a monthly focus exists, **When** the user opens the review, **Then** it shows how much of the completed committed work was under focus themes.
3. **Given** no monthly focus exists, **When** the user opens the review, **Then** the focus measure is not shown.
4. **Given** tasks completed outside the commitment, **When** the user opens the review, **Then** they are listed as done outside the plan, as they are today, and maintenance tasks are not counted as committed work.
5. **Given** the review is opened, **When** it loads, **Then** no goal questions or goal review steps are shown for the week.

---

### User Story 6 - Decide on every unfinished milestone (Priority: P1)

In the review, each unfinished milestone needs a decision before the review can be closed. The three choices are: keep and recommit (it goes into next week's plan), keep but park (it stays active and returns to the picker later), or close and return its open tasks to the parent theme. Closing a milestone moves its open tasks to the parent theme project and closes the milestone. If the task manager cannot move tasks, the close option is not shown. A finished milestone needs no decision.

**Why this priority**: This forces a conscious choice about scope and replaces the existing carry and backlog choices.

**Independent Test**: Review a week with three unfinished milestones. Recommit one, park one, close one. Check that the next week's plan holds the recommitted milestone, the parked one is in the picker as parked, and the closed one has its open tasks back in the theme.

**Acceptance Scenarios**:

1. **Given** an unfinished milestone, **When** the user chooses keep and recommit, **Then** it is added to the next week's commitment and its rollover count goes up by one.
2. **Given** an unfinished milestone, **When** the user chooses keep but park, **Then** it stays active, is shown as parked in the picker, and its rollover count is unchanged.
3. **Given** an unfinished milestone with a parent theme, **When** the user chooses close and return tasks, **Then** its open tasks move to the parent theme, the milestone is closed, and it no longer appears in the picker.
4. **Given** an unfinished milestone with no parent theme, **When** the user opens the decision, **Then** the close option is not offered.
5. **Given** a task manager that cannot move tasks, **When** the user opens the decision, **Then** the close option is not shown.
6. **Given** the move of tasks fails part way, **When** the user chooses close, **Then** the milestone stays unclosed, the tasks already moved are reported, and the user can try again.
7. **Given** unfinished milestones without a decision, **When** the user tries to finish the review, **Then** the review reports which ones still need a decision.
8. **Given** a milestone that was finished during the week, **When** the user opens the review, **Then** it is shown as done and needs no decision.

---

### User Story 7 - Rollover count, expected rollover and re-scope nudge (Priority: P2)

Each recommit raises the milestone's rollover count. When recommitting, the user can mark it as an expected rollover ("this was bigger than a week"). An expected rollover never triggers a nudge. A milestone recommitted twice without the marker triggers a nudge to re-scope it (shrink it, split it, or close it).

**Why this priority**: It makes oversized milestones visible, but the weekly flow works without it.

**Independent Test**: Recommit a milestone twice without the marker and check that the nudge appears. Recommit another once with the marker and check that no nudge appears.

**Acceptance Scenarios**:

1. **Given** a milestone recommitted for the first time, **When** the user confirms, **Then** its rollover count is 1 and no nudge is shown.
2. **Given** a milestone with rollover count 1 and no marker, **When** the user recommits it again, **Then** the rollover count is 2 and a nudge asks the user to re-scope it.
3. **Given** the user marks a recommit as expected, **When** the milestone is recommitted, **Then** no nudge is shown for that recommit.
4. **Given** a nudge is shown, **When** the user ignores it, **Then** the user can still commit the milestone.
5. **Given** a milestone that is finished, **When** the user opens it later, **Then** its final rollover count is kept as history.
6. **Given** a parked milestone, **When** the user commits it again later, **Then** the rollover count continues from its earlier value. Parking does not reset it.

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

- A committed milestone becomes orphaned during the week: it is kept in the plan with its stored name, shown as orphaned, and excluded from decisions that need the task manager (close and move). The user can still choose to park or recommit it.
- A committed milestone is relabelled as theme or maintenance during the week: it stays in the plan for that week and is shown with a notice. It is not offered in the next picker as a milestone.
- All tasks in a milestone are completed before the end of the week: it is marked done at the review and needs no decision.
- A milestone has only dropped tasks left: it is done by the completion rule, with a note that remaining tasks were dropped.
- The user marks a milestone done by hand while it still has open tasks: the open tasks stay in the task manager under the done milestone and the user sees a notice. Nothing is moved or deleted.
- The user commits the same milestone two weeks in a row without using the review: it counts as a recommit only when the review decision is made. Without a decision the rollover count does not change.
- The user closes a milestone whose parent theme is ignored or orphaned: the close option is hidden, because there is no valid place for the tasks.
- A plan with zero milestones: it is valid. The review shows only work done outside the plan.
- Two plans committing the same milestone: this is allowed for consecutive weeks. A milestone is committed to at most one week at the same time.
- A week where the user commits a fourth milestone and finishes none: the review shows the warning history, not a block.
- Maintenance projects with many tasks: they never appear in the picker or the decisions, and their completed tasks never reduce the milestone completion numbers.
- A task manager that does not support moving tasks: the close option is hidden everywhere, and the other two decisions work normally.
- The weekly page in the existing flow shows up to 200 tasks done outside the plan: this limit is kept. If more exist, the review says the list is shortened.
- Existing month and week goals: they stay as read-only history and are not shown in the planning or review flow.

## Requirements *(mandatory)*

### Functional Requirements

**Planning**

- **FR-001**: The system MUST offer only milestone projects as candidates for weekly commitment. Theme, maintenance, ignored and orphaned projects MUST NOT be offered as commitments.
- **FR-002**: The system MUST group milestone candidates by their parent theme and MUST show milestones with no parent theme in a "no theme" group.
- **FR-003**: The system MUST include parked milestones in the picker and mark them as parked.
- **FR-004**: The system MUST let the user commit milestones as the weekly commitment, and MUST store for each the milestone, its theme at the time, and its off-plan tag.
- **FR-005**: The cap of three MUST count milestone projects only. Maintenance projects and tasks MUST NOT count.
- **FR-006**: The system MUST NOT reject a commitment of more than three milestones. It MUST show a warning that states the count and the cap, and MUST remove the warning when the count is three or less. This replaces the existing hard limit, so existing tests that expect a rejection will change.
- **FR-007**: When monthly focus data exists, the system MUST show the focus themes first and highlight them, and MUST tag a committed milestone under a non-focus theme as off-plan.
- **FR-008**: When no monthly focus data exists, the system MUST offer all themes, MUST NOT highlight any, and MUST NOT tag any milestone as off-plan.
- **FR-009**: The system MUST let the user create a new milestone under a theme. The user MUST give a name and a done-state, and the system MUST refuse an empty done-state.
- **FR-010**: Creating a milestone MUST create a sub-project under the theme in the task manager first, and only on success record the milestone label, the done-state and the commitment in Tefteri. On failure nothing is recorded and the user sees an error.
- **FR-011**: The system MUST store a milestone's done-state and show it wherever the milestone is shown in planning and review.
- **FR-012**: The system MUST let the user pick tasks from a menu of the milestone's open tasks, and add new tasks under the milestone. New tasks MUST be created in the task manager.
- **FR-013**: The system MUST store the committed task list per milestone, and MUST store unselected open tasks as parked for the week without changing them in the task manager.
- **FR-014**: A milestone MUST be committed to at most one week at a time.
- **FR-015**: Weekly planning MUST NOT ask for, show or require goals. The weekly flow no longer includes goal selection or goal review. Existing month and week goals stay as read-only history. This changes existing behaviour, so the existing goal steps, their tests and their documentation change.

**Milestone state and completion**

- **FR-016**: The system MUST keep a state for each milestone: active, parked, closed or done.
- **FR-017**: A milestone MUST be considered done when all its open tasks are closed or dropped, or when the user marks it done. Dropped tasks MUST NOT block completion.
- **FR-018**: When a milestone is marked done by hand while it has open tasks, the system MUST leave the tasks unchanged and show a notice.
- **FR-019**: The system MUST keep a rollover count and an expected-rollover marker for each milestone, and MUST keep them as history after the milestone is done or closed.

**Review**

- **FR-020**: The review MUST show committed tasks completed out of committed, milestones finished out of committed, and the pace across the week.
- **FR-021**: When monthly focus data exists, the review MUST show how much of the completed committed work served the focus themes. When it does not exist, the review MUST NOT show this measure.
- **FR-022**: The review MUST list tasks completed outside the commitment (done outside the plan), keep the existing limit of 200 and say when the list is shortened, and MUST NOT treat maintenance tasks as committed work.
- **FR-023**: The review MUST require one decision for each unfinished milestone: keep and recommit, keep but park, or close and return its open tasks to the parent theme. A finished milestone MUST NOT need a decision.
- **FR-024**: Keep and recommit MUST add the milestone to the next week's commitment and raise its rollover count by one.
- **FR-025**: Keep but park MUST keep the milestone active, mark it parked in the picker, and leave its rollover count unchanged. Committing a parked milestone again MUST continue from its earlier rollover count.
- **FR-026**: Close and return tasks MUST move the milestone's open tasks to its parent theme project in the task manager, and MUST mark the milestone closed only after all moves succeed. If a move fails, the milestone MUST stay unclosed and the user MUST be told which tasks were moved so that retrying is safe.
- **FR-027**: The close option MUST be hidden when the task manager cannot move tasks (feature 003 capability check), when the milestone has no parent theme, or when the parent theme is ignored or orphaned.
- **FR-028**: The system MUST NOT let the user finish a review while an unfinished milestone has no decision, and MUST name the ones still open.
- **FR-029**: When recommitting, the user MUST be able to mark the recommit as an expected rollover. An expected rollover MUST NOT cause a nudge.
- **FR-030**: When a milestone has been recommitted twice without the expected marker, the system MUST show a nudge to re-scope it, and MUST NOT block the commitment.
- **FR-031**: The existing carry choice MUST map to keep and recommit, and the existing backlog choice MUST map to keep but park. Plans saved before this feature MUST still open and show their choices under the new names, and MUST NOT be rewritten. This changes existing behaviour, so the existing look-back text, tests and documentation change.
- **FR-032**: Every screen and service in the weekly flow MUST work when a milestone or theme is orphaned and show the stored name.
- **FR-033**: The weekly planning flow MUST NOT break for users who have not classified their projects (feature 003). Unclassified projects are shown in an unsorted group with a way to label them as milestone from the picker.
- **FR-034**: The user documentation and the developer documentation MUST describe weekly planning and review with milestones, with screenshots made from fake data, in simplified technical English.

### Key Entities *(include if feature involves data)*

- **Milestone project**: A project labelled milestone (feature 003) with extra planning data: done-state, state (active, parked, closed, done), rollover count and expected-rollover marker. It is kept after it is done or closed, as history.
- **Weekly commitment**: The milestone projects and committed tasks of one week. It evolves the existing weekly plan and its project entries. Each entry holds the milestone, its theme at the time, the off-plan tag, the committed task ids, the parked task ids and the review decision.
- **Review decision**: The choice made for one unfinished milestone in the weekly review: recommit, park or close. It includes the expected-rollover marker when relevant. It replaces the carry and backlog choices.
- **Week review summary**: The numbers shown in the review: committed tasks completed, milestones finished, pace, focus share and tasks done outside the plan.
- **Theme project**: A project labelled theme (feature 003). It is the parent of milestones and is never committed. It receives the open tasks of a closed milestone.
- **Monthly focus (read only here)**: The themes chosen for the month (feature 007). This feature only reads it when it exists.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with classified projects can commit three existing milestones with tasks in under 5 minutes.
- **SC-002**: A user can create a new milestone with a done-state and have it committed in under 1 minute.
- **SC-003**: In 100% of tests, theme, maintenance, ignored and orphaned projects are never offered as weekly commitments.
- **SC-004**: In 100% of tests, a commitment of more than three milestones is saved and shows a warning. No commitment is rejected because of the cap.
- **SC-005**: A user can make a decision for every unfinished milestone in the review in under 30 seconds per milestone.
- **SC-006**: After the decisions are saved, 100% of recommitted milestones appear in the next week's commitment, 100% of parked milestones appear as parked in the picker, and 100% of closed milestones have no open tasks left in them.
- **SC-007**: A milestone recommitted twice without the expected marker shows the nudge in 100% of tests, and no nudge appears for an expected rollover.
- **SC-008**: Every weekly plan saved before this feature opens without error and shows its old choices under the new names, in 100% of tests.
- **SC-009**: No weekly screen fails when a milestone or theme is orphaned, in 100% of tests.
- **SC-010**: With no monthly focus data, the weekly flow works end to end with no off-plan tag and no focus measure.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral.
- Dependencies: feature 003 provides the labels (theme, milestone, maintenance, ignored), orphan handling and the capability check, including whether tasks can be moved. This feature reads them and does not redefine them.
- Feature 007 (monthly focus) is read when it exists. Until then the picker offers all themes and the off-plan tag and the focus measure are off. This feature does not create or edit monthly focus.
- Feature 005 (work categories) later extends the statistics. This feature keeps the existing "done outside the plan" list and only adds the maintenance separation needed for the review numbers.
- Changes to existing behaviour (existing tests and documentation will change):
  - The weekly cap of three is no longer a hard limit. The server no longer rejects a fourth project. It is a warning on milestone count.
  - The unit of commitment changes from any project to a milestone project. Theme, maintenance and ignored projects are not offered.
  - The carry and backlog look-back choices are replaced by keep and recommit, keep but park, and close and return tasks. Old values are mapped on read and old rows are not rewritten.
  - Creating a sub-project during planning now creates a milestone with a done-state under a theme, and labels it.
  - Goals leave the weekly flow. Month and week goals, and the goal review inside the existing look-back, are no longer shown. Stored goal rows and past review records stay as read-only history. Goals are annual only (feature 006).
- The existing project picker, task menu, look-back page and history page are changed in place (evolve, do not rebuild).
- Pace across the week is calculated from task completion times and is a count of completions, never time spent.
- Out of scope: monthly and annual planning and review, key results, work-category statistics beyond the existing list, calendar integration, quarterly checkpoints, and task managers without nested projects.
