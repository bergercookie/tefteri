# Feature Specification: Monthly Planning and Review

**Feature Branch**: `007-monthly-cycle` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Draft

**Input**: User description: "Plan and review each month around theme projects. In monthly planning the user picks three to five theme projects as the month's focus and sets a milestone-count target for each, and sees the key results behind each choice. At the end of the month the user reviews targets against results, updates key results, sees the gap between milestones shipped and key result movement, sees the off-plan trend, decides what happens to each theme, and stores a review snapshot. This replaces the current goal-based Month view. Source: `specs/planning-cycles/source-spec.md`, with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Are there month goals? → A: No. Goals are annual only (feature 006). For months the user works on themed projects, and for weeks on milestone projects. Existing month goal rows stay as read-only history and are not shown in the new flow.
- Q: Does monthly planning create milestone projects? → A: No. Milestones are created in weekly planning (feature 004). Monthly planning only chooses themes and sets targets.
- Q: Can the focus change during the month? → A: Yes. A theme can be swapped mid-month. The swap is recorded in history and never changes a stored snapshot.
- Q: What is the existing period review? → A: It stores goal review notes per plan. The monthly review snapshot is a new, separate record. The old record is not changed and is not used by the new flow.
- Q: How many themes may be chosen? → A: Three to five is the guidance. Going outside it shows a quiet note and is allowed. This follows the same rule style as the weekly cap in feature 004.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pick the themes for the month (Priority: P1)

At the start of a month the user opens monthly planning. Tefteri lists the theme projects. The user picks three to five of them as the month's focus. Each chosen theme shows how many milestones were finished under it last month, as a hint. The user saves. The picked themes are now the monthly focus.

**Why this priority**: The monthly focus is the link between the year and the week. Weekly planning (feature 004) draws from it, so nothing else in the monthly cycle works without it.

**Independent Test**: With at least six theme projects, open monthly planning, pick four, save, reload, and check that the four are shown as the month's focus. Open the weekly project picker and check that the four themes are shown first.

**Acceptance Scenarios**:

1. **Given** classified projects, **When** the user opens monthly planning, **Then** only theme projects are offered. Milestone, maintenance, ignored and orphaned projects are not offered.
2. **Given** the user picks four themes and saves, **When** they return to the month, **Then** the four themes are shown as the monthly focus.
3. **Given** the user picks six themes, **When** they save, **Then** the save works and a quiet note says that three to five is the usual size.
4. **Given** no theme is picked, **When** the user saves, **Then** the month has an empty focus, a quiet note says so, and planning is not blocked.
5. **Given** a saved monthly focus, **When** the user opens weekly planning, **Then** the focus themes are shown first and highlighted.

---

### User Story 2 - Set a milestone-count target for each theme (Priority: P1)

For each chosen theme the user sets a target number of milestones to finish this month, for example "finish three milestones under the open source theme". There are no hour or time targets. A theme may have a target of zero when the user only wants to keep it in view.

**Why this priority**: A target makes the month's review concrete. Without it the review has nothing to compare against.

**Independent Test**: Pick two themes, set targets of 3 and 1, save, reload, and check both targets. Try to enter a negative number and check that it is refused.

**Acceptance Scenarios**:

1. **Given** a chosen theme, **When** the user enters a whole number of zero or more, **Then** it is stored as the target for that theme and month.
2. **Given** a target field, **When** the user enters a negative number, a decimal or text, **Then** the value is refused with a clear message.
3. **Given** a chosen theme with no target entered, **When** the user saves, **Then** the target is stored as zero and the theme is marked "no target" in the review.
4. **Given** the screen, **When** the user looks for time or hour targets, **Then** there are none.

---

### User Story 3 - See the key results behind each choice (Priority: P1)

Next to each theme the screen shows the key results linked to it (feature 006) and how far each has moved so far in the year: start value, current value, target and deadline. A key result with no theme picked this month is flagged quietly as unattended. This makes ignoring a key result a deliberate choice.

**Why this priority**: It ties the month to the year's goals. Without it the user picks themes blind.

**Independent Test**: Link three key results to three themes. Pick two of the themes. Check that the key results are shown beside their themes, and that the key result of the third theme is flagged as unattended.

**Acceptance Scenarios**:

