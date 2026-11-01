# Connect your apps

Tefteri does not store your tasks, events or notes by itself. It shows the data from your own apps.
You connect each app one time. After that, you press Sync to get the newest data.

You can connect these apps:

- Vikunja for tasks.
- Google Calendar for events. You can connect more than one Google account.
- Trilium Next for notes.

## Before you start

1. Log in to tefteri.
2. Open the Settings screen.
3. Find the list of connections.

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

Tefteri tests the connection. If the test works, the connection shows the status OK.

## Connect a Google account

You use the Google sign-in page. Tefteri never sees your Google password.

1. In tefteri, open Settings and choose Add connection.
2. Choose Google Calendar.
3. Sign in to your Google account on the Google page.
4. Read the access request. Choose Allow.
5. Wait for tefteri to show the connection in the list.

To connect more than one Google account, do these steps again for each account.
Each account shows as its own connection.
Each connection shows the calendars of that account. For example, you can see personal, family and work calendars.

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

## Choose what each connection shows

Each connection has containers. A container is a Vikunja project, a Google calendar or a group of notes.
You can set each container to Life or Work. Then the Life and Work switch shows the right items.

## Use Sync

Tefteri does not sync in the background. You start each sync.

1. Press the Sync button at the top of the screen.
2. Wait until the button stops moving.
3. Read the result for each connection.

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

If you did not sync for a long time, the data on the screen can be old. Press Sync to get new data.

## Remove a connection

1. Open Settings.
2. Choose the connection.
3. Choose Remove.

Tefteri deletes the stored token. Your data stays in your app.
