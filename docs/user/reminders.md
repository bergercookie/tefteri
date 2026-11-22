# Get reminders on your phone

Tefteri sends you a notification on your Android phone before a task is due, before a calendar
event starts, and when a weekly, monthly or annual review is waiting. This page tells you what
you get, when you get it, and how to change it.

## What you get

- A task reminder, before a task is due. You get it for every task that has a due time. The
  task does not need a reminder in Vikunja.
- An event reminder, before a calendar event starts.
- A review reminder, when you did not do the weekly, monthly or annual review yet.

Tap a notification to open tefteri at the right place. A task or an event opens the planner on its
day. A review opens the review.

## Tasks and events

By default, you get a notification 15 minutes before the due time of a task, and 15 minutes before
an event starts. You can change each time:

1. Open the menu and choose Settings.
2. Choose Connections.
3. Find "Remind me of a task" and "Remind me of an event".
4. Choose a time. You can choose the time of the task or the event itself, or a time from 5
   minutes up to 2 days before.

The two times are separate. A change takes effect at once for the tasks and the events that
come next.

These rules apply:

- A task that you finished gets no notification.
- A task with a due day but no time gets no notification, because there is no time to remind you
  of. Give the task a time to get one.
- An all-day event gets no notification.
- An event that is in more than one of your calendars gives one notification, not one for each
  calendar.
- If you finish a task, move it or delete it after the notification was planned, tefteri does not
  show the notification.

## Reviews

You get a review notification only when the review is not done. If you did the review before the
time, you get nothing.

| Review | When you get the notification | The review is done when |
| ------ | ----------------------------- | ----------------------- |
| Weekly | Sunday at 12:00 | You looked back at the week, or you committed the plan for the next week |
| Monthly | The last day of the month at 12:00 | You saved the monthly review of the month |
| Annual | 26 December at 12:00, and 31 December at 15:00 | You wrote a note in the annual review of the year |

The times are in your time zone. The annual review gets two notifications. Both stop when you
write a note in the annual review.

## Allow notifications

The first time that you sign in, Android asks if tefteri may send notifications. Choose Allow.
If you chose Don't allow, open the settings of Android, choose Apps, choose tefteri, and then
allow notifications.

Android may delay a notification a little when you did not allow exact alarms. To allow them, open
the settings of Android, choose Apps, choose tefteri, and then allow alarms and reminders.

## How it works

Tefteri asks your server for the list of reminders when you open the app, when you change a time,
and about every 30 minutes. It does this also when the app is closed. Your phone keeps the
reminders for the next two days, and sets them again after a restart. Tefteri asks the server one
more time just before it shows a notification. This is why a finished task or a finished review
does not give a notification.

If your phone has no network when the time comes, it shows the notification it has.

Other systems, such as the browser and the Linux app, do not send notifications.