1. **Given** a theme linked to two key results, **When** the user picks it, **Then** both key results are shown with their progress.
2. **Given** a key result served by two themes and only one of them is picked, **When** the user views the screen, **Then** the key result is not flagged, because at least one linked theme is in focus.
3. **Given** a key result whose linked themes are all unpicked, **When** the user views the screen, **Then** it is flagged as unattended, with the goal it belongs to.
4. **Given** a key result with no linked theme at all, **When** the user views the screen, **Then** it is flagged as unlinked and the user is pointed to annual planning to fix it.
5. **Given** a theme with no linked key result, **When** the user picks it, **Then** it is allowed and marked "not linked to a key result".

---

### User Story 4 - Change the focus mid-month (Priority: P2)

During the month the user swaps one focus theme for another, adds a theme, or removes one. The change is recorded with its date and the old and new theme. Work already finished under the old theme is not lost, and past snapshots do not change.

**Why this priority**: Plans change. Recording the change keeps the review honest about what was really planned.

**Independent Test**: Plan a month with three themes. Swap one for another in the middle of the month. Check that the focus shows the new theme, that the history shows the swap with its date, and that the review lists both themes.

**Acceptance Scenarios**:

1. **Given** a month in progress, **When** the user swaps a theme, **Then** the new theme is in focus and the history records the swap with the date.
2. **Given** a swap, **When** the user sets a target for the new theme, **Then** the target counts milestones finished from the swap date to the end of the month. Milestones the new theme finished earlier in the month are shown in the review but do not count towards the target.
3. **Given** a theme that was removed from the focus, **When** the review opens, **Then** the theme is still listed, marked "swapped out", with its target and the milestones it finished.
4. **Given** weekly commitments already made under the old theme, **When** the swap happens, **Then** those commitments are not changed or removed.

---

### User Story 5 - Review targets against results (Priority: P1)

At the end of the month, the user opens the monthly review. For each focus theme the screen shows the target and the number of milestones finished under it in the month. A milestone counts when it is done (feature 004). The user sees at a glance which themes hit, missed or beat their target.

**Why this priority**: This is the core of the review. It turns the month's plan into an honest result.

**Independent Test**: Plan a month with a target of 3 for one theme. Finish two milestones under it. Open the review and check "2 of 3". Finish a third and check "3 of 3".

**Acceptance Scenarios**:

1. **Given** a focus theme with a target of 3 and two done milestones, **When** the user opens the review, **Then** it shows 2 of 3 and a missed marker.
2. **Given** a theme with four done milestones and a target of 3, **When** the user opens the review, **Then** it shows 4 of 3 and a beaten marker.
3. **Given** a milestone that was done in the month but belongs to a theme that was not in focus, **When** the user opens the review, **Then** it is shown in a separate "outside the focus" list and is not counted against any target.
4. **Given** a milestone that was closed or parked, **When** the review counts results, **Then** it does not count as done.
5. **Given** a milestone that moved to another theme during the month, **When** the review counts results, **Then** it counts under the theme it had when it became done.

---

### User Story 6 - Update key results and see the gap (Priority: P1)

In the review the user updates the key results. Key results with an automatic source are pulled in. Key results with a manual source ask for a new value in a quick prompt. Tefteri then shows milestones shipped next to key result movement for each theme, so a case such as "six milestones shipped, the key result barely moved" is easy to see.

**Why this priority**: The gap between effort and effect is the main insight of the month. It lets the user judge whether the themes were the right ones.

**Independent Test**: Link a manual key result to a theme that shipped three milestones. Enter a new value in the review. Check that the shipped count and the change in the key result are shown side by side. Link an automatic key result and check that its value is pulled without a prompt.

**Acceptance Scenarios**:

1. **Given** a key result with an automatic source, **When** the review opens, **Then** its value is pulled in and shown with the time it was pulled.
2. **Given** an automatic pull fails, **When** the review opens, **Then** the last known value is shown with a clear "not updated" note and a way to enter a value by hand.
3. **Given** a key result with a manual source, **When** the review opens, **Then** the user is asked for a new value, and may skip it.
4. **Given** the user skips a manual key result, **When** the review is stored, **Then** the snapshot keeps the last known value and marks it "not updated this month".
5. **Given** a theme with milestones shipped and linked key results, **When** the review shows the gap, **Then** it shows, for each key result, the value at the start of the month, the value now, and the change, next to the milestone count of the theme.
6. **Given** a key result that is served by several themes, **When** the gap is shown, **Then** the change is shown once for the key result and listed under each theme, with a note that it is shared.
7. **Given** a key result with no value at the start of the month, **When** the gap is shown, **Then** the start value of the key result is used as the base.

