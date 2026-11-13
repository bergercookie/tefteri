# Feature Specification: Split Tasks-and-Calendar Planning Layout

**Feature Branch**: `002-split-planning-layout`

**Created**: 2026-11-02

**Status**: Implemented

**Input**: User description: "I want a different layout as the default where, there's two columns for tasks and calendars: on the left hand side a task view, and on the right hand side my calendar. I should be able to drag and drop tasks to the calendar and that should automatically assign a datetime to them. Also, tasks with already a date/ datetime should appear at the calendar, in the right timeslot. We use due dates as the date of preference for vikunja. and just set the \"start time\" of the event to something like \"due-date\"-1h"

## Clarifications

### Session 2026-11-02

- Q: When a task is dropped on a calendar slot, is that slot the block start or the due time? → A: The slot is the block start. The due time is the slot time plus 1 hour.
- Q: When a task is dropped in the all-day area or on a day cell with no time slots, what is stored? → A: By default only a due date, shown in the all-day area. A user setting, off by default, instead assigns a random time of day on that date.
- Q: Which tasks does the left task view show by default? → A: Clickable filters at the top of the column choose the set (today, tomorrow, this week, all, without due date, overdue), and a search bar finds tasks by text. The default filter is today.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Plan my day in a task-and-calendar split view (Priority: P1)

When the user opens tefteri, the main planning screen shows two columns side by side: their tasks on the left and their calendar on the right. They see what needs doing and what their time looks like without switching screens.

**Why this priority**: The two-column screen is the base for the other stories and is what the user asked to be the default.

**Independent Test**: Open the app with connected apps and verify the first planning screen shows a task list on the left and a calendar on the right, both with the user's real data.

**Acceptance Scenarios**:

1. **Given** a signed-in user with connected apps, **When** they open the app, **Then** the default planning screen shows the task view on the left and the calendar on the right.
2. **Given** the split view is shown, **When** the user changes the work/life filter or presses sync, **Then** both columns update together.
3. **Given** the user prefers another view, **When** they open a different view (for example the plain daily view), **Then** it still works, and they can return to the split view from the navigation.

---

### User Story 2 - Find the right task with filters and search (Priority: P1)

At the top of the left column the user sees clickable filters and a search bar. The filters are: today's tasks, tomorrow's tasks, this week's tasks, all tasks, tasks without a due date, and overdue tasks. The user clicks a filter to narrow the list, or types in the search bar to find a task by name. The user can then drag any task found to the right date and time in the calendar.

**Why this priority**: A long task list is hard to plan from. Without quick filters and search, the drag-and-drop schedule is slow.

**Independent Test**: With tasks due on different days, click each filter and verify the list matches. Search for a task by part of its title and drag it onto a slot.

**Acceptance Scenarios**:

1. **Given** open tasks with different due dates, **When** the user clicks "Today", **Then** only open tasks due today are listed.
2. **Given** the task view, **When** the user clicks "Tomorrow", "This week", "All", "No due date" or "Overdue", **Then** the list shows exactly the matching open tasks, and the active filter is clearly marked.
3. **Given** the user types part of a task title in the search bar, **When** the list updates, **Then** matching tasks are shown, and the user can drag one onto a calendar slot.
4. **Given** a search with no matches, **When** the list updates, **Then** the user sees an empty-result message and a way to clear the search.
5. **Given** a task found by search, **When** the user drops it on a slot, **Then** it is scheduled as in User Story 3.

---

### User Story 3 - Drag a task onto the calendar to schedule it (Priority: P1)

The user drags a task from the left column and drops it on a time slot in the calendar. The task is scheduled at once for that time, with no extra dialog. The change is saved in their task manager.

**Why this priority**: It is the main reason for the new layout: turning a to-do list into a timed plan with one gesture.

**Independent Test**: Drag an undated task onto a time slot. Verify the task shows in that slot, and after sync its date and time in the task manager match the slot.

**Acceptance Scenarios**:

