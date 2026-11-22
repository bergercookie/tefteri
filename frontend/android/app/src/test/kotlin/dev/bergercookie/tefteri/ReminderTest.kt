package dev.bergercookie.tefteri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import androidx.test.core.app.ApplicationProvider
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config
import java.net.InetAddress
import java.net.ServerSocket

/** Runs the reminders on the JVM: the alarms, the notifications and the questions to the server. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [34])
class ReminderTest {
    private val context: Context = ApplicationProvider.getApplicationContext()
    private val alarms get() = shadowOf(context.getSystemService(Context.ALARM_SERVICE) as AlarmManager)
    private val notifications get() =
        shadowOf(context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
    private var server: ServerSocket? = null
    private val paths = mutableListOf<String>()
    private var status = 200
    private var reminders = listOf<ReminderItem>()
    private val now = 1_900_000_000_000L

    private fun item(id: String, minutes: Long, title: String = "Call Sam") = ReminderItem(
        id, "task", title, "Due at 14:30", now + minutes * 60_000, "/?date=2030-03-10",
    )

    private fun json(items: List<ReminderItem>): String =
        items.joinToString(",", "{\"reminders\":[", "]}") {
            """{"id":"${it.id}","kind":"${it.kind}","title":"${it.title}","body":"${it.body}",""" +
                """"fire_at":"${ReminderData.iso(it.fireAt)}","link":"${it.link}"}"""
        }

    @Before
    fun setUp() {
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
                        synchronized(paths) { paths.add("$path|$auth") }
                        val bytes = json(reminders).toByteArray()
                        val out = socket.getOutputStream()
                        val head = if (status == 200) {
                            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: ${bytes.size}\r\nConnection: close\r\n\r\n"
                        } else {
                            "HTTP/1.1 $status Error\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                        }
                        out.write(head.toByteArray())
                        if (status == 200) out.write(bytes)
                        out.flush()
                    }
                } catch (e: Exception) {
                    // The test closed the socket.
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
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE).edit().apply {
            if (token == null) remove("flutter.session_token") else putString("flutter.session_token", token)
            if (address == null) remove("flutter.server_address") else putString("flutter.server_address", address)
        }.commit()
    }

    private fun exactAlarms() = alarms.scheduledAlarms.filter { it.interval == 0L }

    @Test
    fun `the answer of the server becomes reminders`() {
        val parsed = ReminderData.parse(json(listOf(item("task:1", 15)))) as ReminderResult.Loaded
        assertEquals(listOf(item("task:1", 15)), parsed.items)
        assertEquals(ReminderResult.Failed, ReminderData.parse("not json"))
        assertEquals(now, ReminderData.millis(ReminderData.iso(now)))
    }

    @Test
    fun `a sync asks the server with the saved login and sets an alarm at each fire time`() {
        reminders = listOf(item("task:1", 15), item("event:2", 45, "Standup"))
        ReminderScheduler.sync(context, now)
        val request = paths.single()
        assertTrue(request, request.startsWith("/api/v1/reminders?from=") && request.contains("&hours=48"))
        assertTrue(request, request.endsWith("|Bearer token-1"))
        assertEquals(
            listOf(now + 15 * 60_000, now + 45 * 60_000),
            exactAlarms().map { it.triggerAtTime }.sorted(),
        )
    }

    @Test
    fun `a second sync does not set an alarm twice and drops the alarm of a reminder that is gone`() {
        reminders = listOf(item("task:1", 15), item("event:2", 45))
        ReminderScheduler.sync(context, now)
        ReminderScheduler.sync(context, now)
        assertEquals(2, exactAlarms().size)
        reminders = listOf(item("event:2", 45))  // the task was done in the meantime
        ReminderScheduler.sync(context, now)
        assertEquals(listOf(now + 45 * 60_000), exactAlarms().map { it.triggerAtTime })
    }

    @Test
    fun `a changed fire time moves the alarm`() {
        reminders = listOf(item("task:1", 15))
        ReminderScheduler.sync(context, now)
        reminders = listOf(item("task:1", 30))  // the user chose 30 minutes
        ReminderScheduler.sync(context, now)
        assertEquals(listOf(now + 30 * 60_000), exactAlarms().map { it.triggerAtTime })
    }

    @Test
    fun `a reminder whose time has just passed fires at once`() {
        reminders = listOf(item("task:late", -5))
        ReminderScheduler.sync(context, now)
        assertEquals(listOf(now + 1_000), exactAlarms().map { it.triggerAtTime })
    }

    @Test
    fun `a sync also sets the check every half hour`() {
        ReminderScheduler.sync(context, now)
        assertTrue(alarms.scheduledAlarms.any { it.interval == 30L * 60 * 1000 })
    }

    @Test
    fun `the notification shows when the server still lists the reminder, and only once`() {
        val task = item("task:1", 0)
        reminders = listOf(task)
        ReminderScheduler.sync(context, now)
        ReminderScheduler.fire(context, task, now)
        val shown = notifications.allNotifications.single()
        assertEquals("Call Sam", shown.extras.getString(Notification.EXTRA_TITLE))
        assertEquals("Due at 14:30", shown.extras.getString(Notification.EXTRA_TEXT))
        ReminderScheduler.fire(context, task, now)  // a second alarm for the same reminder
        assertEquals(1, notifications.allNotifications.size)
        // A sync that lists it again does not set its alarm again. (The alarm that went off is
        // still in the shadow of the alarm manager, because this test calls fire itself.)
        val before = exactAlarms().size
        ReminderScheduler.sync(context, now)
        assertEquals(before, exactAlarms().size)
    }

    @Test
    fun `no notification shows when the server dropped the reminder`() {
        val task = item("task:1", 0)
        reminders = listOf(task)
        ReminderScheduler.sync(context, now)
        reminders = emptyList()  // the task is done, or the review is done
        ReminderScheduler.fire(context, task, now)
        assertTrue(notifications.allNotifications.isEmpty())
    }

    @Test
    fun `a reminder shows when the server cannot be reached`() {
        val task = item("task:1", 0)
        status = 500
        ReminderScheduler.fire(context, task, now)
        assertEquals(1, notifications.allNotifications.size)
    }

    @Test
    fun `a failed sync keeps the alarms and a sign out removes them`() {
        reminders = listOf(item("task:1", 15))
        ReminderScheduler.sync(context, now)
        status = 500
        ReminderScheduler.sync(context, now)
        assertEquals(1, exactAlarms().size)
        signIn(null, null)
        ReminderScheduler.sync(context, now)
        assertTrue(exactAlarms().isEmpty())
    }

    @Test
    fun `tapping the notification opens the link in the app`() {
        val review = ReminderItem(
            "weekly_review:2030-03-04", "weekly_review", "Time for your weekly review",
            "Look back", now, "/week/plan?date=2030-03-11",
        )
        reminders = listOf(review)
        ReminderScheduler.fire(context, review, now)
        val tap = notifications.allNotifications.single().contentIntent
        val intent = shadowOf(tap).savedIntent
        assertEquals("tefteri://app/week/plan?date=2030-03-11", intent.data.toString())
        assertNull(intent.type)
    }
}
