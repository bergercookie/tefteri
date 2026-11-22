package dev.bergercookie.tefteri

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import kotlin.concurrent.thread

/** Gets the half-hourly check and the alarm of each reminder. */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        when (intent.action) {
            ReminderScheduler.ACTION_SYNC -> background { ReminderScheduler.sync(app) }
            ReminderScheduler.ACTION_SHOW -> {
                val id = intent.getStringExtra("id") ?: return
                val item = ReminderItem(
                    id = id,
                    kind = intent.getStringExtra("kind") ?: "",
                    title = intent.getStringExtra("title") ?: "",
                    body = intent.getStringExtra("body") ?: "",
                    fireAt = intent.getLongExtra("fireAt", System.currentTimeMillis()),
                    link = intent.getStringExtra("link") ?: "/",
                )
                background { ReminderScheduler.fire(app, item) }
            }
        }
    }

    /** The server is asked on another thread. The receiver stays alive until that is done. */
    private fun background(work: () -> Unit) {
        val pending = goAsync()
        thread {
            try {
                work()
            } finally {
                pending?.finish()
            }
        }
    }
}

/** Sets the reminders again after the phone started or the app was updated. */
class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val app = context.applicationContext
        val pending = goAsync()
        thread {
            try {
                ReminderScheduler.sync(app)
            } finally {
                pending?.finish()
            }
        }
    }
}
