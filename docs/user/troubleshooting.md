# Troubleshooting

This page tells you what to do when an app does not answer or refuses your credentials.

## Rules that tefteri follows

- Tefteri always tells you which connection failed and why.
- Tefteri never hides a failed change.
- Tefteri never keeps a failed change in a queue to send later.
- A failure in one app does not stop the other apps.

If a change fails, the app did not get the change. Make the change again after you fix the problem.

## An app is unreachable

The message says that tefteri cannot reach the app. The connection shows the status Error.

Common causes:

- Your computer or phone has no network.
- The server of the app is off.
- The base URL in the connection is wrong.
- A firewall or a VPN blocks the server.

To fix the problem:

1. Read the name of the connection in the message.
2. Make sure that you have a network connection.
3. Open the app in your web browser. Check that it loads.
4. Choose Retry in tefteri.
5. If Retry fails again, choose Open settings.
6. Check the base URL. Correct it if it is wrong.
7. Choose Save. Then press Sync.

## Credentials expired or revoked

The message says that the app refused your credentials. The connection shows the status Needs attention.

Common causes:

- You deleted the API token or the ETAPI token in the app.
- The token reached its end date.
- You removed the access of tefteri in your Google account.
- Google stopped the access because you changed your Google password.

To fix the problem:

1. Choose Reconnect in the message.
2. For Vikunja or Trilium Next, create a new token in the app. Paste it into tefteri.
3. For Google Calendar, sign in again on the Google page and choose Allow.
4. Press Sync.

## What each message means

| Message | Meaning | What to do |
| ------- | ------- | ---------- |
| Cannot reach the app | The app did not answer. | Choose Retry. |
| Credentials expired or revoked | The app refused your token or sign-in. | Choose Reconnect. |
| The item changed in the app | Someone changed the item after your last sync. | Press Sync. Make your change again. |
| Not supported by this app | The app has no support for this action. | Use a different action. Nothing is lost. |

## What the buttons do

- **Retry** sends the same request again. Use it after you fix the network or after the server starts.
- **Reconnect** starts the connection steps again. Use it when the token is not valid.
- **Open settings** shows the connection. Use it to correct the base URL or to remove the connection.

## If the problem stays

1. Remove the connection.
2. Add the connection again. Follow [Connect your apps](connect-apps.md).
3. Ask the person who runs your tefteri server to read the server log.