---

### User Story 7 - See the off-plan trend (Priority: P2)

The review shows the month's share of completed work by kind: goal-aligned, maintenance and off-plan (feature 005). It also shows whether the off-plan share is rising compared with the earlier months. A steady maintenance share is normal. A rising off-plan share is a hint that the plan does not match what really happens.

**Why this priority**: It helps the user notice drift. The month review is still useful without it.

**Independent Test**: With data for three months where off-plan work grows each month, open the review and check that the off-plan share is shown with a "rising" marker. With flat data check that there is no such marker.

**Acceptance Scenarios**:

1. **Given** a month with completed tasks, **When** the user opens the review, **Then** the counts and shares of the three kinds are shown, using the numbers of feature 005 and not a new calculation.
2. **Given** the off-plan share is higher than in each of the previous two months, **When** the review opens, **Then** the share is marked as rising.
3. **Given** fewer than two earlier months of data, **When** the review opens, **Then** no trend is shown and a note says there is not enough history.
4. **Given** a month with no completed task, **When** the review opens, **Then** an empty state is shown for this section and no bar.
5. **Given** the maintenance share is high but steady, **When** the review opens, **Then** it is not marked as a problem.

---

### User Story 8 - Decide what happens to each theme (Priority: P1)

For each focus theme the user decides: carry it forward to next month, drop it, or swap it for another theme. The decisions are saved with the review. Carried-forward themes are offered as the starting point of the next monthly plan, with their targets as editable suggestions.

**Why this priority**: The decision closes the cycle. It makes the user choose, instead of drifting from one month to the next.

**Independent Test**: Review a month with three themes. Carry one, drop one, swap one for another. Open next month's planning and check that the carried theme and the swap target are offered, and that the dropped theme is not.

**Acceptance Scenarios**:

1. **Given** a focus theme in the review, **When** the user chooses carry forward, **Then** the theme is offered in next month's plan with the same target as an editable suggestion.
2. **Given** a theme, **When** the user chooses drop, **Then** it is not offered in next month's plan as a suggestion, and it stays available in the normal theme list.
3. **Given** a theme, **When** the user chooses swap and names another theme, **Then** the other theme is offered in next month's plan, and the swap is stored with the review.
4. **Given** a theme with no decision, **When** the user tries to finish the review, **Then** the review asks for a decision for each theme. The user may finish with "decide later", which stores the review with no decision for that theme.
5. **Given** the next month has no plan yet, **When** the user opens monthly planning, **Then** the suggestions from the last review are shown. They are never saved as a plan until the user saves.

---

### User Story 9 - Store a review snapshot that never changes (Priority: P1)

When the user finishes the review, Tefteri stores one snapshot for the month. It holds the month, the focus themes with their targets and results, the swaps, the decisions, and the value of every linked key result at that time. The snapshot is never recomputed. If a project is later renamed, relabelled, orphaned or deleted, or if a task is moved, the snapshot is the same. The annual review (feature 008) reads these snapshots.

**Why this priority**: Without a fixed record, history changes when projects change, and the annual review would show wrong numbers.

**Independent Test**: Finish a review. Then rename a theme, relabel a milestone and delete a task in the task manager and sync. Open the stored review and check that every number and every name is the same as when it was stored.

**Acceptance Scenarios**:

1. **Given** a finished review, **When** the user opens the month later, **Then** the stored snapshot is shown, not a fresh calculation.
2. **Given** a stored snapshot, **When** a theme is renamed or orphaned later, **Then** the snapshot still shows the name stored at review time.
3. **Given** a stored snapshot, **When** the user wants to change it, **Then** they can reopen the review, change it, and save again. The previous version is kept in the month's history, and the date of the change is shown.
4. **Given** a month with no finished review, **When** the user opens it, **Then** a live, labelled-as-draft view is shown and is not stored until the user finishes.
5. **Given** a stored snapshot, **When** the annual review reads it, **Then** it reads the stored values and never recalculates them.

---

### User Story 10 - The Month view is theme-based (Priority: P2)

