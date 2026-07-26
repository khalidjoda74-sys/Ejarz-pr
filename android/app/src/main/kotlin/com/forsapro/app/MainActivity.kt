package com.forsapro.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterShellArgs

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        ensureActivityNotificationChannel()
    }

    private fun ensureActivityNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = getSystemService(NotificationManager::class.java)
        if (manager.getNotificationChannel(ACTIVITY_CHANNEL_ID) != null) return

        val channel = NotificationChannel(
            ACTIVITY_CHANNEL_ID,
            "تنبيهات فرصة برو",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "الرسائل والإشعارات الجديدة من فرصة برو"
            enableVibration(true)
            setShowBadge(true)
        }
        manager.createNotificationChannel(channel)
    }

    @Suppress("DEPRECATION")
    override fun getFlutterShellArgs(): FlutterShellArgs {
        val shellArgs = super.getFlutterShellArgs()
        val needsStableRenderer =
            Build.MANUFACTURER.equals("HUAWEI", ignoreCase = true) &&
                Build.VERSION.SDK_INT <= Build.VERSION_CODES.Q

        if (needsStableRenderer) {
            shellArgs.remove(FlutterShellArgs.ARG_ENABLE_IMPELLER)
            shellArgs.add(FlutterShellArgs.ARG_DISABLE_IMPELLER)
        }

        return shellArgs
    }

    private companion object {
        const val ACTIVITY_CHANNEL_ID = "majalisna_activity"
    }
}
