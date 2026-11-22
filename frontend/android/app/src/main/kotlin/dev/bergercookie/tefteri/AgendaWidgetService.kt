package dev.bergercookie.tefteri

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService

/** Gives the list of the agenda widget its rows. */
class AgendaWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        AgendaFactory(
            applicationContext,
            intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID),
        )
}

private class AgendaFactory(
    private val context: Context,
    private val widgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {
    private var items: List<AgendaItem> = emptyList()
    private var message: String? = null

    override fun onCreate() {}

    /** Runs off the main thread, so the request to the server may block here. */
    override fun onDataSetChanged() {
        val day = AgendaWidgetProvider.shownDay(context, widgetId)
        when (val result = AgendaData.fetch(context, day)) {
            is AgendaResult.Loaded -> {
                items = result.items
                message = if (items.isEmpty()) context.getString(R.string.agenda_empty) else null
            }
            AgendaResult.NotSignedIn -> {
                items = emptyList()
                message = context.getString(R.string.agenda_sign_in)
            }
            AgendaResult.Failed -> {
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
        val fill = Intent().putExtra(AgendaWidgetProvider.EXTRA_OPEN, true)
        row.setOnClickFillInIntent(R.id.agenda_row, fill)
        if (items.isEmpty()) {
            row.setViewVisibility(R.id.agenda_swatch, View.INVISIBLE)
            row.setViewVisibility(R.id.agenda_time, View.GONE)
            row.setViewVisibility(R.id.agenda_detail, View.GONE)
            row.setTextViewText(R.id.agenda_title, message)
            return row
        }
        val item = items[position]
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
        row.setViewVisibility(R.id.agenda_time, if (time.isEmpty()) View.GONE else View.VISIBLE)
        row.setTextViewText(R.id.agenda_time, time)
        row.setViewVisibility(R.id.agenda_detail, if (item.detail.isEmpty()) View.GONE else View.VISIBLE)
        row.setTextViewText(R.id.agenda_detail, item.detail)
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
