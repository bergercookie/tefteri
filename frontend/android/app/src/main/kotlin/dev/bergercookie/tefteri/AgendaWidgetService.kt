package dev.bergercookie.tefteri

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/** Gives the list of the agenda widget its rows. */
class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        AgendaFactory(applicationContext, widgetIdOf(intent))

    companion object {
        /**
         * The id of the widget that the list is for. It is an extra of the intent, and it is also
         * in the data of the intent (see AgendaWidgetProvider), in case a launcher drops the extras.
         */
        fun widgetIdOf(intent: Intent): Int {
            val id = intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
            if (id != AppWidgetManager.INVALID_APPWIDGET_ID) return id
            val fromData = Regex("appWidgetId=(\\d+)").find(intent.dataString ?: "")?.groupValues?.get(1)
            return fromData?.toIntOrNull() ?: AppWidgetManager.INVALID_APPWIDGET_ID
        }
    }
}

private class AgendaFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var items: List<AgendaItem> = emptyList()
    private var message: String? = null
    private var dayKey: String = ""
    private var link: Uri = Uri.parse("tefteri://app/")

    override fun onCreate() {}

    /** Runs off the main thread, so the request to the server may block here. */
    override fun onDataSetChanged() {
        val day = AgendaWidgetProvider.shownDay(context, widgetId)
        dayKey = AgendaData.dayKey(day)
        link = Uri.parse("tefteri://app/?date=$dayKey")
        when (val result = AgendaData.fetch(context, day)) {
            is AgendaResult.Loaded -> {
                AgendaWidgetProvider.showStatus(context, widgetId, result.staleSince)
                items = result.items
                message = if (items.isEmpty()) context.getString(R.string.agenda_empty) else null
                // On today, start the list at the next event, with the earlier ones above it.
                if (AgendaWidgetProvider.currentOffset(context, widgetId) == 0) {
                    AgendaScroll.request(context, widgetId, items)
                }
            }
            AgendaResult.NotSignedIn -> {
                AgendaWidgetProvider.showStatus(context, widgetId, null)
                items = emptyList()
                message = context.getString(R.string.agenda_sign_in)
            }
            AgendaResult.Failed -> {
                AgendaWidgetProvider.showStatus(context, widgetId, null)
                items = emptyList()
                message = context.getString(R.string.agenda_failed)
            }
        }
    }

    override fun onDestroy() {}

    // A message takes the one row of the list when there is nothing else to show.
    override fun getCount(): Int = if (items.isEmpty() && message != null) 1 else items.size

    override fun getViewAt(position: Int): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.tefteri_agenda_row)
        if (items.isEmpty()) {
            row.setOnClickFillInIntent(R.id.agenda_row, Intent().setData(link))
            row.setViewVisibility(R.id.agenda_swatch, View.INVISIBLE)
            row.setViewVisibility(R.id.agenda_time, View.GONE)
            row.setTextViewText(R.id.agenda_title, message)
            return row
        }
        val item = items[position]
        // A tap opens the task or the event in the app, ready to edit.
        row.setOnClickFillInIntent(R.id.agenda_row, Intent().setData(rowLink(dayKey, item)))
        row.setViewVisibility(R.id.agenda_swatch, View.VISIBLE)
        val accent = context.getColor(R.color.widget_accent)
        row.setInt(R.id.agenda_swatch, "setBackgroundColor", if (item.color != 0) item.color else accent)
        val prefix = when {
            item.isTask && item.done -> "✓ "
            item.isTask -> "☐ "
            else -> ""
        }
        row.setTextViewText(R.id.agenda_title, prefix + item.title)
        val time = if (item.time.isEmpty() && item.isTask) context.getString(R.string.agenda_task) else item.time
        val line = listOf(time, item.detail).filter { it.isNotEmpty() }.joinToString(" \u00b7 ")
        row.setViewVisibility(R.id.agenda_time, if (line.isEmpty()) View.GONE else View.VISIBLE)
        row.setTextViewText(R.id.agenda_time, line)
        // An event that is over is grayed out.
        if (item.past) row.setFloat(R.id.agenda_row, "setAlpha", PAST_ALPHA)
        row.setTextColor(
            R.id.agenda_title,
            context.getColor(if (item.done) R.color.widget_muted else R.color.widget_ink),
        )
        return row
    }

    override fun getLoadingView(): RemoteViews? = null
    override fun getViewTypeCount(): Int = 1
    override fun getItemId(position: Int): Long = position.toLong()
    override fun hasStableIds(): Boolean = false
}

/**
 * Where a tap on a row goes: the planner at the day, with the task or the event opened. A row
 * that has no id (an old answer) opens the day only.
 */
fun rowLink(dayKey: String, item: AgendaItem): Uri {
    val base = "tefteri://app/?date=$dayKey"
    if (item.id.isEmpty()) return Uri.parse(base)
    return Uri.parse("$base&${if (item.isTask) "task" else "event"}=${Uri.encode(item.id)}")
}

/** How faint a row of an event that is over is. */
const val PAST_ALPHA = 0.45f
