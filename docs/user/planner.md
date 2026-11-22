# Plan with the planner

The planner is the first screen of tefteri. It shows your tasks on the left and your calendar on the right.
You can see what you must do and when you have time, on one screen.

![The planner. The task list is on the left, with filters and a search box. The week calendar is on the right, with events and task blocks.](../images/planner-split.png)

## What the two columns show

The left column is the task list. At the top you find the filters and the search box.
The right column is the calendar. It shows your calendar entries and your tasks together. By
default it shows one week. Refer to [Show a week, three days or one day](#show-a-week-three-days-or-one-day).

Task blocks have a colored outline and a check mark. Calendar entries have no outline. An entry
from a Google calendar has the color that you chose for that calendar in Google Calendar: a
strong line on its left edge and a softer color on the block. A task has the color of its
project in Vikunja in the same way. A finished task stays green.
A red dot and a red line show the current time in the column of the current day. The line moves while you work.
A task with a date and no time shows in the row called all day.

Rest the mouse pointer on a block, or on a task in the task list, to see its whole title and
when it is. For an event you also see its calendar, and for a task its project.

### An event that is in two calendars

You can see the calendar of another person in your Google account. When that person invites you
to one of their events, Google keeps a copy of the event in each calendar. The planner shows such
an event once. Its block has the colors of both calendars, in diagonal bands, and a small stack
icon. The line on its left edge has one part in the color of each calendar. Rest the pointer on
the block to read, for example, "Available in both calendars Work and Sam".

When you sync, both columns update.

## Choose what the planner shows

Choose the eye button at the top of the planner. A window shows these switches:

- **Tasks** and **Calendar**: hide one of the two columns. The other column uses the whole window.
- **Task providers**: hide the tasks of one connected task app. The other task apps stay visible.
- **Calendars**: hide the events of one calendar. The other calendars stay visible.

Next to **Task providers**, and next to the name of each calendar connection, a button **Hide
all** hides all of them at once. When they are hidden, the same button says **Show all**.

![The window What the planner shows. It has switches for the two columns, for the task app Home tasks, and for the calendars Work, Family and Holidays.](../images/planner-views.png)

A hidden source keeps syncing. Tefteri only leaves it out of the planner, so you can show it again at once.
Choose **Show all sources** to show every task provider and calendar again.
Tefteri keeps the choice on this device.

The eye button is also in the header when one pane is hidden. The planner always keeps at least one
column visible. To hide the tasks, show the calendar first, or the other way around.

Hiding a calendar in this window is not the same as switching off its sync. To stop syncing a
calendar, open Settings, choose Connections, and choose Choose calendars. Read
[Connect your apps](connect-apps.md).

## Change the width of the sidebar and the task list

You can make the sidebar and the task list wider or narrower.

1. Point at the line between the sidebar and the page, or at the line between the task list and the
   calendar. The pointer changes and the line gets thicker.
2. Drag the line to the left or to the right.

To use the keyboard, choose the line with the Tab key or with a click. Then press the left arrow
key or the right arrow key. Each press moves the line by 16 pixels.

To go back to the standard width, double-click the line, or choose it and press Home.

Tefteri keeps the widths and uses them the next time you open it. The sidebar is 200 to 360 pixels
wide. The task list is 260 to 640 pixels wide, and it always leaves room for the calendar. The
sidebar has a line to drag only when the window is wide enough to show the names of the views.

## Move to today

Choose Today at the top of the calendar to go to today. The calendar scrolls to the current time.
To move by one week, choose the arrows next to the Today button. You can also press the Left arrow key and the Right arrow key.
In the 3 days view, the arrows move by three days. In the Day view, they move by one day.
The arrow keys do not work while you type in the search box.
Every screen with a calendar or a period has a Today button: the planner, Today, Week, Month and Year.
The Month view is for the monthly theme focus and review. Read [Plan your month](monthly-planning.md).

## Show a week, three days or one day

The menu at the right of the calendar header sets how many days the calendar shows:

- Week: Monday to Sunday. This is the default.
- 3 days: three days. The first day is today, or the day that you move to with the arrows.
- Day: one day.

On a narrow screen, the menu shows an icon instead of the name. Tefteri keeps your choice on this
device and uses it the next time you open the planner.

When you change the view and today is on the screen, the new view also shows today. If today is
not on the screen, the new view starts on the first day that you saw.

## Mark a task as done with Ctrl and a click

Hold Ctrl and click a task with the left mouse button. Tefteri marks the task as done in your task
app. This works for a task block on the calendar, for a task in the all day row and for a task in
the task list.

A click that holds Ctrl does not open the task. A click without Ctrl opens the task, as before.

A task that is done stays done: the same click does nothing on it. To reopen a task, open it and
choose Mark not done. An event has nothing to complete.

## See the project of a task

A task on the calendar has a small dark label with the name of its project. This shows you
where each task belongs without opening it. In a short block, the label sits next to the title.
A long name is cut. Point at the label to read the whole name. Events have no label.

## Create a task

1. Press N, or choose New task above the task list.
2. Type the title.
3. Choose the project. Type a few letters, and tefteri shows the projects that match. Use the
   arrow keys and Enter, or choose a project with the pointer. Tefteri remembers the project
   for the next task.
4. Add labels. Type a few letters, and tefteri shows the labels that exist. Press Enter to add
   the label. If the label does not exist, tefteri creates it in your task app.
5. Optional: choose a day and a start time. Tefteri puts the task on the calendar.
6. Choose Create task, or press Ctrl+Enter.

Tefteri creates the task in your task app. The task shows in the list at once.

## See and change a task

Choose a task in the list, or a task block on the calendar. A pop-up shows the task. You can
change these fields:

- The title.
- The description.
- The day. To remove the day, choose the cross in the field.
- The start time. Without a start time, the task is all day. With a start time, the task is a
  block of one hour. The due date in your task app is the end of that hour.

A description that has rich text, such as a link, a list or bold words, shows formatted. Vikunja
keeps this kind of description as HTML. Tefteri does not show the tags. A link opens in your web
browser. To change the text, choose Edit the text. The field then shows the text with its tags,
and the formatted view stays below it. Choose Show it formatted to go back. A description without
tags is a plain field from the start.

The pop-up also shows the status, the time on the calendar and the project.

1. Change the fields.
2. Choose Save.

Tefteri writes the changes to your task app. Tefteri closes the pop-up when the task app accepts
them. If the task app does not accept a change, the pop-up stays open and shows the reason. Your
changes stay in the fields, so you can try again.

Save is off until you change something. If you choose Cancel after a change, tefteri asks if you
want to discard the change.

### Add a reminder

When a task has a day and a start time, the pop-up has a button, for example Remind me 15 minutes
before. Choose it to add a reminder to the task in Vikunja. Vikunja then tells you at that time,
the way you set it up there.

- The reminder is relative to the due date. If you move the task to another time, the reminder
  moves with it.
- The pop-up then shows the reminder and a Remove button. Choose Remove to delete the reminder.
- The button is off when the task has no start time, because an all day task has no time to count
  back from. It is also off while you have a change in the day or the time that is not saved. Save
  the change first.
- The button is not there when the app that holds the task has no reminders. Today, only Vikunja
  has them.

Tefteri adds or removes the reminder at once. You do not need to choose Save. Other reminders that
you made in Vikunja stay as they are.

To change the default time, open the menu, choose Settings, and then choose Connections. Use
"Remind me of a task". It offers at the time, from 5 minutes up to 2 days before. A change
applies to the reminders that you add after it. The reminders that exist stay as they are. The
same time sets when the app sends a notification for a task. Read [Reminders](reminders.md).

![The pop-up of the task Update the road map. It shows the title, the day, the start time and the description as fields that you can change, and the Save button.](../images/planner-task-details.png)

If you choose a calendar entry, the pop-up shows the time of the entry.

## Find text on the page

Press Ctrl+F (Cmd+F on a Mac). A find bar opens at the top right of the screen. It works in every
view, in the web client and in the Android and Linux apps.

1. Type the text. Tefteri marks every match on the screen, for example in the task list, on the
   calendar and in the menu. The bar shows which match you are at, for example `2 of 7`.
2. Press Enter to go to the next match. Press Shift+Enter to go to the match before. Tefteri
   scrolls the match into view.
3. Press Esc, or choose the cross, to close the bar.

The search does not care about upper and lower case. Tefteri searches the text that the screen
shows, also the text that you typed in a field. A field for a password is not searched.
Page Down and Page Up scroll the page while the find bar is open. A long list shows only part of its items, so the bar finds the items that you can reach by
scrolling when you scroll to them.

Tefteri takes the Ctrl+F key from the browser. The browser cannot mark text in the web client,
because the client draws its text itself.

## Find a task

Use the filters at the top of the task list. Each filter shows how many open tasks it holds.

| Filter | Tasks it shows |
| --- | --- |
| Today | Open tasks that are due today |
| Tomorrow | Open tasks that are due tomorrow |
| This week | Open tasks that are due from Monday to Sunday of this week |
| All | All open tasks |
| No due date | Open tasks that have no due date |
| Overdue | Open tasks whose due date is in the past |

When you open the planner, the filter Today is on. To use another filter, choose it.

![The task list with the filter Overdue. It shows one task that is late.](../images/planner-filter-overdue.png)

To find a task by name, type part of the name in the search box. Tefteri searches all open tasks.
It does not use the filter while you search. To go back to the filter, choose the X in the search box.

![The search box with the word road. The list shows one task: Update the road map.](../images/planner-search.png)

If no task matches, tefteri tells you. Choose Clear search to see the list again.

## Put a task on the calendar

When you point at a task with the mouse, the task lifts, gets an outline and shows a grip on the left. The cursor becomes a hand. This shows that you can drag the task.

1. Find the task in the list.
2. Drag the task to a time on the calendar.
3. Drop the task.

Tefteri saves the time at once. The task shows as a block on the calendar.

While you drag, the calendar turns grey. Only the place where the task will go stays clear. It
shows the start time and the end time of the block. The block moves from slot to slot when you
move the pointer. If you drag near the top or the bottom of the calendar, the calendar scrolls.
To plan only the day, drag the task to the all day row. The row then says All day.

![A task is dragged over the calendar. The calendar is grey. The block from 13:30 to 14:30 on Thursday is clear and shows where the task will go.](../images/planner-drag.png)

The block starts at the time slot where you drop the task. Time slots are 15 minutes long.
A block is one hour long. Your task app gets the due date and time of the task. The due time is one hour after the start of the block.

For example, you drop a task at 14:30. The block is from 14:30 to 15:30. The due time of the task is 15:30.

Tefteri changes only the due date of the task. It does not make an event in your calendar app.

## Put a task on a day with no time

1. Drag the task to the row called all day at the top of the calendar.
2. Drop the task on the day that you want.

The task gets a due date and no time. It shows in the all day row.

You can change what happens in this case. Open the menu, choose Settings, and then choose Connections. Use the switch
"Give a random time to date-only drops". When the switch is on, the task gets a random time on that day.
The time is from 08:00 to 19:45. You can move the block later.

![The Connections screen. The switch Give a random time to date-only drops is on. Below it, the reminder for a task and the reminder for an event are each 15 minutes before.](../images/planner-setting-random-time.png)

## Move an event to another time

Drag an event block to another time or to another day. The event keeps its length. While you
drag, the calendar shows where the event would land, with its start and end time in the color of
its calendar. Tefteri writes the new time to your calendar app, for example Google Calendar.

You can move an event only when you can change its calendar:

- An event of a calendar that is read-only does not move. This is a calendar that someone shared
  with you for reading. Tefteri still shows the event.
- An all-day event does not move.

If the calendar app does not accept the change, tefteri shows the reason and the event stays
where it was.

## Make an event longer or shorter

Put the pointer on the top edge or the bottom edge of an event block. The pointer changes to a
double arrow. Drag the edge up or down:

- The bottom edge changes when the event ends.
- The top edge changes when the event starts.

The edge moves in steps of a quarter of an hour. A small label shows the new start and end while
you drag. When you let go, tefteri writes the new times to your calendar app. A short drag of a
few pixels does nothing. An event is never shorter than a quarter of an hour, and its end stays
on the same day.

You can drag the edges of an event only when you can move it: it has a time, it is not all day,
it is in a calendar that you can change, and it starts and ends on the same day.

## Change an event

Choose an event block. A pop-up opens with the details of the event as fields that you can change:

- The title.
- The day, the start time and the length. You type them as plain text, in the same way as for a
  new event: `20261104` for a day, `1105` for a time, and `45m` or `1h30` for a length. Times
  always use 24 hours. A line under the fields shows when the event ends.
- The place.
- The description. A description with rich text, such as a link or a list, shows formatted.
  Choose Edit the text to change its text.

Press Tab to go from one field to the next. Choose Save, or press Ctrl+Enter. Tefteri writes the
change to your calendar app, for example Google Calendar. Choose Cancel to close the pop-up without
a change.

![The pop-up of the event Team standup. It has the fields Title, Day, Starts at, Length, Place and Description, a line that shows when the event ends, and the buttons Cancel and Save.](../images/planner-event-edit.png)

- The pop-up of an event in a calendar that is read-only shows the details and cannot be saved. It
  says so.
- An all-day event has no time fields. You can change its title, its place and its description.
- An event that is in more than one calendar changes in the first calendar only. The pop-up says
  which one.
- If the calendar app does not accept the change, tefteri shows the reason and keeps the pop-up
  open, so that you do not lose what you typed.

![The menu of a right click on an empty slot. It offers a new event and a new task at 12:15.](../images/planner-slot-menu.png)

## Add an event or a task on an empty slot

You can add an event in three ways:

- Choose the button New event in the row above the calendar. On a narrow screen, the button is a
  small icon.
- Press Shift+N on any page.
- Click an empty slot of the calendar with the right mouse button. A menu opens, with the time
  of the slot (a quarter of an hour).

In the menu of a right click:

- Choose New event to add an event to one of your calendars.
- Choose New task to add a task to one of your projects. The task starts with that day and time.

Click the row all day with the right button to add an all-day event or a task for that day.

![The pop-up New event. It shows the title, the calendar with its color, the day, the times, the switch All day, the place and the people to invite.](../images/planner-new-event.png)

In the pop-up New event:

1. Type the title.
2. Choose the calendar. The list shows only the calendars that are on and that you can change.
   Tefteri starts with the calendar that you chose in the settings. Without a choice, it starts
   with the calendar of your last new event.
3. Change the day, the start time and the length if you need to. To add an event for the whole
   day, turn on All day.
4. Optional: type a place.
5. Optional: tick the people to invite.
6. Choose Add event, or press Ctrl+Enter.

### Use only the keyboard

Press Tab to go to the next field. Press Shift+Tab to go back. The order is: title, calendar,
day, All day, start time, length, place, the people, and then the buttons. The small buttons for
the pickers are only for the mouse, so Tab skips them.

You type the day and the time as plain text:

| Field | You type | Result |
| --- | --- | --- |
| Day | 20261102 | 2 November 2026 |
| Starts at | 1105 | 11:05 |
| Day or Starts at | 20261102T1105 | Sets the day and the time |
| Length | 45m, 1h or 1h30 | The length of the event |

Times always use 24 hours, for example 14:30. Tefteri never shows AM or PM, also not in the
time picker. When you leave a field, tefteri writes the value in the standard form.

### Invite people

Below the place, the list Invite shows the people that you usually invite. Tick a person with the
mouse, or press Tab to go to the person and press Space. Nobody is ticked at first. When you add
the event, the calendar app sends an invitation to each ticked person.

To change the list, open Settings and look for People you invite to events. Type an e-mail
address and press Enter to add a person. Choose the cross on a person to remove them.

### Choose the calendar for new events

Open Settings. In the card with the planner settings, choose a calendar in Calendar for new
events. The pop-up New event then starts with this calendar. Choose Last used to start with the
calendar of your last new event again.

If you have no calendar that you can change, the pop-up tells you to connect a Google calendar
and to choose a calendar in Settings. Read [Connect your apps](connect-apps.md).

A right click on a task block or on an event block does nothing. In a web browser, the right
click opens the menu of tefteri, not the menu of the browser, while the pointer is over the
calendar.

## Move a task or take it off the calendar

- To move a task, drag its block to a new time. Tefteri saves the new due date.
- To take a task off the calendar, drag its block to the task list. The task loses its due date and time.

## See tasks that already have a date

Tasks that have a due date show on the calendar, also when you set the date in your task app.
Press sync to get the latest dates.

- A task with a date and a time shows as a block. The block ends at the due time and is one hour long.
- A task with a date and no time shows in the all day row.
- A task that you completed has a line through its name.

If a due time is in the first hour of the day, the block starts at 00:00. A small arrow on the block shows this.

If a task and a calendar entry are at the same time, tefteri shows them side by side.

A task that is due at exactly 00:00 in your time zone shows as a task with a date and no time. Vikunja has no separate field for this case.

## If a change does not save

If your task app is not available, tefteri shows a message at the top. The message gives the name of the app and the reason.
The task does not show as scheduled. Nothing changes in your task app.

![A red message at the top of the planner. It says that Home tasks cannot be reached and that nothing was changed.](../images/planner-save-failed.png)

Fix the problem, then drag the task again.

If you changed the task in your task app after the last sync, tefteri shows a conflict.
Open the Conflicts screen and choose the version that you want to keep. See [Solve a sync conflict](conflicts.md).

## Use the planner on a phone

On a narrow screen, the two columns do not fit. The planner shows two tabs: Tasks and Calendar.
Your filter, your search text and your days stay the same when you change tabs.

![The planner on a narrow screen. The Tasks tab shows the filters, the search box and three tasks, each with a Schedule button.](../images/planner-narrow-tasks.png)

You do not drag tasks on a phone. To schedule a task:

1. Choose Schedule next to the task.
2. Choose the day and the start time.
3. Choose Schedule.

![The Choose a time dialog. It has a day and a start time.](../images/planner-narrow-schedule.png)

The time that you choose is the start of the block. The due time is one hour later.