1. **Given** a task without a date, **When** the user drops it on a time slot, **Then** the task block starts at that slot, the task's due time is set to 1 hour after the slot time, and the block appears there.
2. **Given** a task that is already scheduled, **When** the user drags its block to another slot, **Then** the date and time move to the new slot.
3. **Given** a scheduled task block, **When** the user drags it back to the task column, **Then** the task loses its date and time and appears as unscheduled.
4. **Given** the task manager is unreachable, **When** the user drops a task, **Then** they see a clear error naming the connection, and the task is not shown as scheduled.
5. **Given** the user drops a task on a slot that already holds a calendar entry, **When** the drop completes, **Then** the overlap is visible.

---

### User Story 4 - See already-dated tasks in the right slot (Priority: P1)

Tasks that already have a date or date and time (set in tefteri or directly in the task manager) appear in the calendar at the matching time, next to the user's calendar entries.

**Why this priority**: The calendar is not trustworthy for planning unless it shows every dated task.

**Independent Test**: Give tasks a due date and time in the task manager, sync, and verify each task shows in the calendar at the expected slot.

**Acceptance Scenarios**:

1. **Given** a task with a due date and time, **When** the calendar shows that day, **Then** the task appears as a block that starts one hour before the due time and ends at the due time.
2. **Given** a task with a due date but no time, **When** the calendar shows that day, **Then** the task appears in the all-day area for that day.
3. **Given** a task and a calendar entry at the same time, **When** the calendar shows that day, **Then** both are visible and the user can tell them apart.
4. **Given** a task is completed, **When** the calendar shows its day, **Then** the block shows the completed state.

---

### User Story 5 - Use the layout on small screens (Priority: P3)

On a narrow screen, such as a phone, two columns do not fit. The user still reaches both the task view and the calendar and can still schedule tasks.

**Why this priority**: The Android client is in scope for tefteri, but planning on desktop is the main use.

**Independent Test**: Open the app in a narrow window and verify both the task view and calendar are reachable, and that a task can be scheduled.

**Acceptance Scenarios**:

1. **Given** a narrow screen, **When** the user opens the planning screen, **Then** they can switch between the task view and the calendar without losing their place.
2. **Given** a narrow screen, **When** the user wants to schedule a task, **Then** they can pick a date and time for it without drag and drop.

---

### Edge Cases

