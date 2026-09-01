package com.zkv.sensmos

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Kanał IMPORTANCE_HIGH: bez niego FCM ląduje w kanale domyślnym (DEFAULT), a Android
        // pokazuje wtedy tylko dźwięk + ikonę w pasku — BEZ pływającego banera (heads-up).
        // BE wskazuje channelId "alerts" w payloadzie; manifest ma go jako default.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                "alerts", "Alerts", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Node emergency and alerts"
                enableVibration(true)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }
}
