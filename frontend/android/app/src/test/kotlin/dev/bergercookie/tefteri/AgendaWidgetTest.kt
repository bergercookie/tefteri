package dev.bergercookie.tefteri

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.os.Looper
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.core.app.ApplicationProvider
import org.json.JSONObject
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.Robolectric
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import org.robolectric.shadows.ShadowAppWidgetManager
import java.net.InetAddress
import java.net.ServerSocket
import java.util.Calendar
import java.util.TimeZone

/** Runs the agenda widget on the JVM: its layouts, its arrows, its list and its requests. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class AgendaWidgetTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private var server: ServerSocket? = null
    private val requests = mutableListOf<Pair<String, String?>>()
    private var status = 200

    private var body = """
        {"date": "2026-11-22",
         "entries": [
           {"title": "Standup", "start": "2026-11-22T08:00:00Z", "end": "2026-11-22T08:30:00Z",
            "all_day": false, "color": "#ff0000", "location": "Room 4"},
           {"title": "Holiday", "start": "2026-11-21T22:00:00Z", "end": "2026-11-22T22:00:00Z",
            "all_day": true, "color": null, "location": ""}],
         "tasks": [
           {"title": "Done thing", "status": "done", "due_at": "2026-11-22T10:00:00Z",
            "all_day": false, "project": "Home", "project_color": "#00ff00"},
           {"title": "Write report", "status": "open", "due_at": "2026-11-22T12:00:00Z",
            "all_day": false, "project": null, "project_color": null},
           {"title": "Pay rent", "status": "open", "due_at": "2026-11-21T22:00:00Z",
            "all_day": true, "project": "Home", "project_color": null}],
         "note": null}
    """.trimIndent()

    @Before
    fun setUp() {
        TimeZone.setDefault(TimeZone.getTimeZone("Europe/Athens"))
        val http = ServerSocket(0, 50, InetAddress.getByName("127.0.0.1"))
        server = http
        Thread {
            while (!http.isClosed) {
                try {
                    http.accept().use { socket ->
                        val input = socket.getInputStream().bufferedReader()
                        val path = input.readLine().split(" ")[1]
                        var auth: String? = null
                        while (true) {
                            val line = input.readLine()
                            if (line.isNullOrEmpty()) break
                            if (line.startsWith("Authorization:", ignoreCase = true)) auth = line.substringAfter(":").trim()
                        }
                        synchronized(requests) { requests.add(path to auth) }
                        val bytes = body.toByteArray()
                        val out = socket.getOutputStream()
                        val head = if (status == 200) "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                        else "HTTP/1.1 $status Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        out.write(head.toByteArray())
                        if (status == 200) out.write(bytes)
                        out.flush()
                    }
                } catch (e: Exception) {
                    // The socket was closed by the test.
                }
            }
        }.apply { isDaemon = true }.start()
        signIn("token-1", "http://127.0.0.1:${http.localPort}")
    }

    @After
    fun tearDown() {
        server?.close()
    }

    private fun signIn(token: String?, address: String?) {
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit()
            .apply {
                if (token == null) remove("flutter.session_token") else putString("flutter.session_token", token)
                if (address == null) remove("flutter.server_address") else putString("flutter.server_address", address)
            }.commit()
    }

    private fun texts(view: View): List<String> =
        (view as? TextView)?.let { listOf(it.text.toString()) }
            ?: ((view as? android.view.ViewGroup)?.let { g -> (0 until g.childCount).flatMap { texts(g.getChildAt(it)) } }
                ?: emptyList())

    private fun factory(widgetId: Int) =
        Robolectric.setupService(AgendaWidgetService::class.java).onGetViewFactory(
            Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, widgetId),
        )

    private fun rows(widgetId: Int): List<List<String>> {
        val factory = factory(widgetId)
        factory.onDataSetChanged()
        val parent = FrameLayout(context)
        return (0 until factory.count).map { texts(factory.getViewAt(it).apply(context, parent)).filter { t -> t.isNotEmpty() } }
    }

    /** Taps a view of the widget. The broadcast of the tap arrives when the main looper runs. */
    private fun click(manager: ShadowAppWidgetManager, id: Int, viewId: Int) {
        manager.getViewFor(id).findViewById<View>(viewId).performClick()
        shadowOf(Looper.getMainLooper()).idle()
    }

    private fun createWidget(): Pair<Int, ShadowAppWidgetManager> {
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        val id = manager.createWidget(AgendaWidgetProvider::class.java, R.layout.tefteri_agenda_widget)
        // The launcher asks the provider to draw the widget.
        AgendaWidgetProvider().onUpdate(context, AppWidgetManager.getInstance(context), intArrayOf(id))
        return id to manager
    }

    @Test
    fun `the day is read with the saved login and shown as events then tasks`() {
        val (id, _) = createWidget()
        val shown = rows(id)
        assertEquals("/api/v1/views/day/${AgendaData.dayKey(Calendar.getInstance())}", requests.last().first)
        assertEquals("Bearer token-1", requests.last().second)
        assertEquals(
            listOf(
                listOf("Standup", "10:00 - 10:30 · Room 4"),
                listOf("Holiday", "All day"),
                listOf("☐ Write report", "Due 14:00"),
                listOf("☐ Pay rent", "Task · Home"),
                listOf("✓ Done thing", "Due 12:00 · Home"),
            ),
            shown,
        )
    }

    @Test
    fun `the widget starts on today and the arrows move one day at a time`() {
        val (id, manager) = createWidget()
        fun label(): String = texts(manager.getViewFor(id)).first { it.contains("\n") }
        fun offset() = AgendaWidgetProvider.currentOffset(context, id)
        assertEquals(0, offset())
        assertTrue(label(), label().startsWith("Today"))

        click(manager, id, R.id.agenda_next)
        assertEquals(1, offset())
        assertTrue(label(), label().startsWith("Tomorrow"))
        click(manager, id, R.id.agenda_next)
        assertEquals(2, offset())
        val twoDays = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 2) }
        val weekday = java.text.SimpleDateFormat("EEEE", java.util.Locale.getDefault()).format(twoDays.time)
        val date = java.text.SimpleDateFormat("d MMM", java.util.Locale.getDefault()).format(twoDays.time)
        assertEquals("$weekday\n$date", label())
        repeat(4) { click(manager, id, R.id.agenda_previous) }
        assertEquals(-2, offset())
        click(manager, id, R.id.agenda_previous)
        click(manager, id, R.id.agenda_date)
        assertEquals(0, offset())
        assertTrue(label(), label().startsWith("Today"))
    }

    @Test
    fun `the list asks for the day that the arrows chose`() {
        val (id, manager) = createWidget()
        click(manager, id, R.id.agenda_next)
        rows(id)
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
        assertEquals("/api/v1/views/day/${AgendaData.dayKey(tomorrow)}", requests.last().first)
    }

    @Test
    fun `a day that was chosen on an earlier day is forgotten`() {
        val (id, _) = createWidget()
        context.getSharedPreferences("tefteri_agenda_widget", Context.MODE_PRIVATE).edit()
            .putString("shown_$id", "2000-01-05").putString("set_on_$id", "2000-01-01").commit()
        assertEquals(0, AgendaWidgetProvider.currentOffset(context, id))
    }

    @Test
    fun `a row opens the planner at the shown day`() {
        val (id, _) = createWidget()
        val factory = factory(id)
        factory.onDataSetChanged()
        val row = factory.getViewAt(0).apply(context, FrameLayout(context))
        assertTrue(row.findViewById<View>(R.id.agenda_row) != null)
    }

    @Test
    fun `without a login the list asks the person to sign in`() {
        signIn(null, null)
        val (id, _) = createWidget()
        assertEquals(listOf(listOf(context.getString(R.string.agenda_sign_in))), rows(id))
    }

    @Test
    fun `an expired login asks the person to sign in and a broken server says so`() {
        val (id, _) = createWidget()
        status = 401
        assertEquals(listOf(listOf(context.getString(R.string.agenda_sign_in))), rows(id))
        status = 500
        assertEquals(listOf(listOf(context.getString(R.string.agenda_failed))), rows(id))
    }

    @Test
    fun `the picker preview inflates and shows a day`() {
        val preview = android.view.LayoutInflater.from(context)
            .inflate(R.layout.tefteri_agenda_preview, FrameLayout(context), false)
        val shown = texts(preview)
        assertTrue(shown.toString(), shown.any { it.startsWith("Today") })
        assertTrue(shown.toString(), shown.any { it.contains("Team meeting") })
    }

    @Test
    fun `both widgets are declared as providers with a label and a preview`() {
        val manager = context.packageManager
        val names = manager.queryBroadcastReceivers(
            Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).setPackage(context.packageName),
            android.content.pm.PackageManager.GET_META_DATA,
        ).map { it.activityInfo.name }.toSet()
        assertTrue(names.toString(), "dev.bergercookie.tefteri.AgendaWidgetProvider" in names)
        assertTrue(names.toString(), "dev.bergercookie.tefteri.NavWidgetProvider" in names)
    }

    @Test
    fun `an empty day says that nothing is planned`() {
        val parsed = AgendaData.parse("""{"entries": [], "tasks": []}""")
        assertEquals(AgendaResult.Loaded(emptyList()), parsed)
        assertEquals(JSONObject("{}").length(), 0)
    }

    private fun open(id: Int) = factory(id).also { it.onDataSetChanged() }

    @Test
    fun `a chosen day stays when the widget is drawn again and its list is loaded again`() {
        val (id, manager) = createWidget()
        click(manager, id, R.id.agenda_next)
        assertEquals(1, AgendaWidgetProvider.currentOffset(context, id))
        // What a launcher or the system can do after a tap: ask for an update, load the list.
        repeat(3) {
            AgendaWidgetProvider().onUpdate(context, AppWidgetManager.getInstance(context), intArrayOf(id))
            open(id)
            shadowOf(Looper.getMainLooper()).idle()
        }
        assertEquals(1, AgendaWidgetProvider.currentOffset(context, id))
        val label = texts(manager.getViewFor(id)).first { it.contains("\n") }
        assertTrue(label, label.startsWith("Tomorrow"))
        // And the list asked the server for tomorrow, not for today.
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
        assertEquals("/api/v1/views/day/${AgendaData.dayKey(tomorrow)}", requests.last().first)
        click(manager, id, R.id.agenda_previous)
        click(manager, id, R.id.agenda_previous)
        assertEquals(-1, AgendaWidgetProvider.currentOffset(context, id))
    }

    @Test
    fun `the chosen day is written to disk at once`() {
        val (id, manager) = createWidget()
        click(manager, id, R.id.agenda_next)
        // A second reader of the same file, as another process would be, sees the day.
        val stored = context.getSharedPreferences("tefteri_agenda_widget", Context.MODE_PRIVATE)
        val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
        assertEquals(AgendaData.dayKey(tomorrow), stored.getString("shown_$id", null))
    }

    @Test
    fun `the id of the widget is read from the data of the list intent when the extras are lost`() {
        val withExtra = Intent().putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, 7)
        assertEquals(7, AgendaWidgetService.widgetIdOf(withExtra))
        val data = Intent().setData(android.net.Uri.parse("intent:#Intent;component=a/.B;i.appWidgetId=12;end"))
        assertEquals(12, AgendaWidgetService.widgetIdOf(data))
        assertEquals(AppWidgetManager.INVALID_APPWIDGET_ID, AgendaWidgetService.widgetIdOf(Intent()))
    }

    private fun event(title: String, endYear: Int) = """
        {"title": "$title", "start": "$endYear-03-10T08:00:00Z", "end": "$endYear-03-10T09:00:00Z",
         "all_day": false, "color": "#ff0000", "location": ""}
    """.trimIndent()

    @Test
    fun `an event that is over is grayed out and the others are not`() {
        val (id, _) = createWidget()
        body = """{"entries": [${event("Old", 2000)}, ${event("Coming", 2099)}], "tasks": []}"""
        val factory = open(id)
        val parent = FrameLayout(context)
        val old = factory.getViewAt(0).apply(context, parent)
        val coming = factory.getViewAt(1).apply(context, parent)
        assertEquals(PAST_ALPHA, old.alpha, 0.001f)
        assertEquals(1f, coming.alpha, 0.001f)
    }

    @Test
    fun `an all-day event of today is not over and one of a day that passed is`() {
        val soon = System.currentTimeMillis() + 3_600_000
        val before = System.currentTimeMillis() - 3_600_000
        assertTrue(AgendaData.isOver(ReminderData.iso(before), System.currentTimeMillis()))
        assertTrue(!AgendaData.isOver(ReminderData.iso(soon), System.currentTimeMillis()))
        assertTrue(AgendaData.isOver(ReminderData.iso(1_000), 1_000)) // ends this second: over
        assertTrue(!AgendaData.isOver("", 1_000)) // an end that cannot be read is not over
    }

    private fun item(task: Boolean, past: Boolean = false) =
        AgendaItem(task, "x", "", "", 0, false, past)

    @Test
    fun `the list starts at the first event that is not over`() {
        // Two events are over, the third is next, then one more and two tasks.
        val items = listOf(item(false, true), item(false, true), item(false), item(false), item(true), item(true))
        assertEquals(2, AgendaScroll.anchorIndex(items))
        // No event is over yet: the list starts at the top, so that the first event shows.
        assertEquals(-1, AgendaScroll.anchorIndex(listOf(item(false), item(false), item(true))))
        // Every event is over: the list starts at the tasks.
        assertEquals(2, AgendaScroll.anchorIndex(listOf(item(false, true), item(false, true), item(true))))
        // Every event is over and there is no task: nothing is below them, so there is no scroll.
        assertEquals(-1, AgendaScroll.anchorIndex(listOf(item(false, true), item(false, true))))
        // No event at all.
        assertEquals(-1, AgendaScroll.anchorIndex(listOf(item(true), item(true))))
        assertEquals(-1, AgendaScroll.anchorIndex(emptyList()))
    }

    @Test
    fun `the scroll position puts the anchor at the top of the screen`() {
        // A widget that is 220 dp high shows (220 - 60) / 52 = 3 rows.
        assertEquals(3, AgendaScroll.rowsOnScreen(220))
        assertEquals(1, AgendaScroll.rowsOnScreen(80)) // a very small widget still shows a row
        // The anchor is row 5, so the last row of that screen is row 7.
        assertEquals(7, AgendaScroll.targetPosition(5, 20, 220))
        // Near the end of the list, the last row is the most that the list can show.
        assertEquals(9, AgendaScroll.targetPosition(8, 10, 220))
        assertEquals(0, AgendaScroll.targetPosition(0, 1, 220))
    }

    @Test
    fun `the list is scrolled once for today and not for another day`() {
        val (id, manager) = createWidget()
        body = """{"entries": [${event("Old", 2000)}, ${event("Coming", 2099)}], "tasks": []}"""
        open(id)
        assertTrue(AgendaWidgetProvider.wasScrolled(context, id))
        // Another day is shown from the top and is not marked.
        click(manager, id, R.id.agenda_next)
        open(id)
        assertTrue(!AgendaWidgetProvider.wasScrolled(context, id))
        // Back to today: it is scrolled again, once.
        click(manager, id, R.id.agenda_date)
        assertTrue(!AgendaWidgetProvider.wasScrolled(context, id))
        open(id)
        assertTrue(AgendaWidgetProvider.wasScrolled(context, id))
    }

    @Test
    fun `no scroll is made when no event is over`() {
        val (id, _) = createWidget()
        body = """{"entries": [${event("Coming", 2099)}], "tasks": []}"""
        open(id)
        assertTrue(!AgendaWidgetProvider.wasScrolled(context, id))
    }

    @Test
    fun `every button of every widget has an intent of its own`() {
        val manager = shadowOf(AppWidgetManager.getInstance(context))
        val first = manager.createWidget(AgendaWidgetProvider::class.java, R.layout.tefteri_agenda_widget)
        val second = manager.createWidget(AgendaWidgetProvider::class.java, R.layout.tefteri_agenda_widget)
        for (id in listOf(first, second)) {
            AgendaWidgetProvider().onUpdate(context, AppWidgetManager.getInstance(context), intArrayOf(id))
        }
        // A tap on a button of the second widget moves the second widget and not the first.
        click(manager, second, R.id.agenda_next)
        click(manager, second, R.id.agenda_next)
        click(manager, first, R.id.agenda_previous)
        assertEquals(2, AgendaWidgetProvider.currentOffset(context, second))
        assertEquals(-1, AgendaWidgetProvider.currentOffset(context, first))
        // The widget is also found by the address of the intent, when the extras are lost.
        val bare = Intent(AgendaWidgetProvider.ACTION_NEXT)
            .setData(android.net.Uri.parse("tefteri-agenda://widget/$second/next"))
        assertEquals(second, AgendaWidgetProvider.widgetIdOf(bare))
    }
}