The current Month view is goal-based. It is replaced by the monthly planning and review screens. The monthly checklist (the plain list of monthly tasks) stays as it is. Month goals leave the flow. Existing month goal rows stay as read-only history and are not shown in the new flow.

**Why this priority**: It removes the old model from the user's sight. The features above work without it, but the product would then show two competing ideas of a month.

**Independent Test**: Open the Month view. Check that it shows the focus themes, targets and review, and no goal list. Check that the monthly checklist works as before.

**Acceptance Scenarios**:

1. **Given** the new Month view, **When** the user opens it, **Then** it shows the month's focus, its progress and the review, and does not offer to create a month goal.
2. **Given** existing month goal rows, **When** the user opens the Month view, **Then** they are not shown, and the data is not deleted.
3. **Given** the monthly checklist, **When** the user opens the Month view, **Then** the checklist works as it did before.
4. **Given** a month in the past that has only old goal data, **When** the user opens it, **Then** the old data can be read in a read-only "earlier format" view, and no snapshot is made from it.

---

### Edge Cases

- A theme that is orphaned during the month: it keeps its place in the focus, shows the stored name, and is marked orphaned. The review still counts its milestones from the stored data. It is not offered for next month.
- A theme relabelled during the month (for example to maintenance or ignored): it stays in the month's focus as planned and is marked "label changed". It is not offered for next month. Past snapshots do not change.
- A month with no key results (the user has no annual plan): monthly planning and review still work. The key result sections show an empty state with a pointer to annual planning.
- A key result whose deadline has passed: it is still shown, marked past deadline.
- A key result that was retired or re-linked in the middle of the year: the review uses the links that were valid in the month, from the stored history of feature 006.
- A month at the edge of a year: the planning uses the annual cycle that holds the month. A month in December and the next one in January use different cycles, and the link suggestions follow the cycle of each month.
- Two different times zones: the month starts and ends in the user's time zone. A milestone done at 00:30 on the first day counts in that month.
- A user who skips a whole month: the month has no plan and no snapshot. The next monthly plan offers the last stored decisions, if any, and says which month they came from.
- A user who plans a future month in advance: allowed. Results are empty until the month starts.
- A theme picked twice, or a theme picked in a month that already has it: refused with a clear message, one entry per theme.
- A very large number of themes (hundreds): the picker is searchable and grouped.
- A key result with an automatic source and no network: see User Story 6, the last known value is shown.
- Deleting a milestone that counted toward a target: a stored snapshot does not change. A draft review counts again from the live data.
- Monthly focus and the weekly cap are separate: the focus of three to five themes does not limit the three milestone projects of a week.

## Requirements *(mandatory)*

### Functional Requirements

**Monthly planning**

- **FR-001**: The system MUST let the user choose the theme projects for a month. Only projects labelled theme, and not orphaned, MUST be offered. Together with their targets they form the monthly focus.
- **FR-002**: The system MUST suggest three to five themes. It MUST allow fewer or more and MUST show a quiet note when the number is outside this range. It MUST NOT block saving.
- **FR-003**: The system MUST store for each focus theme one target: a whole number of milestones of zero or more. It MUST refuse any other value. It MUST NOT offer time, hour or effort targets.
- **FR-004**: The system MUST allow each theme at most once in the focus of a month.
- **FR-005**: The system MUST NOT create milestone projects, tasks or any other project in the task manager during monthly planning.
- **FR-006**: The system MUST show, for each theme, its linked key results (feature 006) with start value, current value, target, deadline and progress.
- **FR-007**: The system MUST flag a key result as unattended when none of its linked themes is in the month's focus. The flag MUST be quiet and MUST NOT block planning.
- **FR-008**: The system MUST flag a key result with no linked theme as unlinked and point the user to annual planning. It MUST NOT let the user create links in monthly planning.
- **FR-009**: The system MUST show for each theme the milestones finished under it last month, as a hint.
- **FR-010**: The system MUST offer the carried-forward themes and targets of the last stored review as editable suggestions, and MUST NOT save them as a plan until the user saves.
- **FR-011**: The system MUST make the monthly focus available to weekly planning (feature 004), which shows the focus themes first. The monthly focus MUST NOT limit what the weekly picker can offer.

**Changing the focus**

