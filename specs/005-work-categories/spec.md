# Feature Specification: Work Categories and Statistics

**Feature Branch**: `005-work-categories` (developed on the session branch)

**Created**: 2026-11-11

**Status**: Implemented

**Input**: User description: "Sort every completed task into one of three work categories: goal-aligned (work in a milestone project that was committed for the week), maintenance or off-plan (goal-type work that was not committed). Store the category once, when the task is first seen as completed, and never recompute it. Use one shared definition for any period, so the week, month and year views always agree. Show the three categories in one visual language, with counts and drill-down, and never hide or merge a category. Never track time. Source: `specs/planning-cycles/source-spec.md` (sections on daily execution and maintenance work, and on visual language and statistics), with the decisions in `specs/planning-cycles/decisions.md`."

## Clarifications

### Session 2026-11-11

- Q: Are goals part of this feature? → A: No. Goals are annual only (feature 006). The three work categories are decided by project labels (feature 003) and the weekly commitment (feature 004), never by month or week goals. Months work with theme projects and weeks with milestone projects.
- Q: Which project decides the category of a task that was moved between projects? → A: The project the task was in when it was completed. A later move does not change the category of an already completed task. A move before completion counts the new project. (Default, accepted unless the owner objects.)
- Q: What category is a task completed in an unclassified project, or in no project? → A: Off-plan, shown with a small "unsorted" note. It is goal-type work that nobody committed, and the user has not said otherwise. (Default.)
- Q: When is the category decided, and can it change? → A: It is decided once, when Tefteri first sees the task as completed, from the label the project had on the completion day (feature 003 label history) and the weekly commitment of the completion week (feature 004). It is stored and never recomputed, not when a label changes, not when a commitment is edited later, not on a re-sync. (Decision of 2026-11-11, replaces "recompute on edit".)
- Q: What happens to tasks in ignored projects? → A: They are not counted in any of the three work categories. The views show one quiet line with the number of hidden tasks, so no work disappears without a trace. (Default.)

## User Scenarios & Testing *(mandatory)*

### User Story 1 - See every completed task in one of three work categories (Priority: P1)

The user opens the weekly page after a busy week. Every task completed that week is listed and sits in exactly one work category: goal-aligned (work in a milestone project that was committed for the week), maintenance (in a maintenance project) or off-plan (goal-type work that was not committed). The three categories look different, and none is hidden. A helper line on the page says: "Goal-aligned means work in a milestone you committed to this week." Each category name is explained once, in one plain sentence, at its first use.

**Why this priority**: This is the core rule. The month and year views, the reviews and all later statistics depend on it.

**Independent Test**: Complete one task in a committed milestone, one in a maintenance project and one in a theme project that was not committed. Open the weekly page. Check that each task is listed once, in the right category, with its own style.

**Acceptance Scenarios**:

1. **Given** a task completed in a milestone project that was committed for the week, **When** the user opens that week, **Then** the task is goal-aligned and shown in the main style.
2. **Given** a task completed in a maintenance project, **When** the user opens that week, **Then** the task is maintenance and shown in the muted style, even if the project was never planned.
3. **Given** a task completed in a milestone or theme project that was not committed that week, **When** the user opens that week, **Then** the task is off-plan and shown outlined or accented.
4. **Given** any completed task in the week, **When** the three lists are added up, **Then** every task appears in exactly one category, with no duplicates and no gaps.
5. **Given** a task that was completed in a committed project but was not one of the committed task ids, **When** the user opens that week, **Then** the task is still goal-aligned, because the project was committed.

---

### User Story 2 - See the same numbers for a month and a year (Priority: P1)

The user opens the month view, then the year view. Instead of task lists, each shows the count for each of the three work categories and one proportion bar (for example 60% goal-aligned, 25% maintenance, 15% off-plan). The user taps a category or a bar segment and drills down to the tasks behind it. The month numbers are the sum of its days, and the year numbers are the sum of its months.

**Why this priority**: The month and year views are where the user judges whether the plan matches reality. They must use the same definition as the week.

**Independent Test**: Complete tasks of all three categories across several days of one month. Open the day counts and note them. Open the month view. Check that each month count equals the sum of the day counts, that the year count equals the sum of its months, and that drill-down lists exactly those tasks.

