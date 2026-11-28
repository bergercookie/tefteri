package dev.bergercookie.tefteri

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Locale

/**
 * The agenda widget: the events and the tasks of one day, with arrows to the day before and the
 * day after. It shows today until the arrows are used, and goes back to today on the next day.
 */
class AgendaWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        Log.i(TAG, "update of ${ids.toList()}")
        for (id in ids) refresh(context, id)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = prefs(context).edit()
        for (id in ids) edit.remove(shownKey(id)).remove(setOnKey(id)).remove(scrolledKey(id)).remove(staleKey(id))
        edit.commit()
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = widgetIdOf(intent)
        Log.i(TAG, "received ${intent.action} for widget $id")
        when (intent.action) {
            ACTION_PREVIOUS -> move(context, id, -1)
            ACTION_NEXT -> move(context, id, 1)
            ACTION_TODAY -> move(context, id, 0)
            ACTION_REFRESH -> refresh(context, id)
            else -> super.onReceive(context, intent)
        }
    }

    private fun move(context: Context, id: Int, step: Int) {
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val day = if (step == 0) Calendar.getInstance() else shownDay(context, id).apply { add(Calendar.DAY_OF_YEAR, step) }
        show(context, id, day)
        Log.i(TAG, "widget $id shows ${AgendaData.dayKey(day)}")
        refresh(context, id)
    }

    private fun refresh(context: Context, id: Int) {
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val manager = AppWidgetManager.getInstance(context)
        draw(context, manager, id)
        manager.notifyAppWidgetViewDataChanged(id, R.id.agenda_list)
    }

    private fun draw(context: Context, manager: AppWidgetManager, id: Int) {
        val views = RemoteViews(context.packageName, R.layout.tefteri_agenda_widget)
        val day = shownDay(context, id)
        views.setTextViewText(R.id.agenda_date, dateLabel(context, currentOffset(context, id), day))
        views.setOnClickPendingIntent(R.id.agenda_previous, action(context, id, ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.agenda_next, action(context, id, ACTION_NEXT))
        // The date goes back to today; today is also the refresh.
        views.setOnClickPendingIntent(R.id.agenda_date, action(context, id, ACTION_TODAY))
        views.setOnClickPendingIntent(R.id.agenda_refresh, action(context, id, ACTION_REFRESH))
        // The plus opens the app on the menu with a note, a task and an event, for the shown day.
        views.setOnClickPendingIntent(
            R.id.agenda_add,
            PendingIntent.getActivity(
                context,
                id,
                openApp(context, Uri.parse("tefteri://app/?date=${AgendaData.dayKey(day)}&add=menu")),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            ),
        )
        applyStatus(context, views, id)

        val service = Intent(context, AgendaWidgetService::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        // The data URI makes the intent of each widget unique.
        service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
        views.setRemoteAdapter(R.id.agenda_list, service)

        // A tap on a row opens the planner at that day in the app. The row adds the link, because
        // only the row knows the day (see AgendaWidgetService).
        val open = openApp(context, null)
        views.setPendingIntentTemplate(
            R.id.agenda_list,
            PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE),
        )
        manager.updateAppWidget(id, views)
    }

    /** An intent that opens the app, at [link] when it is given. */
    private fun openApp(context: Context, link: Uri?): Intent =
        Intent(Intent.ACTION_VIEW)
            .setClass(context, MainActivity::class.java)
            .apply { if (link != null) data = link }
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)

    private fun action(context: Context, id: Int, action: String): PendingIntent {
        // The widget and the button are in the address of the intent, so every button of every
        // widget has an intent of its own. Nothing depends on the extras being kept up to date.
        val intent = Intent(context, AgendaWidgetProvider::class.java)
            .setAction(action)
            .setData(Uri.parse("tefteri-agenda://widget/$id/${action.substringAfterLast('.').lowercase()}"))
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        return PendingIntent.getBroadcast(
            context,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val ACTION_PREVIOUS = "dev.bergercookie.tefteri.agenda.PREVIOUS"
        const val ACTION_NEXT = "dev.bergercookie.tefteri.agenda.NEXT"
        const val ACTION_TODAY = "dev.bergercookie.tefteri.agenda.TODAY"
        const val ACTION_REFRESH = "dev.bergercookie.tefteri.agenda.REFRESH"
        private const val PREFS = "tefteri_agenda_widget"

        private const val TAG = "TefteriAgenda"

        private fun staleKey(id: Int) = "stale_$id"

        /**
         * Shows or hides the line that says the list is an old one. [staleSince] is the time of the
         * answer that the rows come from, or null when the rows are fresh. It is also kept, so
         * that a redraw of the widget keeps the line until a new answer comes.
         */
        fun showStatus(context: Context, id: Int, staleSince: Long?) {
            if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
            prefs(context).edit().putLong(staleKey(id), staleSince ?: 0L).commit()
            val views = RemoteViews(context.packageName, R.layout.tefteri_agenda_widget)
            applyStatus(context, views, id)
            AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(id, views)
        }

        private fun applyStatus(context: Context, views: RemoteViews, id: Int) {
            val since = prefs(context).getLong(staleKey(id), 0L)
            if (since <= 0L) {
                views.setViewVisibility(R.id.agenda_status, android.view.View.GONE)
                return
            }
            views.setViewVisibility(R.id.agenda_status, android.view.View.VISIBLE)
            views.setTextViewText(R.id.agenda_status, context.getString(R.string.agenda_stale, staleLabel(since)))
        }

        /** "14:05" for a time of today, and "21 Nov 14:05" for an earlier day. */
        fun staleLabel(since: Long, now: Long = System.currentTimeMillis()): String {
            val then = Calendar.getInstance().apply { timeInMillis = since }
            val today = Calendar.getInstance().apply { timeInMillis = now }
            val sameDay = AgendaData.dayKey(then) == AgendaData.dayKey(today)
            return SimpleDateFormat(if (sameDay) "HH:mm" else "d MMM HH:mm", Locale.getDefault()).format(then.time)
        }

        /** The widget that an intent is for: its extra, or the address of the intent. */
        fun widgetIdOf(intent: Intent): Int {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) return id
            val fromData = intent.data?.takeIf { it.scheme == "tefteri-agenda" }?.pathSegments?.firstOrNull()
            return fromData?.toIntOrNull() ?: AppWidgetManager.INVALID_APPWIDGET_ID
        }

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        private fun shownKey(id: Int) = "shown_$id"
        private fun setOnKey(id: Int) = "set_on_$id"
        private fun scrolledKey(id: Int) = "scrolled_$id"

        /**
         * Remembers the day that the arrows chose, as the day itself and not as a number of days
         * from today. The write is finished when this returns (not queued), so that no later
         * redraw, in this process or another one, can read an older day.
         */
        private fun show(context: Context, id: Int, day: Calendar) {
            prefs(context).edit()
                .putString(shownKey(id), AgendaData.dayKey(day))
                .putString(setOnKey(id), AgendaData.dayKey(Calendar.getInstance()))
                .remove(scrolledKey(id))
                .commit()
        }

        /** The day that the widget shows: the one that the arrows chose today, else today. */
        fun shownDay(context: Context, id: Int): Calendar {
            val p = prefs(context)
            val today = Calendar.getInstance()
            val shown = p.getString(shownKey(id), null)
            if (shown != null && p.getString(setOnKey(id), null) == AgendaData.dayKey(today)) {
                parseDay(shown)?.let { return it }
            }
            return today
        }

        private fun parseDay(key: String): Calendar? {
            val parts = key.split("-")
            if (parts.size != 3) return null
            return try {
                Calendar.getInstance().apply {
                    clear()
                    set(parts[0].toInt(), parts[1].toInt() - 1, parts[2].toInt(), 12, 0, 0)
                }
            } catch (e: NumberFormatException) {
                null
            }
        }

        /** Days from today that the widget shows: 1 is tomorrow, -1 is yesterday. */
        fun currentOffset(context: Context, id: Int): Int {
            val noon = { c: Calendar ->
                Calendar.getInstance().apply {
                    clear()
                    set(c.get(Calendar.YEAR), c.get(Calendar.MONTH), c.get(Calendar.DAY_OF_MONTH), 12, 0, 0)
                }.timeInMillis
            }
            val days = (noon(shownDay(context, id)) - noon(Calendar.getInstance())) / DAY_MILLIS.toDouble()
            return Math.round(days).toInt()
        }

        /** True when the list of this day was scrolled to the next event already. */
        fun wasScrolled(context: Context, id: Int): Boolean =
            prefs(context).getString(scrolledKey(id), null) == AgendaData.dayKey(shownDay(context, id))

        /** Remembers that the list of the shown day was scrolled, so that it happens once. */
        fun markScrolled(context: Context, id: Int) {
            prefs(context).edit().putString(scrolledKey(id), AgendaData.dayKey(shownDay(context, id))).commit()
        }

        private const val DAY_MILLIS = 24L * 60 * 60 * 1000

        /**
         * Two lines: "Today", "Tomorrow", "Yesterday" or the name of the weekday, and under it
         * the date, for example "Today" and "22 Nov".
         */
        fun dateLabel(context: Context, offset: Int, day: Calendar): String {
            val date = SimpleDateFormat("d MMM", Locale.getDefault()).format(day.time)
            val name = when (offset) {
                0 -> context.getString(R.string.agenda_today)
                1 -> context.getString(R.string.agenda_tomorrow)
                -1 -> context.getString(R.string.agenda_yesterday)
                else -> SimpleDateFormat("EEEE", Locale.getDefault()).format(day.time)
            }
            return "$name\n$date"
        }
    }
}