- **FR-012**: The system MUST allow the user to swap, add or remove a focus theme at any time during the month.
- **FR-013**: The system MUST record each change with its date, the theme that left and the theme that came. A swap MUST NOT change any stored snapshot, and MUST NOT change or remove existing weekly commitments.
- **FR-014**: The system MUST count a target for a theme that was added during the month from the date it was added. It MUST show milestones done earlier in the month under that theme separately.
- **FR-015**: The review MUST list themes that were swapped out, with their targets and results.

**Monthly review**

- **FR-016**: The system MUST show for each focus theme the target and the number of milestones that became done under it in the month, and mark it as missed, met or beaten. A theme with no target MUST be marked "no target".
- **FR-017**: A milestone MUST count as done only when it is done by the rule of feature 004. A closed or parked milestone MUST NOT count. A milestone MUST count under the theme it had when it became done.
- **FR-018**: The system MUST list milestones that became done in the month under a theme that was not in focus, in a separate list, and MUST NOT count them against any target.
- **FR-019**: The system MUST pull the value of each key result with an automatic source when the review opens, and show the time of the pull. If the pull fails, it MUST show the last known value with a "not updated" note and allow a manual value.
- **FR-020**: The system MUST ask for a new value for each key result with a manual source, and allow the user to skip it. A skipped key result MUST keep the last known value and be marked "not updated this month".
- **FR-021**: The system MUST show, for each focus theme, the milestones shipped next to the movement of each linked key result: its value at the start of the month, its value now and the change. A key result shared by several themes MUST show the change once and be marked as shared.
- **FR-022**: The system MUST NOT claim that shipped milestones caused a key result change. It MUST show the two side by side without a computed score.
- **FR-023**: The system MUST show the counts and shares of goal-aligned, maintenance and off-plan work for the month, using the numbers of feature 005, and MUST NOT calculate the kinds again.
- **FR-024**: The system MUST show whether the off-plan share is rising. The share is rising when it is higher than in each of the previous two months. With fewer than two earlier months of data it MUST show no trend and say so. A steady or high maintenance share MUST NOT be marked as a problem.
- **FR-025**: The system MUST ask the user to decide, for each focus theme, to carry it forward, drop it or swap it for another theme. It MUST allow "decide later" and MUST NOT block finishing the review.
- **FR-026**: A decision to swap MUST name the other theme. The system MUST offer carried-forward themes and swap targets in the next month's plan, as in FR-010, and MUST NOT offer dropped themes as suggestions.

**Snapshot**

- **FR-027**: When the user finishes the review, the system MUST store one review snapshot for the month. It MUST hold the month, each focus theme with its stored name, target and result, the list of swaps, the decisions, the outside-the-focus milestones, the shares of the three kinds, and the value, the start value and the update status of every linked key result.
- **FR-028**: The review snapshot is a new record. It MUST NOT change, reuse or replace the existing period review record that holds goal review notes. The existing record stays as it is.
- **FR-029**: The system MUST NOT recompute a stored snapshot. A rename, relabel, move, orphaning or deletion of a project or task after the review MUST NOT change it. Stored names MUST be shown, not live names.
- **FR-030**: The system MUST allow the user to reopen and save a finished review again. It MUST keep the earlier version in history with its date, and MUST show which version is current.
- **FR-031**: A month with no finished review MUST show a live view labelled as a draft. The draft MUST NOT be stored until the user finishes.
- **FR-032**: The system MUST make the stored snapshots readable by the annual review (feature 008) without recalculation.

**Month view and existing data**

- **FR-033**: The system MUST replace the goal-based Month view with the monthly planning and review screens. This changes existing behaviour: the existing screens, tests and documentation of the Month view will change.
- **FR-034**: The monthly checklist MUST stay and MUST work as before.
- **FR-035**: The system MUST NOT offer to create or edit a month goal. Existing month goal rows MUST stay in storage as read-only history and MUST NOT be shown in the new flow. A past month that has only old goal data MUST open in a read-only "earlier format" view.
- **FR-036**: The system MUST NOT create a snapshot from old month goal data.

**General**

- **FR-037**: Every screen and service in this feature MUST work with an orphaned project and show its stored name.
- **FR-038**: The month MUST start and end in the user's time zone.
- **FR-039**: The monthly focus, targets, swaps, decisions and snapshots MUST be private to the user, per connection.
- **FR-040**: The system MUST NOT record, show or estimate time spent, duration, hours or effort in any view of this feature.
- **FR-041**: The user documentation and the developer documentation MUST describe monthly planning and review, with screenshots made from fake data, in simplified technical English. The documents of the old Month view MUST be updated.