**Acceptance Scenarios**:

1. **Given** completed tasks in a month, **When** the user opens the month view, **Then** it shows three counts and one proportion bar.
2. **Given** the month view, **When** the user selects a category, **Then** the tasks of that category are listed, grouped by project, newest first.
3. **Given** the year view, **When** it is opened, **Then** it shows the same three counts and the same bar, as the sum of its months, and drill-down works the same way.
4. **Given** a month that spans two partial weeks, **When** the month view is opened, **Then** a task counts in the month of its completion date, and in the week of its completion date. A task is never counted twice in one period.
5. **Given** a period with no completed task, **When** the user opens it, **Then** no bar is drawn and an empty-state message is shown. When no project is labelled yet, the message offers the inline action "Label your projects", which opens the classification screen of feature 003.

---

### User Story 3 - The statistics stay honest (Priority: P1)

The three work categories are always shown separately. Maintenance is never folded into goal work to make a week look better, and off-plan work is never hidden to make a plan look better. The bar always has the three categories, the counts are plain counts of tasks, and nothing in the app measures time.

**Why this priority**: The value of the statistics is trust. A flattering number is worse than none.

**Independent Test**: Complete only maintenance tasks in a week. Check that the week shows 0 goal-aligned, N maintenance and 0 off-plan, and that the bar is 100% maintenance. Check that no screen shows hours, minutes, duration or a time estimate.

**Acceptance Scenarios**:

1. **Given** a period with tasks in only one category, **When** the user opens it, **Then** the bar shows 100% of that category and the other two categories are still shown with a count of zero.
2. **Given** a small category (for example 1 task in 100), **When** the bar is drawn, **Then** it is still visible, and its count is shown as a number.
3. **Given** any view in this feature, **When** it is inspected, **Then** no time spent, duration, hours or time estimate is shown or stored.
4. **Given** the percentages of a bar, **When** they are computed and rounded for display, **Then** they add up to 100. Percentages are never stored.
5. **Given** the user compares two periods, **When** the proportions differ, **Then** the counts are shown next to the proportions, so a change in total work is not hidden by a change in proportion.

---

### User Story 4 - No cap on done-outside-the-plan work (Priority: P1)

Today the weekly page shows at most 200 tasks that were done outside the plan. A user with a very active week sees only part of the work. After this feature, the count and the list cover every completed task of the period, and the weekly page can page through a long list.

**Why this priority**: A capped list silently breaks the honest-statistics rule.

**Independent Test**: Complete 250 tasks in off-plan projects in one week. Open the week. Check that the off-plan count is 250 and that all 250 can be reached in the list. This feature owns the weekly list of completed tasks; the weekly review of feature 004 uses it and does not set its own limit.

**Acceptance Scenarios**:

1. **Given** more than 200 off-plan tasks in a week, **When** the user opens the week, **Then** the count is the full number and every task can be reached.
2. **Given** a very long list, **When** the user scrolls or pages, **Then** the page stays responsive and no task is lost or repeated.
3. **Given** the month and year views, **When** they are opened, **Then** their counts are not limited by any cap.

---

### User Story 5 - Unusual projects and moved tasks are handled clearly (Priority: P2)

Some tasks sit in projects that are not neatly planned: an unclassified project, an ignored project, a project that disappeared from the task manager (orphaned, see feature 003), or a project the task was moved out of. The user sees a clear, stable answer for each.

**Why this priority**: These cases are common in real task managers. Without clear rules, the numbers would change in ways the user cannot explain.

**Independent Test**: Complete one task in each of: an unclassified project, an ignored project, an orphaned milestone that was committed, and a project the task was later moved out of. Open the week. Check each task against the rules in the acceptance scenarios.

**Acceptance Scenarios**:

