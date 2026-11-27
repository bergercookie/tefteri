package dev.bergercookie.tefteri

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Locale
import java.util.TimeZone

/** One notification that the server wants shown at [fireAt] (milliseconds since 1970). */
data class ReminderItem(
    val id: String,
    val kind: String,
    val title: String,
    val body: String,
    val fireAt: Long,
    /** A path in the app, such as `/week/plan?date=2030-03-11`. */
    val link: String,
    /** The start or due time of a task or an event (milliseconds), or null for a review. */
    val at: Long? = null,
    /** `Starts` or `Due`. */
    val verb: String? = null,
    /** The project of a task or the place of an event. */
    val detail: String? = null,
) {
    /**
     * The text of the notification. For a task or an event the time is written in the time zone
     * of the phone, not the one that the server keeps for the user.
     */
    fun text(zone: TimeZone = TimeZone.getDefault()): String {
        if (at == null || verb.isNullOrEmpty()) return body
        val clock = SimpleDateFormat("HH:mm", Locale.ROOT).apply { timeZone = zone }.format(at)
        val when_ = "$verb at $clock"
        return if (detail.isNullOrEmpty()) when_ else "$when_ \u00b7 $detail"
    }
}

/** What the server said about the reminders. */
sealed class ReminderResult {
    data class Loaded(val items: List<ReminderItem>) : ReminderResult()
    object NotSignedIn : ReminderResult()
    object Failed : ReminderResult()
}

/** Reads `GET /api/v1/reminders` with the login that the app saved. */
object ReminderData {
    private const val PREFS = "FlutterSharedPreferences"

    /** The reminders that fire from [from] (milliseconds) for [hours] hours. */
    fun fetch(context: Context, from: Long, hours: Int): ReminderResult {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.session_token", null)
        val server = prefs.getString("flutter.server_address", null)
        if (token.isNullOrEmpty() || server.isNullOrEmpty()) return ReminderResult.NotSignedIn
        return try {
            val start = iso(from)
            val url = URL("${server.trimEnd('/')}/api/v1/reminders?from=$start&hours=$hours")
            val conn = url.openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 10_000
                conn.readTimeout = 10_000
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("X-Tefteri-Client", "tefteri")
                conn.setRequestProperty("Accept", "application/json")
                when (conn.responseCode) {
                    200 -> parse(conn.inputStream.bufferedReader().use { it.readText() })
                    401 -> ReminderResult.NotSignedIn
                    else -> ReminderResult.Failed
                }
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            ReminderResult.Failed
        }
    }

    /** Turns the body of the answer into reminders. */
    fun parse(body: String): ReminderResult {
        return try {
            val list = JSONObject(body).getJSONArray("reminders")
            val items = (0 until list.length()).map {
                val r = list.getJSONObject(it)
                ReminderItem(
                    id = r.getString("id"),
                    kind = r.optString("kind"),
                    title = r.optString("title"),
                    body = r.optString("body"),
                    fireAt = millis(r.getString("fire_at")),
                    link = r.optString("link", "/"),
                    at = if (r.isNull("at")) null else millis(r.getString("at")),
                    verb = if (r.isNull("verb")) null else r.optString("verb"),
                    detail = if (r.isNull("detail")) null else r.optString("detail"),
                )
            }
            ReminderResult.Loaded(items)
        } catch (e: Exception) {
            ReminderResult.Failed
        }
    }

    private fun format() = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT).apply {
        timeZone = TimeZone.getTimeZone("UTC")
    }

    /** `2030-03-10T14:15:00Z` (or with a fraction or an offset of 0) as milliseconds. */
    fun millis(iso: String): Long = format().parse(iso.substring(0, 19))!!.time

    /** The time as UTC text for a query: `2030-03-10T14:15:00Z`. */
    fun iso(millis: Long): String = format().format(millis) + "Z"
}