### Key Entities *(include if feature involves data)*

- **Monthly focus**: The theme projects chosen for one month for one user. It holds the month, and a list of focus entries.
- **Focus entry**: One theme in a monthly focus, with its milestone-count target, the date it entered the focus and, if it left, the date and reason (swapped out, removed).
- **Focus change**: A record of a swap, add or remove during the month, with the date, the theme that left and the theme that came.
- **Monthly review snapshot**: The stored result of a monthly review. It holds the month, the focus themes with stored names, targets and results, the swaps, the outside-the-focus milestones, the shares of the three kinds, the key result values, the decisions and a version number. It is never recomputed and is read by the annual review.
- **Theme decision**: The choice for one theme in a review: carry forward, drop, swap (with the other theme) or decide later.
- **Key result value**: The value of a key result at the start and at the end of the month, with its source (manual or automatic), the time it was taken and its update status (updated, not updated).
- **Key result** (feature 006) and **Key result to theme link** (feature 006): Read here. They are not changed by this feature.
- **Milestone project** and **Theme project** (features 003 and 004): Read here for counting. They are not changed by this feature.
- **Period review** (existing): The older record of goal review notes per plan. It is not changed and is not used by the new flow.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user with 20 theme projects can plan a month, with three themes and their targets, in under 3 minutes.
- **SC-002**: A user can finish the monthly review, including key result values and a decision for each theme, in under 10 minutes for a month with five focus themes.
- **SC-003**: The numbers of milestones per theme in the review equal the count of done milestones in the data, in 100% of tests on the demo data set, including swaps, moved milestones and orphaned themes.
- **SC-004**: After a rename, relabel, move, orphaning or deletion in the task manager and one sync, a stored snapshot is identical to the one stored at review time, in 100% of tests.
- **SC-005**: The three kinds of work in the review equal the numbers of feature 005 for the same month, in 100% of tests. The review makes no separate calculation.
- **SC-006**: Every key result that has no focus theme is flagged on the planning screen and in the review, in 100% of tests.
- **SC-007**: No screen of this feature fails when a theme or milestone is orphaned.
- **SC-008**: No project, task or field is created or changed in the task manager by monthly planning or review. The contract tests confirm it.
- **SC-009**: The Month view no longer shows any goal-creation control, and the monthly checklist still passes its existing tests.
- **SC-010**: The review opens in under 3 seconds for a month with 500 completed tasks, when automatic key result sources respond. A slow or failing source never blocks the screen.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral.
- Dependencies: feature 003 gives the labels (theme, milestone, maintenance, ignored), orphan handling and the capability check. Feature 004 defines when a milestone is done, how milestones belong to a theme, and how weekly planning reads the monthly focus. Feature 005 gives the shares of goal-aligned, maintenance and off-plan work, computed on the server. Feature 006 gives goals, key results with their sources and values, and the key result to theme links per annual cycle. Feature 008 reads the snapshots made here.
- This feature changes existing behaviour. The current Month view is goal-based and is replaced. Its tests and its user and developer documentation will change. Month goal rows are kept as read-only history. The existing period review record is kept unchanged and unused by the new flow.
- Goals are annual only (decision). Month and week goals leave the planning flow. This feature does not create, edit or show them.
- Key results have one type: a number with a start value, a target and a deadline. Their source is manual or automatic. Other types come later.
- A milestone is done when all its open tasks are closed or dropped, or when the user marks it done (decision). Dropped tasks never block completion. Feature 004 owns this rule.
- The rising off-plan trend compares the month with the two months before it. This is a default and may be tuned in the plan.
- The start value of a key result for a month is its value in the snapshot of the month before, or its own start value if none exists.
- Automatic key result sources are pulled by the key result feature (006). This feature only asks for the current value when the review opens.
- The weekly cap of three milestone projects is not affected. The focus of three to five themes is guidance and is also never a hard limit.
- Out of scope: creating milestone projects, linking key results to themes (annual planning), the weekly review, the annual review, quarterly checkpoints, calendar use in planning, time budgets and hour targets, paired controllable key results, and task managers without nested projects.