1. **Given** a task completed in an unclassified project, **When** the user opens the week, **Then** it is off-plan with an "unsorted" note.
2. **Given** a task completed in an ignored project, **When** the user opens the week, **Then** it is not counted in any category, and a quiet line shows how many tasks are hidden for that reason.
3. **Given** a task completed in a committed milestone project that was later orphaned, **When** the user opens that week, **Then** it is still goal-aligned and shows the stored project name.
4. **Given** a task completed in a maintenance project that was later orphaned, **When** the user opens that week, **Then** it is still maintenance.
5. **Given** a task completed in project A and moved to project B afterwards, **When** the user opens the week, **Then** it keeps the category that project A gave it.
6. **Given** a task moved from project A to project B and then completed, **When** the user opens the week, **Then** project B decides its category.
7. **Given** a completed task in no project, **When** the user opens the week, **Then** it is off-plan with an "unsorted" note.
8. **Given** the user later changes the label of a project, **When** the user opens a past period, **Then** tasks completed before the change keep their category.
9. **Given** the weekly commitment of a past week is edited after tasks were first seen as completed, **When** the user opens that week, **Then** those tasks keep their stored category. Only tasks first seen as completed after the edit use the edited commitment.
10. **Given** the task manager cannot say what label a project had on the completion day, **When** Tefteri first sees the task, **Then** it reads the label history of feature 003 for the completion day, and uses the oldest known label if the history starts later.

---

### User Story 6 - Maintenance work is first-class and never nagged (Priority: P2)

The user does groceries and chores from a maintenance project. These tasks appear in daily work and are counted as maintenance. Planning never asks the user to commit to them, they have no finish line, and they do not count toward the weekly cap.

**Why this priority**: A system that only knows goal work misrepresents the week. This story confirms the maintenance category is complete, but daily work already shows these tasks.

**Independent Test**: Complete five maintenance tasks in a week without planning anything. Open the week. Check that the five tasks show as maintenance, and that no warning, reminder or cap message mentions them.

**Acceptance Scenarios**:

1. **Given** a maintenance project with completed tasks, **When** the user opens the week, **Then** the tasks are counted and listed as maintenance.
2. **Given** a week with many maintenance tasks, **When** the user checks the weekly cap, **Then** the cap and its warning (owned by feature 004) count only milestone projects.
3. **Given** a week with no commitment at all, **When** the user opens it, **Then** maintenance tasks are still maintenance, and goal-type tasks are off-plan.

---

### Edge Cases

