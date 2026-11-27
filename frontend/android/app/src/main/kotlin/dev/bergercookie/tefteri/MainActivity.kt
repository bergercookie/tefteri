package dev.bergercookie.tefteri

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import kotlin.concurrent.thread

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The app asks for the time zone of the phone, to tell it to the server.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.bergercookie.tefteri/device")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "timezone" -> result.success(java.util.TimeZone.getDefault().id)
                    else -> result.notImplemented()
                }
            }
        // The app tells the reminders to ask the server again (after a sign in, a change of the
        // settings or a start of the app), and asks for the permission to show notifications.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dev.bergercookie.tefteri/reminders")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "sync" -> {
                        val app = applicationContext
                        thread { ReminderScheduler.sync(app) }
                        result.success(null)
                    }
                    "requestPermission" -> {
                        val needed = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) !=
                            PackageManager.PERMISSION_GRANTED
                        if (needed) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 1)
                        result.success(needed)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
