package cc.nexvision.sip_phone_app

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build

class Application : Application() {
    override fun onCreate() {
        super.onCreate()
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)

            // Background service channel — must exist in EVERY process (incl. WatchdogReceiver)
            // so Android can post the required foreground service notification without crashing.
            manager.createNotificationChannel(
                NotificationChannel(
                    "nexvision_sip_bg",
                    "Nexvision SIP Background Service",
                    NotificationManager.IMPORTANCE_LOW
                ).apply {
                    description = "Keeps Nexvision SIP alive in background for incoming calls"
                    setShowBadge(false)
                }
            )

            // Calls channel (for CallKit incoming call notifications)
            manager.createNotificationChannel(
                NotificationChannel(
                    "sip_calls_channel",
                    "Incoming Calls",
                    NotificationManager.IMPORTANCE_HIGH
                ).apply {
                    description = "Incoming SIP call alerts"
                }
            )
        }
    }
}