- A week with no weekly commitment (feature 004): no task can be goal-aligned. Goal-type work is off-plan. Maintenance stays maintenance.
- A task completed in a theme project directly (not in a milestone): themes are never committed, so the task is off-plan.
- A milestone project committed for week 10 and not for week 11: a task completed in it in week 11 is off-plan, even if it was committed before. A milestone that is outside the month's focus is still goal-aligned when committed; this feature never reads the monthly focus.
- A milestone that was parked or closed during the week: it was committed for the week, so tasks completed in it that week are goal-aligned.
- A task completed late on Sunday or early on Monday near the week boundary: the completion time in the user's time zone decides the week.
- A task that was completed, then reopened, then completed again: only the latest completion counts, once. The category of the new completion is decided when it is first seen, and replaces the earlier one.
- A completed task that was deleted in the task manager: it leaves the statistics on the next sync. Past counts may drop. This is shown by the next sync, not hidden. Stored counts in review snapshots (feature 007) are not changed.
- A task completed but Tefteri has not synced yet: it appears after the next sync. The view shows when it last synced.
- A project that was a theme and is relabelled as maintenance in the middle of a month: tasks completed before the change keep their category (read from the label history of feature 003). Tasks after the change are maintenance.
- A very large year (tens of thousands of tasks): counts and the bar stay fast. Drill-down lists load in pages.
- Month and week goal rows from older versions: they are read-only history. They never change the category of any task.
- Checklist items inside a task are not tasks and are never counted.
- Recurring tasks: each completion of a recurring task is one completed task in the period it was completed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST place every completed task of a period in exactly one of three work categories: goal-aligned, maintenance or off-plan, or, in the one case in FR-008, in the hidden count. This feature owns these words. "Off-plan" and "done outside the plan" mean only completed work that was not committed.
- **FR-002**: A completed task MUST be goal-aligned when it was completed in a milestone project that was part of the weekly commitment (feature 004) for the week of its completion. In plain words: goal-aligned means work in a committed milestone. The weekly page MUST show this helper line.
- **FR-003**: A completed task MUST be maintenance when it was completed in a project labelled maintenance (on the completion day, per the label history of feature 003), whether or not that project was planned.
- **FR-004**: A completed task MUST be off-plan when it was completed in a theme project, or in a milestone project that was not part of the weekly commitment for the week of its completion.
- **FR-005**: A completed task in an unclassified project, or in no project, MUST be off-plan and MUST be marked "unsorted" in lists.
- **FR-006**: The category of a task MUST depend on the project the task was in when it was completed. A later move of the task MUST NOT change its category. A move before completion MUST count the new project.
- **FR-007**: The system MUST decide the category of a completed task once, when it first sees the task as completed, using the label the project had on the completion day (read from the label history of feature 003) and the weekly commitment of the completion week (feature 004). The category MUST be stored with the task and MUST NOT be recomputed: not when the label of its project changes later, not when the project is orphaned, not when the weekly commitment of a past week is edited, and not on a re-sync. Past periods keep their numbers. A new completion of a reopened task is a new first sight and gets its own category.
- **FR-008**: A completed task in a project labelled ignored, or under an ignored project, MUST NOT be counted in any of the three categories. The hidden count is stored the same way as the category counts (FR-025). Every view MUST show the number of such hidden tasks as one quiet line.
- **FR-009**: One shared definition MUST be used for the week, the month, the year and any other period. The numbers of a day come from the stored categories. The month numbers MUST equal the sum of its days, and the year numbers MUST equal the sum of its months. A week is the sum of its days.
- **FR-010**: A task MUST be counted in the period that holds its latest completion time, in the user's time zone, and only once per period.
- **FR-011**: Statistics MUST be computed on the server over all completed tasks of the period, so that every client shows the same numbers. Client-only calculation of categories MUST be removed.
- **FR-012**: The system MUST NOT limit the number of tasks counted or listed. The existing limit of 200 tasks done outside the plan MUST be removed. Long lists MUST load in pages without losing or repeating a task.
- **FR-013**: The three categories MUST always be shown separately. The system MUST NOT merge maintenance into goal work, and MUST NOT hide a category. A category with zero tasks MUST still be shown with a count of zero.
- **FR-014** (owner of the no-time-tracking rule; other specs refer to it): The system MUST NOT record, show or estimate time spent, duration, hours or effort in any view of this feature.
- **FR-015**: All views MUST use one visual language: goal-aligned in the main style, maintenance muted, off-plan outlined or accented. The style MUST NOT rely on colour alone, so that a user who cannot tell colours apart can still distinguish the categories.
- **FR-016**: The weekly view MUST list the completed tasks, grouped by category, each with its project name and its category style.
- **FR-017**: The month and year views MUST show a count for each category and one proportion bar, not task lists. Each count and each bar segment MUST open a drill-down list of the tasks behind it.
- **FR-018**: The percentages of the bar MUST be based on task counts, MUST be rounded so that they add up to 100, and MUST be shown next to the plain counts.
- **FR-019**: A period with no completed task MUST show an empty state and no bar.
- **FR-020**: Orphaned projects follow the rules of feature 003 (FR-010 to FR-012, FR-028) and are not redefined here. In this feature, the stored category of a task does not change when its project is orphaned, and screens show the stored project name.
- **FR-021**: The system MUST count every completion of a recurring task as a task, and MUST NOT count checklist items.
- **FR-022**: Each view MUST show when the data was last synced, because the numbers depend on the task manager.
- **FR-023**: The numbers of this feature MUST NOT depend on month or week goals. Existing month and week goal rows stay read-only history and have no effect on the categories.
- **FR-024**: The user documentation and the developer documentation MUST describe the three work categories and the rules of FR-002 to FR-008, with screenshots made from fake data, in simplified technical English.
- **FR-025**: For every day, the system MUST keep the count per category and the hidden count. Review snapshots (feature 007) store these counts, never shares. Percentages MUST be computed only for display.
- **FR-026**: This feature MUST NOT work without feature 004 (the weekly commitment). There is no fallback to the old weekly commitment of the current app. If feature 004 is not available, the views MUST say so and MUST NOT show guessed numbers.
- **FR-027**: Every empty view MUST offer an inline action next to the message (for example "Label your projects" or "Plan your week"). Every term (goal-aligned, maintenance, off-plan, unsorted, hidden) MUST be explained once, in one plain sentence, at its first use.
- **FR-028**: This feature has no destructive choice, because categories are results and not settings. No view MUST block the user: while a sync runs or has failed, the views MUST show the last stored numbers and the time of the last sync.
- **FR-029**: A task in a project that sits inside a maintenance project (at any depth) MUST be counted as maintenance, whatever the label of its own project is (decision 10 of `specs/planning-cycles/decisions.md`; the project labels are owned by feature 003).

