# Get started

This guide shows how to install the tefteri client and sign in the first time. Your
administrator gives you the server address, a username and a first password.

## Install the client

Tefteri has a client for the Linux desktop, for Android and for the web browser. Get the
packages from the releases page of the project on GitHub.

On Debian or Ubuntu:

1. Download the file `tefteri_<version>_amd64.deb`.
2. Install it: `sudo apt install ./tefteri_<version>_amd64.deb`.
3. Start Tefteri from the application menu.

On other Linux systems:

1. Download the file `tefteri-<version>-x86_64.AppImage`.
2. Make it executable: `chmod +x tefteri-<version>-x86_64.AppImage`.
3. Start the file.

On Android:

1. Download the file `tefteri-<version>.apk` on your phone.
2. Open the file. Let your phone install apps from this source if it asks.
3. Start Tefteri.

To keep the Android app in step with the server, use [Obtainium](https://obtainium.imranr.dev/):

1. Open Settings in the web client or the Linux client, and find the card Android app.
2. Scan the QR code with your phone, or open the link on your phone. Obtainium adds Tefteri and
   installs the release of the version that the server runs.
3. After the server is updated, use the new link or code from the same card. The link is for one
   version, so the app never gets ahead of the server.

The card has no link when the server is not a published release (for example a development build).

In a web browser, open the address that your administrator gives you.

Every change that reaches the main branch becomes a new release, with a new version number. The
newest release has the newest packages. In Settings, choose Check for updates to see if a newer
version exists.

## Sign in for the first time

1. Start tefteri.
2. Type your username and the first password from your administrator.
3. Choose Sign in.
4. Open the menu and choose Settings. Then choose Change password. Set a password that only you know.

![The sign-in screen with the fields Username and Password and the Sign in button.](../images/accounts-login.png)

Refer to [Accounts and sign-in](accounts-and-sign-in.md) for more about passwords and sessions.

## Connect your apps

Tefteri does not keep your tasks, events and notes itself. It shows the items from your own
apps. Connect them next. Refer to [Connect your apps](connect-apps.md).

## Use a company Google account

A company Google account (Google Workspace) can block apps that the company did not approve.
In this case, Google shows a message that it blocks the app when you connect the calendar.

1. Ask the Google Workspace administrator of your company to approve the tefteri OAuth client.
   Give the administrator the client ID from the administrator of your tefteri server.
2. Tell the Google Workspace administrator that tefteri asks for one scope:
   `https://www.googleapis.com/auth/calendar` (read and change your calendars).
3. After the approval, connect the calendar again. Refer to
   [Connect a Google account](connect-apps.md).

You can connect a personal Google account and a company Google account at the same time. Each
account is a separate connection.

## Copy text

You can select the text on every screen with the mouse. Then press Ctrl+C to copy it. This is useful for error messages.
The tasks in the task list are different. You drag them, so you cannot select their text. Choose a task to open its details. You can select the text there.

## Learn the main screens

- [Plan with the planner](planner.md)
- [Plan your day](daily-planning.md)
- [Put tasks on the calendar](scheduling.md)
- [Plan for the year](annual-planning.md)
- [Keep a planning checklist](planning-checklists.md)
- [Plan your month](monthly-planning.md)
- [Use the keyboard](shortcuts.md)
