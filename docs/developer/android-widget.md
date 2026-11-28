# The Android home screen widget

The widget is native Android code in `frontend/android/app/src/main`. It has four buttons that
open a view of the app. Flutter does not draw it, because a widget runs outside the app.

## Parts

- `NavWidgetProvider.kt` is the `AppWidgetProvider`. It gives each button a `PendingIntent` that
  starts `MainActivity` with a link such as `tefteri://app/week`.
- `res/layout/tefteri_widget.xml` is the layout: four equal buttons with an icon and a label.
  It uses only views that a `RemoteViews` can show.
- `res/xml/tefteri_widget_info.xml` sets the size: 4 cells wide and 1 cell high
  (`targetCellWidth`, `targetCellHeight`, and a minimum of 250 dp by 40 dp for older launchers).
- `AndroidManifest.xml` declares the receiver and a `VIEW` filter for `tefteri://app`.
- The colors are those of `lib/theme/palette.dart`, with a dark version in `values-night`.

## How a button opens a view

Flutter gives the path of the link to the router. When the app starts from the link, the path
is the initial route. When the app is open, `MainActivity.onNewIntent` sends it as route
information. The intent flags `NEW_TASK`, `CLEAR_TOP` and `SINGLE_TOP` keep one instance of the
app. `go_router` then opens the view. No Dart code is special for the widget.

| Button | Link path | View |
| --- | --- | --- |
| Today | `/daily` | the plan of the day |
| Week | `/week` | the week |
| Month | `/month` | the month |
| Planner | `/` | the planner |

The Month button opens the monthly theme plan and review. The route stays `/month`.

The paths are the ones of `lib/core/shortcuts/keymap.dart`. To change a button, change the
`buttons` list in `NavWidgetProvider.kt`, and the layout, the icon and the strings.

## The agenda widget: links, cache and retry

A tap on a row of the agenda opens a link on the planner route with the day and the item:
`tefteri://app/?date=2026-11-22&task=<id>` or `&event=<id>` (`rowLink` in
`AgendaWidgetService.kt`). The plus button opens `...&add=menu`. The planner (`PlannerScreen`)
reads `task`, `event` and `add`, opens the details pop-up or the Add menu, and then takes those
parts out of the address. Without that step, a second tap on the same row would be the same
address and would not open anything. The links of the reminder notifications use the same
parameters.

`AgendaData.fetch` asks the server up to `ATTEMPTS` times with `retryDelayMillis` between the
asks. An answer that can be read is kept in the `tefteri_agenda_cache` preferences, by day, for
14 days. When every ask fails, `fetch` returns the kept answer with `staleSince` set, and the
factory then shows the line `agenda_status` through `AgendaWidgetProvider.showStatus`. Only a day
with no kept answer shows `agenda_failed`. A 401 answer, or no login, clears the cache.

## Tests

`frontend/test/core/home_screen_widget_test.dart` starts the app from each link and sends each
link to the open app. It also checks that the Kotlin file, the layout, the size and the manifest
agree with the routes of the app.

The widget itself is not tested in CI. No build job runs it on a device or an emulator. To try
it, build the APK, install it, and add the widget as the user guide says.
