package com.xamepage.app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import io.socket.client.IO
import io.socket.client.Socket
import io.socket.engineio.client.transports.WebSocket

class PresenceService : Service() {

    companion object {
        const val CHANNEL_ID = "xamepage_presence"
        const val NOTIFICATION_ID = 2003

        private const val PREFS = "xamepage_presence"
        private const val KEY_USER_ID = "user_id"

        private const val ACTION_START = "com.xamepage.app.PRESENCE_START"
        private const val ACTION_STOP = "com.xamepage.app.PRESENCE_STOP"
        private const val EXTRA_USER_ID = "user_id"
        private const val EXTRA_SESSION_TOKEN = "session_token"
        private const val HEARTBEAT_INTERVAL_MS = 30_000L

        fun start(context: Context, userId: String, sessionToken: String) {
            if (userId.isBlank() || sessionToken.isBlank()) return

            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(KEY_USER_ID, userId)
                .apply()

            val intent = Intent(context, PresenceService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_USER_ID, userId)
                putExtra(EXTRA_SESSION_TOKEN, sessionToken)
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .remove(KEY_USER_ID)
                .apply()

            context.stopService(Intent(context, PresenceService::class.java))
        }
    }

    private var socket: Socket? = null
    private var currentUserId: String? = null
    private var currentSessionToken: String? = null

    private val heartbeatHandler = android.os.Handler(mainLooper)

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            val id = currentUserId ?: return
            if (socket?.connected() != true) return

            socket?.emit("heartbeat")
            heartbeatHandler.postDelayed(this, HEARTBEAT_INTERVAL_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                buildNotification(),
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(
                NOTIFICATION_ID,
                buildNotification()
            )
        }
    }

    override fun onStartCommand(
        intent: Intent?,
        flags: Int,
        startId: Int
    ): Int {
        when (intent?.action) {
            ACTION_STOP -> {
                stopPresence()
                return START_NOT_STICKY
            }

            ACTION_START -> {
                val userId = intent.getStringExtra(EXTRA_USER_ID)
                val token = intent.getStringExtra(EXTRA_SESSION_TOKEN)

                if (!userId.isNullOrBlank() && !token.isNullOrBlank()) {
                    startPresence(userId, token)
                }
            }

            else -> {
                // The service is intentionally not allowed to create an
                // unauthenticated socket after a process restart.
                stopSelf()
                return START_NOT_STICKY
            }
        }

        return START_STICKY
    }

    private fun startPresence(userId: String, sessionToken: String) {
        if (
            currentUserId == userId &&
            currentSessionToken == sessionToken &&
            socket?.connected() == true
        ) {
            emitOnline()
            return
        }

        stopSocketOnly()

        currentUserId = userId
        currentSessionToken = sessionToken

        val auth = mapOf<String, String>(
            "token" to sessionToken
        )

        val options = IO.Options.builder()
            .setForceNew(true)
            .setReconnection(true)
            .setReconnectionAttempts(Int.MAX_VALUE)
            .setReconnectionDelay(1000)
            .setReconnectionDelayMax(5000)
            .setTimeout(30000)
            .setTransports(arrayOf(WebSocket.NAME))
            .setPath("/socket.io/")
            .setQuery("userId=$userId")
            .setAuth(auth)
            .build()

        try {
            socket = IO.socket("https://app.xamepage.com", options)

            socket?.on(Socket.EVENT_CONNECT) {
                emitOnline()
            }

            socket?.on(Socket.EVENT_DISCONNECT) {
                // Native Socket.IO reconnection remains enabled.
            }

            socket?.on(Socket.EVENT_CONNECT_ERROR) {
                // Keep retrying through native Socket.IO reconnection.
            }

            socket?.connect()
        } catch (_: Exception) {
            socket = null
        }
    }

    private fun emitOnline() {
        if (currentUserId == null) return

        // Server derives identity from authenticated socket.userId.
        socket?.emit("user-online")
        startHeartbeat()
    }

    private fun startHeartbeat() {
        heartbeatHandler.removeCallbacks(heartbeatRunnable)
        heartbeatHandler.postDelayed(heartbeatRunnable, HEARTBEAT_INTERVAL_MS)
    }

    private fun stopPresence() {
        stopSocketOnly()
        stopSelf()
    }

    private fun stopSocketOnly() {
        heartbeatHandler.removeCallbacks(heartbeatRunnable)

        try {
            socket?.off()
            socket?.disconnect()
            socket?.close()
        } catch (_: Exception) {
        }

        socket = null
        currentUserId = null
        currentSessionToken = null
    }

    private fun buildNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("XamePage")
            .setContentText("You are online and available for messages and calls")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setCategory(NotificationCompat.CATEGORY_SERVICE)
            .setOngoing(true)
            .setShowWhen(false)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "XamePage Online Presence",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description =
                    "Keeps your XamePage messaging presence available while you are logged in"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }

            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    override fun onDestroy() {
        stopSocketOnly()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}
