package dev.bergercookie.tefteri

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import org.json.JSONObject

/**
 * Shows the reminders of the server as notifications.
 *
 * The server says what to remind and when (`GET /reminders`). This class sets one alarm for each
 * reminder, and shows the notification when the alarm goes off, unless the server has dropped the
 * reminder by then (the task is done, the review is done). It asks the server again every half
 * hour, when the app opens, and after a restart of the phone.
 */
object ReminderScheduler {
    const val ACTION_SYNC = "dev.bergercookie.tefteri.reminders.SYNC"
    const val ACTION_SHOW = "dev.bergercookie.tefteri.reminders.SHOW"
    const val CHANNEL = "reminders"

    private const val PREFS = "tefteri_reminders"
    private const val SCHEDULED = "scheduled"
    private const val FIRED = "fired"
    private const val LOOK_BACK_MINUTES = 10L
    private const val HOURS_AHEAD = 48
    private const val KEEP_FIRED_MILLIS = 3L * 24 * 60 * 60 * 1000
    private const val HALF_HOUR = 30L * 60 * 1000

    private val lock = Any()

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun read(context: Context, key: String): JSONObject =
        try {
            JSONObject(prefs(context).getString(key, "{}") ?: "{}")
        } catch (e: Exception) {
            JSONObject()
        }

    private fun write(context: Context, key: String, value: JSONObject) {
        prefs(context).edit().putString(key, value.toString()).apply()
    }

    /** Asks the server what to remind and sets the alarms. Blocks while it asks. */
    fun sync(context: Context, now: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            when (val result = ReminderData.fetch(context, now - LOOK_BACK_MINUTES * 60_000, HOURS_AHEAD)) {
                is ReminderResult.NotSignedIn -> cancelAll(context)
                is ReminderResult.Failed -> Unit // keep the alarms that are set
                is ReminderResult.Loaded -> apply(context, result.items, now)
            }
            schedulePeriodic(context)
        }
    }

    private fun apply(context: Context, items: List<ReminderItem>, now: Long) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val scheduled = read(context, SCHEDULED)
        val fired = read(context, FIRED)
        val wanted = items.filter { !fired.has(it.id) }.associateBy { it.id }
        // Drop the alarms of reminders that the server does not list any more.
        val stale = scheduled.keys().asSequence().filter { it !in wanted }.toList()
        for (id in stale) {
            cancel(context, alarms, id)
            scheduled.remove(id)
        }
        for ((id, item) in wanted) {
            if (scheduled.optLong(id, -1) == item.fireAt) continue
            // A reminder whose time has just passed (a task that was added late) fires at once.
            set(context, alarms, item, maxOf(item.fireAt, now + 1_000))
            scheduled.put(id, item.fireAt)
        }
        val keep = JSONObject()
        for (id in fired.keys()) {
            if (now - fired.optLong(id) < KEEP_FIRED_MILLIS) keep.put(id, fired.optLong(id))
        }
        write(context, SCHEDULED, scheduled)
        write(context, FIRED, keep)
    }

    private fun cancelAll(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val scheduled = read(context, SCHEDULED)
        for (id in scheduled.keys().asSequence().toList()) cancel(context, alarms, id)
        write(context, SCHEDULED, JSONObject())
    }

    private fun showIntent(context: Context, id: String): Intent =
        Intent(context, ReminderReceiver::class.java)
            .setAction(ACTION_SHOW)
            // The data makes the intent of each reminder different, so that each has its own alarm.
            .setData(Uri.parse("tefteri-reminder:${Integer.toHexString(id.hashCode())}"))

    private fun set(context: Context, alarms: AlarmManager, item: ReminderItem, at: Long) {
        val intent = showIntent(context, item.id)
            .putExtra("id", item.id)
            .putExtra("kind", item.kind)
            .putExtra("title", item.title)
            .putExtra("body", item.body)
            .putExtra("fireAt", item.fireAt)
            .putExtra("link", item.link)
        val pending = PendingIntent.getBroadcast(
            context,
            item.id.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val exact = Build.VERSION.SDK_INT < Build.VERSION_CODES.S || alarms.canScheduleExactAlarms()
        if (exact) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        } else {
            // Without the permission for exact alarms, the phone may delay the alarm a little.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, pending)
        }
    }

    private fun cancel(context: Context, alarms: AlarmManager, id: String) {
        val pending = PendingIntent.getBroadcast(
            context,
            id.hashCode(),
            showIntent(context, id),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarms.cancel(pending)
        pending.cancel()
    }

    /** Asks the server again every half hour, also when the app is closed. */
    fun schedulePeriodic(context: Context) {
        val alarms = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pending = PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ReminderReceiver::class.java).setAction(ACTION_SYNC),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        alarms.setInexactRepeating(
            AlarmManager.RTC,
            System.currentTimeMillis() + HALF_HOUR,
            HALF_HOUR,
            pending,
        )
    }

    /**
     * The alarm of [item] went off. The notification is shown unless the server has dropped the
     * reminder since (the task is done, the review is done). With no answer from the server, it is
     * shown, because a late reminder is better than none.
     */
    fun fire(context: Context, item: ReminderItem, now: Long = System.currentTimeMillis()) {
        synchronized(lock) {
            if (read(context, FIRED).has(item.id)) return
            val still = ReminderData.fetch(context, item.fireAt - 2 * 60_000, 1)
            val dropped = when (still) {
                is ReminderResult.Loaded -> still.items.none { it.id == item.id }
                is ReminderResult.NotSignedIn -> true
                is ReminderResult.Failed -> false
            }
            val scheduled = read(context, SCHEDULED)
            scheduled.remove(item.id)
            write(context, SCHEDULED, scheduled)
            if (dropped) return
            show(context, item)
            val fired = read(context, FIRED)
            fired.put(item.id, now)
            write(context, FIRED, fired)
        }
    }

    private fun show(context: Context, item: ReminderItem) {
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL,
                    context.getString(R.string.reminders_channel),
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = context.getString(R.string.reminders_channel_description) },
            )
        }
        val open = Intent(Intent.ACTION_VIEW, Uri.parse("tefteri://app${item.link}"))
            .setClass(context, MainActivity::class.java)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        val tap = PendingIntent.getActivity(
            context,
            item.id.hashCode(),
            open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(context, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(context).setPriority(Notification.PRIORITY_HIGH)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_stat_reminder)
            .setContentTitle(item.title)
            .setContentText(item.body)
            .setStyle(Notification.BigTextStyle().bigText(item.body))
            .setContentIntent(tap)
            .setAutoCancel(true)
            .setCategory(Notification.CATEGORY_REMINDER)
            .setWhen(item.fireAt)
            .build()
        // The same id replaces a notification that is there, so a reminder never shows twice.
        manager.notify(item.id.hashCode(), notification)
    }
}
