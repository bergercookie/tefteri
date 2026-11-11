# Connect your apps

Tefteri does not store your tasks, events or notes by itself. It shows the data from your own apps.
You connect each app one time. After that, you press Sync to get the newest data.

You can connect these apps:

- Vikunja for tasks.
- Google Calendar for events. You can connect more than one Google account.
- Trilium Next for notes.

## Before you start

1. Log in to tefteri.
2. Open the menu and choose Settings.
3. Choose Connections. You see the list of connections.

![The Connections screen with three connections: Home tasks, Work calendar and Notes. Each shows its app and the time of the last sync.](../images/connections-list.png)

## Connect Vikunja

You need the web address of your Vikunja server and an API token.

1. Open Vikunja in your web browser.
2. Open the Vikunja settings and find the API tokens.
3. Create a new token. Copy the token.
4. In tefteri, open Settings and choose Add connection.
5. Choose Vikunja.
6. Type the base URL of your Vikunja server. Type it in full, with https at the start.
7. Paste the API token.
8. Choose Save.

Tefteri syncs the new connection at once. If the sync works, the connection shows the status OK. If
the first sync fails, tefteri still keeps the connection and shows the reason in a message. Fix the
address or the token, then press Sync next to the connection to try again.

### The color of a project

Tefteri reads the color of each project in Vikunja. It uses this color for the tasks of the
project in the planner, in the task list, in the Week and Month views and in the weekly planning.
When you change the color of a project in Vikunja, tefteri shows the new color after the next sync.
A project with no color gets a color from the palette of tefteri. The same project always gets
the same color.

## Connect a Google account

You use the Google sign-in page. Tefteri never sees your Google password.

1. In tefteri, open Settings and choose Add connection.
2. Choose Google Calendar. Then choose Continue.
3. Choose Open Google sign-in. Sign in to your Google account on the Google page.
4. Read the access request. Choose Allow.
5. Wait for tefteri to show the connection in the list.

To connect more than one Google account, do these steps again for each account.
Each account shows as its own connection.
Each connection shows the calendars of that account. For example, you can see personal, family and work calendars.

### The color of a calendar

Tefteri reads the color that you chose for each calendar in Google Calendar. It uses this color for
the events of that calendar in the planner and in the Today view.
When you change the color of a calendar in Google Calendar, tefteri shows the new color after the
next sync. A calendar with no color keeps the standard color of tefteri.

## Choose the calendars

Tefteri syncs only the calendars that you switch on. The first sync of a new Google connection uses
the calendars that you show in Google Calendar. After you sign in, tefteri opens the list of
calendars so that you can check the choice.

You can change the choice at any time:

1. Open Settings and choose Connections.
2. Find the Google connection. Choose Choose calendars.
3. Select the calendars that you want. Choose Save.

The list also shows the calendars that you hide in Google Calendar, and shared calendars, for
example Family. Tefteri leaves them off until you switch them on. A calendar with the label
Read only shows its events, but tefteri cannot change them.

## Connect Trilium Next

You need the web address of your Trilium Next server and an ETAPI token.

1. Open Trilium Next in your web browser.
2. Open the Options and choose ETAPI.
3. Create a new ETAPI token. Copy the token.
4. In tefteri, open Settings and choose Add connection.
5. Choose Trilium Next.
6. Type the base URL of your Trilium Next server.
7. Paste the ETAPI token.
8. Choose Save.

Tefteri tests each connection when you save it. If the connection does not work, a message
tells you why. For example, it names the address that answered and what it answered. Fix the
address or the token, and choose Save again.

The base URL is the address that you use to open Trilium Next, for example
`https://notes.example.com`. If you copy the address of a page, tefteri ignores the part after
`#`, and it ignores `/etapi` at the end.

Tefteri does not copy your notes. A sync only checks that the address and the token still work.
Tefteri reads and writes a note only when it needs it. These are the daily note of a day, and the
retrospective that you save from a review. Tefteri does not read your other notes, and it does not
store them. If you used an older version, tefteri removes the copies that it made of your notes.

## Use Sync

Tefteri syncs all your connections by itself every hour. It also syncs a new connection once when
you add it. The server does this, so it works when no window of tefteri is open. The administrator
can change the time between two syncs, or turn the automatic sync off. Read
[Deploy tefteri](../developer/deployment.md).

A connection that needs attention is left out of the automatic sync, because the app rejects its
token and each try would fail again. Fix the token in Settings. Then the automatic sync includes
the connection again.

You can also sync at any time:

1. Press the Sync button at the top of the screen.
2. Wait until the button stops moving.
3. Read the result for each connection.

![The Connections screen after a sync. A message at the bottom says: Sync finished.](../images/connections-sync-result.png)

To sync one connection only, open Settings and choose Sync next to that connection.

If one app fails, tefteri still syncs the other apps. The failed app shows a message.
Read [Troubleshooting](troubleshooting.md) to find out what to do.

## Read the last-sync status

Each connection shows the time and the result of its last sync.

| Status | Meaning |
| ------ | ------- |
| OK | The last sync worked. |
| Needs attention | The app refused your credentials. Reconnect the app. |
| Error | Tefteri could not reach the app. Retry later. |

The data on the screen is as new as the last sync, and the automatic sync runs every hour. Press Sync to get new data at once, for example after you change something in your app.

## Change a connection

1. Open Settings.
2. Choose the edit button (the pencil) next to the connection.
3. Change the name, the base URL or the token.
   To keep the stored token, leave the token field empty.
4. Choose Save. Then press Sync.

## Remove a connection

1. Open Settings.
2. Choose the remove button (the bin) next to the connection.
3. Choose Remove to confirm.

Tefteri deletes the stored token. Your data stays in your app.