- A task has a due time in the first hour of the day, so the one-hour block would start on the previous day.
- A dropped task is in the past.
- Two tasks have the same or overlapping times.
- A task is dropped in the all-day area, or on a month-style day cell, where no time of day is chosen (see FR-017).
- The user drops a task and the save fails or conflicts with a change made in the task manager since the last sync.
- A task has a date but belongs to a list that the work/life filter hides.
- A recurring task has a due date.
- The search text matches nothing, or matches a task that is hidden by the work/life filter.
- A filter has no tasks, for example no overdue tasks.
- A task moves between filters after a drop (for example from "No due date" to "Today").
- The week changes at midnight, or the user's week starts on a different day.
- The task list is long, so the drag needs the list to scroll while the calendar stays visible.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The default planning screen MUST show two columns: a task view on the left and a calendar on the right.
- **FR-002**: The task view MUST list the user's open tasks according to the active filter and search (FR-018, FR-019), and MUST let the user tell scheduled tasks from unscheduled ones.
- **FR-003**: The work/life filter and the sync action MUST apply to both columns together.
- **FR-004**: Users MUST be able to drag a task from the task view onto a time slot in the calendar, and the task MUST be scheduled for that slot without further input.
- **FR-005**: Users MUST be able to drag a scheduled task to another slot to reschedule it, and drag it back to the task view to remove its date and time.
- **FR-006**: When the task manager is Vikunja, the task's due date and time MUST be the single stored date for scheduling, in line with the constitution. A drop, move or removal MUST change only the due date and time, and MUST be saved to the task manager.
- **FR-007**: A scheduled task MUST appear in the calendar as a block that starts one hour before the due time and ends at the due time. The start time is derived and MUST NOT be stored in the task manager as a separate date.
- **FR-008**: Dropping a task on a slot MUST place its block so that it starts at the slot the user chose, so the stored due time is one hour after that slot's time. The same rule applies when a scheduled block is moved to another slot.
- **FR-009**: Tasks that have a due date and time MUST appear in the calendar at the matching slot after load and after each sync, whether the date was set in tefteri or in the task manager.
- **FR-010**: Tasks that have a due date but no time MUST appear in the calendar's all-day area for that date.
- **FR-011**: Task blocks MUST be visibly different from calendar entries, and the calendar MUST show overlaps between them.
- **FR-012**: If saving a schedule change fails, the system MUST tell the user which connection failed and why, MUST NOT show the task as scheduled, and MUST leave the previous date and time unchanged.
- **FR-013**: If a task was changed in the task manager since the last sync, a drop MUST follow the existing conflict handling, and MUST NOT overwrite the other change without the user's decision.
- **FR-014**: On a narrow screen the layout MUST let the user switch between the task view and the calendar, and MUST offer a way to schedule a task without drag and drop.
- **FR-015**: Other views MUST remain available, and the user MUST be able to return to the split view from the navigation.
- **FR-016**: The new layout MUST be documented for users with screenshots, as the constitution requires.
- **FR-017**: Dropping a task in the all-day area, or on a day cell that has no time slots, MUST by default set only the due date, with no time, and the task MUST show in the all-day area. A per-user setting, off by default, MUST let the user choose instead that such a drop assigns a random time of day on that date. With the setting on, the random time MUST be the block start, MUST lie within 08:00 to 20:00 local time and snap to 15 minutes, and the due time is 1 hour later as in FR-008. The user MUST be able to move the block afterwards.
- **FR-018**: The top of the task view MUST show clickable filters: today's tasks, tomorrow's tasks, this week's tasks, all tasks, tasks without a due date, and overdue tasks. Exactly one filter MUST be active, and it MUST be clearly marked. "Today" MUST be the default filter. A filter matches open tasks by due date in the user's local time: today, tomorrow, the current calendar week, any date, no due date, and a due date and time before now. Each filter MUST show the number of tasks it matches.
- **FR-019**: The top of the task view MUST show a search bar. Searching MUST match tasks by title, MUST search all open tasks regardless of the active filter, and MUST update the list as the user types. Clearing the search MUST return to the active filter. Tasks found by search MUST be draggable to the calendar as in FR-004.

### Key Entities

- **Task**: A unit of work with a title, status and an optional due date and time. The due date and time is its scheduled time.
- **Task block**: The calendar display of a dated task. It spans one hour ending at the due time. It is a view of the task, not a stored item.
- **Calendar entry**: An event from a connected calendar, shown in the same calendar as task blocks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can schedule an unscheduled task at a chosen time with a single drag and drop, in under 5 seconds.
- **SC-002**: 100% of tasks with a due date and time in the connected task manager appear in the calendar at the correct slot after sync.
- **SC-003**: After a drag-and-drop schedule change and a sync, the task manager shows the same due date and time as the calendar in 100% of tested cases.
- **SC-004**: A first-time user opens the app and sees both their tasks and their calendar without any navigation.
- **SC-005**: A user on a narrow screen can schedule a task in 3 steps or fewer.
- **SC-006**: A user can find a specific task among at least 200 open tasks by search and start dragging it in under 10 seconds.

## Assumptions

- Vikunja is the task backend for this feature, and its due date is the canonical date (constitution Principle VII). Other backends define their own mapping later.
- The one-hour block length is fixed in this version. A user-set length is out of scope.
- Dropped times snap to 15-minute slots.
- The default filter is "Today" (FR-018). Tasks that are done are not listed. The filter and search apply on top of the work/life filter.
- The random-time setting is stored per user and is available in the app settings. The 08:00 to 20:00 window is fixed in this version.
- The first spec's separate "scheduled time" for tasks is replaced by the due date for Vikunja tasks.
- Calendar entries from Google Calendar remain as in the first spec. This feature does not create events in the calendar app.
- Drag and drop is the main method on desktop. On touch screens a time picker replaces it (FR-014).
- Past-time drops are allowed without a warning.
- Task views, filters, sync and conflict handling from the first spec (`001-daily-planning-framework`) are reused.
