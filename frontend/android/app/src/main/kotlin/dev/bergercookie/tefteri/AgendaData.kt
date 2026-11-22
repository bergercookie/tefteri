package dev.bergercookie.tefteri

import android.content.Context
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.text.SimpleDateFormat
import java.util.Calendar
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/** One row of the agenda: an event or a task of a day. */
data class AgendaItem(
    val isTask: Boolean,
    val title: String,
    /** "09:00 - 10:30", "All day" or "" for a task without a time. */
    val time: String,
    /** The calendar or project, may be empty. */
    val detail: String,
    /** The color of the calendar or project as ARGB, or 0 for the accent. */
    val color: Int,
    val done: Boolean,
)

/** What the widget shows for one day. */
sealed class AgendaResult {
    data class Loaded(val items: List<AgendaItem>) : AgendaResult()
    object NotSignedIn : AgendaResult()
    object Failed : AgendaResult()
}

/** Reads the day of the app from the server, with the token and address that the app saved. */
object AgendaData {
    private const val PREFS = "FlutterSharedPreferences"

    fun dayKey(cal: Calendar): String =
        String.format(
            Locale.ROOT, "%04d-%02d-%02d",
            cal.get(Calendar.YEAR), cal.get(Calendar.MONTH) + 1, cal.get(Calendar.DAY_OF_MONTH),
        )

    fun fetch(context: Context, day: Calendar): AgendaResult {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.session_token", null)
        val server = prefs.getString("flutter.server_address", null)
        if (token.isNullOrEmpty() || server.isNullOrEmpty()) return AgendaResult.NotSignedIn
        return try {
            val url = URL("${server.trimEnd('/')}/api/v1/views/day/${dayKey(day)}")
            val conn = url.openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 10_000
                conn.readTimeout = 10_000
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("X-Tefteri-Client", "tefteri")
                conn.setRequestProperty("Accept", "application/json")
                when (conn.responseCode) {
                    200 -> parse(conn.inputStream.bufferedReader().use { it.readText() })
                    401 -> AgendaResult.NotSignedIn
                    else -> AgendaResult.Failed
                }
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            AgendaResult.Failed
        }
    }

    /** Turns the body of `GET /views/day/{day}` into rows: events by start, then tasks. */
    fun parse(body: String): AgendaResult {
        return try {
            val root = JSONObject(body)
            val items = mutableListOf<AgendaItem>()
            val entries = root.optJSONArray("entries")
            for (i in 0 until (entries?.length() ?: 0)) {
                val e = entries!!.getJSONObject(i)
                val allDay = e.optBoolean("all_day")
                items.add(
                    AgendaItem(
                        isTask = false,
                        title = e.optString("title"),
                        time = if (allDay) "All day"
                        else "${clock(e.optString("start"))} - ${clock(e.optString("end"))}",
                        detail = e.optString("location"),
                        color = color(e.optString("color")),
                        done = false,
                    ),
                )
            }
            val tasks = root.optJSONArray("tasks")
            val taskItems = mutableListOf<AgendaItem>()
            for (i in 0 until (tasks?.length() ?: 0)) {
                val t = tasks!!.getJSONObject(i)
                taskItems.add(
                    AgendaItem(
                        isTask = true,
                        title = t.optString("title"),
                        time = "",
                        detail = if (t.isNull("project")) "" else t.optString("project"),
                        color = color(if (t.isNull("project_color")) "" else t.optString("project_color")),
                        done = t.optString("status") == "done",
                    ),
                )
            }
            // Open tasks first, done tasks last.
            items.addAll(taskItems.sortedBy { it.done })
            AgendaResult.Loaded(items)
        } catch (e: Exception) {
            AgendaResult.Failed
        }
    }

    /** "#rrggbb" to ARGB, or 0. */
    fun color(hex: String): Int {
        if (!Regex("#[0-9a-fA-F]{6}").matches(hex)) return 0
        return (0xFF000000L or hex.substring(1).toLong(16)).toInt()
    }

    /** The local "HH:mm" of a time such as `2026-11-22T09:00:00Z` (UTC). */
    private fun clock(iso: String): String {
        if (iso.length < 19) return ""
        return try {
            val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT)
            parser.timeZone = TimeZone.getTimeZone("UTC")
            val moment: Date = parser.parse(iso.substring(0, 19)) ?: return ""
            SimpleDateFormat("HH:mm", Locale.ROOT).format(moment)
        } catch (e: Exception) {
            ""
        }
    }
}
