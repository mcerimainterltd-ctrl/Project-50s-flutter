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
        private const val DIAG_STARTED = "diag_started"
        private const val DIAG_TASK_REMOVED = "diag_task_removed"
        private const val DIAG_DESTROYED = "diag_destroyed"
        private const val DIAG_LAST_HEARTBEAT = "diag_last_heartbeat"
        private const val DIAG_LAST_RESPONSE = "diag_last_response"
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

    private var lastNetRefresh = 0L
    private var netCallback: android.net.ConnectivityManager.NetworkCallback? = null

    private fun heartbeatAlarmIntent(): android.app.PendingIntent {
        val i = Intent(this, NativePresenceService::class.java).setAction(ACTION_START)
        val flags = android.app.PendingIntent.FLAG_UPDATE_CURRENT or
            android.app.PendingIntent.FLAG_IMMUTABLE
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            android.app.PendingIntent.getForegroundService(this, 7101, i, flags)
        } else {
            android.app.PendingIntent.getService(this, 7101, i, flags)
        }
    }

    private fun scheduleHeartbeatAlarm() {
        try {
            val am = getSystemService(android.content.Context.ALARM_SERVICE)
                as android.app.AlarmManager
            val at = android.os.SystemClock.elapsedRealtime() + REFRESH_MS
            val pi = heartbeatAlarmIntent()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                try {
                    am.setExactAndAllowWhileIdle(
                        android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                } catch (e: SecurityException) {
                    am.setAndAllowWhileIdle(
                        android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
                }
            } else {
                am.set(android.app.AlarmManager.ELAPSED_REALTIME_WAKEUP, at, pi)
            }
        } catch (e: Exception) {
        }
    }

    private fun cancelHeartbeatAlarm() {
        try {
            val am = getSystemService(android.content.Context.ALARM_SERVICE)
                as android.app.AlarmManager
            am.cancel(heartbeatAlarmIntent())
        } catch (e: Exception) {
        }
    }

    private fun registerNetCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N || netCallback != null) return
        try {
            val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE)
                as android.net.ConnectivityManager
            val cb = object : android.net.ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: android.net.Network) {
                    val now = System.currentTimeMillis()
                    if (now - lastNetRefresh < 10000L) return
                    lastNetRefresh = now
                    handler.post { refreshPresence() }
                }
            }
            cm.registerDefaultNetworkCallback(cb)
            netCallback = cb
        } catch (e: Exception) {
        }
    }

    private fun unregisterNetCallback() {
        val cb = netCallback ?: return
        try {
            val cm = getSystemService(android.content.Context.CONNECTIVITY_SERVICE)
                as android.net.ConnectivityManager
            cm.unregisterNetworkCallback(cb)
        } catch (e: Exception) {
        }
        netCallback = null
    }

    private val refreshRunnable = object : Runnable {
        override fun run() {
            refreshPresence()
            handler.postDelayed(this, REFRESH_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()

        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putLong(DIAG_STARTED, System.currentTimeMillis())
            .putLong(DIAG_DESTROYED, 0L)
            .apply()

        createNotificationChannel()

        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            buildNotification(),
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
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
            cancelHeartbeatAlarm()
            unregisterNetCallback()
            stopSelf()
            return START_NOT_STICKY
        }

        handler.removeCallbacks(refreshRunnable)
        refreshPresence()
        handler.postDelayed(refreshRunnable, REFRESH_MS)
        scheduleHeartbeatAlarm()
        registerNetCallback()

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

                val heartbeatTime = System.currentTimeMillis()

                getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putLong(DIAG_LAST_HEARTBEAT, heartbeatTime)
                    .putInt(DIAG_LAST_RESPONSE, code)
                    .apply()

                if (code == HttpURLConnection.HTTP_OK) {
                    val time = java.text.SimpleDateFormat(
                        "HH:mm:ss",
                        java.util.Locale.getDefault()
                    ).format(java.util.Date(heartbeatTime))

                    handler.post {
                        updatePresenceNotification(
                            "Presence heartbeat: $time"
                        )
                    }
                }

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

    private fun updatePresenceNotification(text: String) {
        val manager = getSystemService(NotificationManager::class.java)
        manager.notify(
            NOTIFICATION_ID,
            NotificationCompat.Builder(this, CHANNEL_ID)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle("XamePage")
                .setContentText(text)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setOngoing(true)
                .setShowWhen(false)
                .build()
        )
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

    override fun onTaskRemoved(rootIntent: Intent?) {
        val taskRemovedTime = System.currentTimeMillis()

        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putLong(DIAG_TASK_REMOVED, taskRemovedTime)
            .apply()

        updatePresenceNotification("Task removed — monitoring presence")

        // The XamePage task was swiped from Recents.
        // Keep the authenticated foreground presence service alive.
        val token = getSharedPreferences(PREFS, MODE_PRIVATE)
            .getString(TOKEN_KEY, null)

        if (!token.isNullOrBlank()) {
            handler.removeCallbacks(refreshRunnable)
            refreshPresence()
            handler.postDelayed(refreshRunnable, REFRESH_MS)
        }

        super.onTaskRemoved(rootIntent)
    }

    override fun onDestroy() {
        getSharedPreferences(PREFS, MODE_PRIVATE)
            .edit()
            .putLong(DIAG_DESTROYED, System.currentTimeMillis())
            .apply()

        val tk = getSharedPreferences(PREFS, MODE_PRIVATE).getString(TOKEN_KEY, null)
        if (tk.isNullOrBlank()) cancelHeartbeatAlarm()
        unregisterNetCallback()
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
