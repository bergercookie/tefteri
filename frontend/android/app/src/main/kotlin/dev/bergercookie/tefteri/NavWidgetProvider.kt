package dev.bergercookie.tefteri

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews

/**
 * The home screen widget: one row of four buttons that open a view of tefteri.
 *
 * Each button starts [MainActivity] with a link such as `tefteri://app/daily`. Flutter hands
 * the path of the link to the router of the app, both when the app starts and when it is
 * already open. The paths are those of `lib/core/shortcuts/keymap.dart`; a test checks that
 * they match.
 */
class NavWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, views(context))
        }
    }

    /** A button of the widget: the view that holds it and the path of the view it opens. */
    private data class Button(val viewId: Int, val path: String)

    companion object {
        private val buttons = listOf(
            Button(R.id.widget_today, "/daily"),
            Button(R.id.widget_week, "/week"),
            Button(R.id.widget_month, "/month"),
            Button(R.id.widget_planner, "/"),
        )

        private fun views(context: Context): RemoteViews {
            val views = RemoteViews(context.packageName, R.layout.tefteri_widget)
            buttons.forEachIndexed { index, button ->
                views.setOnClickPendingIntent(button.viewId, open(context, button.path, index))
            }
            return views
        }

        /** An intent that opens [path] in the app. [code] makes each button's intent its own. */
        private fun open(context: Context, path: String, code: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("tefteri://app$path"))
                .setClass(context, MainActivity::class.java)
                // One instance of the app: an open app gets the link in onNewIntent.
                .addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
