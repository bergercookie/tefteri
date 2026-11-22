package dev.bergercookie.tefteri

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
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
        for (id in ids) refresh(context, id)
    }

    override fun onDeleted(context: Context, ids: IntArray) {
        val edit = prefs(context).edit()
        for (id in ids) edit.remove(offsetKey(id)).remove(baseKey(id))
        edit.apply()
    }

    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
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
        val offset = if (step == 0) 0 else currentOffset(context, id) + step
        prefs(context).edit()
            .putInt(offsetKey(id), offset)
            .putString(baseKey(id), AgendaData.dayKey(Calendar.getInstance()))
            .apply()
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
        views.setTextViewText(R.id.agenda_date, SimpleDateFormat("EEE d MMM", Locale.getDefault()).format(day.time))
        views.setOnClickPendingIntent(R.id.agenda_previous, action(context, id, ACTION_PREVIOUS))
        views.setOnClickPendingIntent(R.id.agenda_next, action(context, id, ACTION_NEXT))
        // The date goes back to today; today is also the refresh.
        views.setOnClickPendingIntent(R.id.agenda_date, action(context, id, ACTION_TODAY))
        views.setOnClickPendingIntent(R.id.agenda_refresh, action(context, id, ACTION_REFRESH))

        val service = Intent(context, AgendaWidgetService::class.java)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        // The data URI makes the intent of each widget unique.
        service.data = Uri.parse(service.toUri(Intent.URI_INTENT_SCHEME))
        views.setRemoteAdapter(R.id.agenda_list, service)

        // A tap on a row opens the planner of the day in the app.
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("tefteri://app/daily"))
            .setClass(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        views.setPendingIntentTemplate(
            R.id.agenda_list,
            PendingIntent.getActivity(context, 0, open, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE),
        )
        manager.updateAppWidget(id, views)
    }

    private fun action(context: Context, id: Int, action: String): PendingIntent {
        val intent = Intent(context, AgendaWidgetProvider::class.java)
            .setAction(action)
            .putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, id)
        return PendingIntent.getBroadcast(
            context,
            id * 10 + action.hashCode().mod(10),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    companion object {
        const val ACTION_PREVIOUS = "dev.bergercookie.tefteri.agenda.PREVIOUS"
        const val ACTION_NEXT = "dev.bergercookie.tefteri.agenda.NEXT"
        const val ACTION_TODAY = "dev.bergercookie.tefteri.agenda.TODAY"
        const val ACTION_REFRESH = "dev.bergercookie.tefteri.agenda.REFRESH"
        const val EXTRA_OPEN = "open"
        private const val PREFS = "tefteri_agenda_widget"

        private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        private fun offsetKey(id: Int) = "offset_$id"
        private fun baseKey(id: Int) = "base_$id"

        /** Days from today that the widget shows. It is 0 when it was set on an earlier day. */
        fun currentOffset(context: Context, id: Int): Int {
            val p = prefs(context)
            val base = p.getString(baseKey(id), null)
            return if (base == AgendaData.dayKey(Calendar.getInstance())) p.getInt(offsetKey(id), 0) else 0
        }

        /** The day that the widget shows. */
        fun shownDay(context: Context, id: Int): Calendar {
            val day = Calendar.getInstance()
            day.add(Calendar.DAY_OF_YEAR, currentOffset(context, id))
            return day
        }
    }
}
