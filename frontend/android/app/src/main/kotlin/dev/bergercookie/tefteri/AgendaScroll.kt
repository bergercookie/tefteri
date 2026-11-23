package dev.bergercookie.tefteri

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.os.Handler
import android.os.Looper
import android.widget.RemoteViews

/**
 * Scrolls the list of the agenda widget, on today, so that the first event that is not over is at
 * the top and the events that are over are above it, out of view.
 *
 * A widget can only ask a list to scroll to a position, and the list then shows that position at
 * its bottom edge when it scrolls down. So the position to ask for is the one that is a screen
 * of rows below the event. Every row has the same height (`agenda_row_height`), which makes the
 * number of rows on a screen known.
 */
object AgendaScroll {
    /** The height of a row in dp. It is the `minHeight` of the row layout. */
    const val ROW_DP = 52

    /** The header of the widget (the arrows and the date) and the padding around the list, in dp. */
    private const val CHROME_DP = 60

    private const val FIRST_TRY_MILLIS = 900L
    private const val SECOND_TRY_MILLIS = 2500L

    /**
     * The row that the list should start with, or -1 when it should start at the top.
     *
     * That is the first event that is not over, when an event before it is over. When every event
     * is over, it is the first task (the events are above it). With no event that is over, the
     * list starts at the top, so that the first event shows.
     */
    fun anchorIndex(items: List<AgendaItem>): Int {
        val events = items.count { !it.isTask }
        if (events == 0) return -1
        val firstUpcoming = items.indexOfFirst { !it.isTask && !it.past }
        return when {
            firstUpcoming > 0 -> firstUpcoming
            firstUpcoming == 0 -> -1
            // Every event is over: start at the first task, if there is one.
            items.size > events -> events
            else -> -1
        }
    }

    /** How many rows fit in a widget that is [heightDp] high. */
    fun rowsOnScreen(heightDp: Int): Int = ((heightDp - CHROME_DP) / ROW_DP).coerceAtLeast(1)

    /**
     * The position to ask for, so that [anchor] ends at the top of the list: the row that is the
     * last of the screen when [anchor] is the first. At the end of the list, that is the last row.
     */
    fun targetPosition(anchor: Int, count: Int, heightDp: Int): Int =
        (anchor + rowsOnScreen(heightDp) - 1).coerceIn(0, (count - 1).coerceAtLeast(0))

    /** The height of the widget in dp, as the launcher gave it, for the way the phone is held. */
    fun widgetHeightDp(context: Context, id: Int): Int {
        val options = AppWidgetManager.getInstance(context).getAppWidgetOptions(id)
        val portrait = context.resources.configuration.orientation != Configuration.ORIENTATION_LANDSCAPE
        val height = options.getInt(
            if (portrait) AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT else AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT,
        )
        return if (height > 0) height else DEFAULT_HEIGHT_DP
    }

    private const val DEFAULT_HEIGHT_DP = 220

    /**
     * Scrolls the list once for the day that is shown. The list gets its rows a moment after the
     * data is loaded, so the request is made twice, a little later each time. The second one does
     * nothing when the list is where it should be.
     */
    fun request(context: Context, id: Int, items: List<AgendaItem>) {
        if (id == AppWidgetManager.INVALID_APPWIDGET_ID) return
        val anchor = anchorIndex(items)
        if (anchor < 0 || AgendaWidgetProvider.wasScrolled(context, id)) return
        AgendaWidgetProvider.markScrolled(context, id)
        val target = targetPosition(anchor, items.size, widgetHeightDp(context, id))
        val handler = Handler(Looper.getMainLooper())
        for (delay in listOf(FIRST_TRY_MILLIS, SECOND_TRY_MILLIS)) {
            handler.postDelayed({ scrollTo(context, id, target) }, delay)
        }
    }

    /** Asks the list of widget [id] to scroll to [position]. */
    fun scrollTo(context: Context, id: Int, position: Int) {
        val views = RemoteViews(context.packageName, R.layout.tefteri_agenda_widget)
        views.setScrollPosition(R.id.agenda_list, position)
        AppWidgetManager.getInstance(context).partiallyUpdateAppWidget(id, views)
    }
}
