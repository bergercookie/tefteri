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
    /** An event that is over: it ended before now. The widget shows it grayed out. */
    val past: Boolean = false,
    /** The id of the task or the event in tefteri. A tap on the row opens it in the app. */
    val id: String = "",
)

/** What the widget shows for one day. */
sealed class AgendaResult {
    /**
     * The rows of the day. [staleSince] is set when the server could not be reached and the rows
     * are the ones of an earlier answer: the time of that answer, in milliseconds since 1970.
     */
    data class Loaded(val items: List<AgendaItem>, val staleSince: Long? = null) : AgendaResult()
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

    private const val CACHE = "tefteri_agenda_cache"
    private const val KEEP_MILLIS = 14L * 24 * 60 * 60 * 1000

    /** How many times the server is asked before the widget falls back to the last answer. */
    const val ATTEMPTS = 3

    /** The wait between two attempts. A test sets it to 0. */
    @Volatile
    var retryDelayMillis = 2_000L

    private sealed class Answer {
        data class Body(val text: String) : Answer()
        object Unauthorized : Answer()
        object Failure : Answer()
    }

    private fun ask(server: String, token: String, key: String): Answer =
        try {
            val url = URL("${server.trimEnd('/')}/api/v1/views/day/$key")
            val conn = url.openConnection() as HttpURLConnection
            try {
                conn.connectTimeout = 10_000
                conn.readTimeout = 10_000
                conn.setRequestProperty("Authorization", "Bearer $token")
                conn.setRequestProperty("X-Tefteri-Client", "tefteri")
                conn.setRequestProperty("Accept", "application/json")
                when (conn.responseCode) {
                    200 -> Answer.Body(conn.inputStream.bufferedReader().use { it.readText() })
                    401 -> Answer.Unauthorized
                    else -> Answer.Failure
                }
            } finally {
                conn.disconnect()
            }
        } catch (e: Exception) {
            Answer.Failure
        }

    /**
     * Reads the day from the server. A request that fails (a phone that is asleep, a network that
     * is not up yet, a server that is slow to wake) is tried again. When every attempt fails, the
     * last answer for this day is shown, marked as old, and only a day that was never loaded shows
     * the failure.
     */
    fun fetch(context: Context, day: Calendar, now: () -> Long = System::currentTimeMillis): AgendaResult {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val token = prefs.getString("flutter.session_token", null)
        val server = prefs.getString("flutter.server_address", null)
        if (token.isNullOrEmpty() || server.isNullOrEmpty()) {
            clearCache(context)
            return AgendaResult.NotSignedIn
        }
        val key = dayKey(day)
        for (attempt in 1..ATTEMPTS) {
            when (val answer = ask(server, token, key)) {
                is Answer.Body -> {
                    val result = parse(answer.text, now())
                    // Only an answer that can be read is kept.
                    if (result is AgendaResult.Loaded) remember(context, key, answer.text, now())
                    return result
                }
                Answer.Unauthorized -> {
                    clearCache(context)
                    return AgendaResult.NotSignedIn
                }
                Answer.Failure -> if (attempt < ATTEMPTS && retryDelayMillis > 0) Thread.sleep(retryDelayMillis)
            }
        }
        return fromCache(context, key, now()) ?: AgendaResult.Failed
    }

    private fun cache(context: Context) = context.getSharedPreferences(CACHE, Context.MODE_PRIVATE)

    private fun remember(context: Context, key: String, body: String, at: Long) {
        val edit = cache(context).edit().putString("body_$key", body).putLong("at_$key", at)
        // Forget the days that are old: the cache holds a few days, not a history.
        for ((name, value) in cache(context).all) {
            if (name.startsWith("at_") && value is Long && at - value > KEEP_MILLIS) {
                edit.remove(name).remove("body_" + name.removePrefix("at_"))
            }
        }
        edit.apply()
    }

    private fun fromCache(context: Context, key: String, now: Long): AgendaResult? {
        val body = cache(context).getString("body_$key", null) ?: return null
        val at = cache(context).getLong("at_$key", 0L)
        val parsed = parse(body, now) as? AgendaResult.Loaded ?: return null
        return parsed.copy(staleSince = at)
    }

    /** Forgets every kept answer, when the person signs out. */
    fun clearCache(context: Context) {
        cache(context).edit().clear().apply()
    }

    /** Turns the body of `GET /views/day/{day}` into rows: events by start, then tasks. */
    fun parse(body: String, now: Long = System.currentTimeMillis()): AgendaResult {
        return try {
            val root = JSONObject(body)
            val items = mutableListOf<AgendaItem>()
            val entries = root.optJSONArray("entries")
            for (i in 0 until (entries?.length() ?: 0)) {
                val e = entries!!.getJSONObject(i)
                val allDay = e.optBoolean("all_day")
                items.add(
                    AgendaItem(
                        id = e.optString("id"),
                        isTask = false,
                        title = e.optString("title"),
                        time = if (allDay) "All day"
                        else "${clock(e.optString("start"))} - ${clock(e.optString("end"))}",
                        detail = e.optString("location"),
                        color = color(e.optString("color")),
                        done = false,
                        // An all-day event ends at the end of its day, so it is over on the next day.
                        past = isOver(e.optString("end"), now),
                    ),
                )
            }
            // The events that are over come first, even before an all-day event of today, so that
            // they all scroll out of view above the next event. The sort keeps the order otherwise.
            items.sortByDescending { it.past }
            val tasks = root.optJSONArray("tasks")
            val taskItems = mutableListOf<AgendaItem>()
            for (i in 0 until (tasks?.length() ?: 0)) {
                val t = tasks!!.getJSONObject(i)
                taskItems.add(
                    AgendaItem(
                        id = t.optString("id"),
                        isTask = true,
                        title = t.optString("title"),
                        time = if (t.optBoolean("all_day") || t.isNull("due_at")) ""
                        else "Due ${clock(t.optString("due_at"))}",
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

    /** The time of [endIso] is not after [now]. An end that cannot be read is not over. */
    fun isOver(endIso: String, now: Long): Boolean =
        try {
            if (endIso.length < 19) false else millis(endIso) <= now
        } catch (e: Exception) {
            false
        }

    /** `2030-03-10T14:15:00Z` as milliseconds since 1970. */
    private fun millis(iso: String): Long {
        val parser = SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.ROOT)
        parser.timeZone = TimeZone.getTimeZone("UTC")
        return parser.parse(iso.substring(0, 19))!!.time
    }

    /** "#rrggbb" to ARGB, or 0. */
    fun color(hex: String): Int {
        if (!Regex("#[0-9a-fA-F]{6}").matches(hex)) return 0
        return (0xFF000000L or hex.substring(1).toLong(16)).toInt()
    }

    /** The local "HH:mm" of a time such as `2026-11-22T09:00:00Z` (UTC). */
    fun clock(iso: String): String {
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