### Key Entities *(include if feature involves data)*

- **Work category**: One of goal-aligned, maintenance or off-plan. It is a result of rules, not something the user sets by hand. It is stored once per completed task and never recomputed.
- **Completed task**: A task with a completion time, the project it was in when it was completed, and its stored category. The category is decided when the task is first seen as completed and is never recomputed (see FR-006 and FR-007).
- **Category summary**: The three counts and the hidden (ignored) count for one period. A day is stored, a month is the sum of its days and a year is the sum of its months. Proportions are computed on display and never stored. Feature 007 snapshots store these counts.
- **Period**: A day, week, month or year, defined by the user's time zone. Larger periods are made of smaller ones without overlap.
- **Project label** (feature 003): Theme, milestone, maintenance, ignored or unclassified. It decides which categories are possible for a project. The label on the completion day comes from the label history.
- **Weekly commitment** (feature 004): The milestone projects committed for a week. It decides whether work in a milestone is goal-aligned or off-plan when the task is first seen as completed.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: In 100% of test weeks, every completed task is in exactly one category or in the hidden count, and the categories plus the hidden count equal the number of completed tasks.
- **SC-002**: In 100% of test months and years, each month count equals the sum of its days and each year count equals the sum of its months.
- **SC-003**: A week with 1,000 completed tasks shows its counts and the first page of tasks in under 2 seconds. A year with 20,000 completed tasks shows its counts and bar in under 3 seconds.
- **SC-004**: No task is lost, hidden or repeated when a list has more than 200 tasks. A test with 1,000 tasks reaches every one of them.
- **SC-005**: The week, month and year views show the same count for the same period on every client and after every reload.
- **SC-006**: No screen of this feature shows or stores a time spent, duration or estimate.
- **SC-007**: A user can tell the three categories apart in a greyscale screenshot, in light and dark mode, on a phone and on a desktop width.
- **SC-008**: A user can answer "how much of this month was goal work, maintenance and off-plan?" in under 10 seconds from opening the month view.
- **SC-009**: No screen fails when a project is orphaned, ignored or unclassified, or when a task has been moved, in any view of this feature.
- **SC-010**: In 100% of tests that relabel a project or edit a past commitment after completion, the stored category of earlier tasks is unchanged.

## Assumptions

- The first supported task manager is Vikunja. This specification stays task-manager-neutral. The task manager supplies completion times, which is a required capability from feature 003.
- Dependencies: feature 003 provides the project labels, orphan handling and the capability check. Feature 004 provides the weekly commitment of milestone projects. This feature needs 004 and has no fallback: implementation of 005 starts after 004. The label on a given day comes from the label history of 003.
- A task keeps the project it was in when it was completed. If the task manager cannot tell where a task was at completion time, Tefteri uses the project it last saw for the task before completion, and records the project and the category when it first sees the task as completed. This is a plan decision.
- Dashboards and goals: month and year views show work categories only. Goal progress and key results belong to features 006 and 008. Monthly review (007) stores the counts of this feature in its snapshots, and annual review (008) reads those snapshots.
- **This feature changes existing behaviour.** The weekly service no longer caps done-outside-the-plan work at 200 tasks. The client-only cadence and category calculations in the weekly feature move to the server, and the client shows the server's numbers. The week, month and year views change to the shared visual language, and the month and year views show counts and a bar. Existing tests for the 200 task cap, the client-side calculation and the old month and year numbers will change. Existing documentation and screenshots for the weekly, month and year views will change.
- The burndown and cadence chart inside the weekly progress view is not removed by this feature. Only its source of categories changes.
- The visual style (main, muted, outlined or accented) is built from the existing theme and tokens. No new hard-coded colours are introduced.
- Out of scope: time tracking in any form, weighting tasks by size or effort, goal progress and key results, review flows, calendar use in planning, and task managers that do not meet the capability list of feature 003.
