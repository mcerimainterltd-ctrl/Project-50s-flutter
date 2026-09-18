package com.xamepage.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.app.NotificationCompat
import java.net.HttpURLConnection
import java.net.URL

class NativePresenceService : Service() {

    companion object {
        const val ACTION_START = "com.xamepage.app.presence.START"
        const val ACTION_STOP = "com.xamepage.app.presence.STOP"
        const val EXTRA_TOKEN = "session_token"

        private const val CHANNEL_ID = "xamepage_presence"
        private const val NOTIFICATION_ID = 2003
        private const val PREFS = "xamepage_native_presence"
        private const val TOKEN_KEY = "session_token"
        private const val SERVER_URL = "https://project-50s.onrender.com"
        private const val REFRESH_MS = 3 * 60 * 1000L

        fun start(context: android.content.Context, token: String) {
            if (token.isBlank()) return

            context.getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .putString(TOKEN_KEY, token)
                .apply()

            val intent = Intent(context, NativePresenceService::class.java)
                .setAction(ACTION_START)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: android.content.Context) {
            context.getSharedPreferences(PREFS, MODE_PRIVATE)
                .edit()
                .remove(TOKEN_KEY)
                .apply()

            context.stopService(
                Intent(context, NativePresenceService::class.java)
                    .setAction(ACTION_STOP)
            )
        }
    }

    private val handler = android.os.Handler(android.os.Looper.getMainLooper())

    private val refreshRunnable = object : Runnable {
        override fun run() {
            refreshPresence()
            handler.postDelayed(this, REFRESH_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING
            } else {
                0
            }
        )
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        if (intent?.action == ACTION_STOP) {
            stopSelf()
            return START_NOT_STICKY
        }

        handler.removeCallbacks(refreshRunnable)
        refreshPresence()
        handler.postDelayed(refreshRunnable, REFRESH_MS)

        return START_STICKY
    }

    private fun refreshPresence() {
        Thread {
            val token = getSharedPreferences(PREFS, MODE_PRIVATE)
                .getString(TOKEN_KEY, null)

            if (token.isNullOrBlank()) {
                return@Thread
            }

            var connection: HttpURLConnection? = null

            try {
                val url = URL("$SERVER_URL/api/presence/heartbeat")
                connection = url.openConnection() as HttpURLConnection
                connection.requestMethod = "POST"
                connection.connectTimeout = 15000
                connection.readTimeout = 15000
                connection.doOutput = true
                connection.setRequestProperty(
                    "Content-Type",
                    "application/json"
                )

                val body =
                    """{"token":${org.json.JSONObject.quote(token)}}"""

                connection.outputStream.use { output ->
                    output.write(body.toByteArray(Charsets.UTF_8))
                }

                val code = connection.responseCode

                if (code == HttpURLConnection.HTTP_UNAUTHORIZED) {
                    handler.post { stopSelf() }
                }
            } catch (_: Exception) {
                // The server lease remains valid for seven minutes.
                // A later refresh will recover automatically.
            } finally {
                connection?.disconnect()
            }
        }.start()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager =
                getSystemService(NotificationManager::class.java)

            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "XamePage presence",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(
            this,
            CHANNEL_ID
        )
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("XamePage")
            .setContentText("Online presence is active")
            .setPriority(
                androidx.core.app.NotificationCompat.PRIORITY_LOW
            )
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
