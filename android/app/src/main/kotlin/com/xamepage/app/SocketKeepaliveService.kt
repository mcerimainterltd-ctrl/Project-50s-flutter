package com.xamepage.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.*
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class SocketKeepaliveService : Service() {

    companion object {
        const val CHANNEL_ID   = "xamepage_keepalive"
        const val NOTIF_ID     = 2001
        const val CHANNEL_NAME = "com.xamepage.app/keepalive"
        const val PREFS_NAME   = "FlutterSharedPreferences"
        const val PREFS_KEY    = "flutter.xamepage_user_id"

        fun start(context: Context) {
            val intent = Intent(context, SocketKeepaliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(intent)
            else
                context.startService(intent)
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, SocketKeepaliveService::class.java))
        }
    }

    private val handler  = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null
    private var engineLaunchAttempted = false

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            pingFlutter()
            handler.postDelayed(this, 25_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        acquireWakeLock()
        handler.post(heartbeatRunnable)
    }

    private fun getSavedUserId(): String? {
        // Flutter stores SharedPreferences with "flutter." prefix
        val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        return prefs.getString(PREFS_KEY, null)
    }

    private fun pingFlutter() {
        if (wakeLock?.isHeld == false) acquireWakeLock()
        val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("main")
        if (engine != null) {
            // Flutter engine is running — send heartbeat
            engineLaunchAttempted = false
            try {
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                    .invokeMethod("heartbeat", null)
            } catch (e: Exception) {
                // Engine not ready yet — skip this beat
            }
        } else if (!engineLaunchAttempted) {
            // Engine not running — check if user is logged in
            val userId = getSavedUserId()
            if (!userId.isNullOrEmpty()) {
                // Launch app to initialize Flutter engine and connect socket
                engineLaunchAttempted = true
                try {
                    val launchIntent = Intent(this, MainActivity::class.java).apply {
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
                        putExtra("boot_launch", true)
                    }
                    startActivity(launchIntent)
                } catch (e: Exception) {
                    engineLaunchAttempted = false
                }
            }
            // If no userId saved, user is not logged in — skip silently
        }
    }

    private fun buildNotification(): Notification {
        val openIntent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("XamePage")
            .setContentText("Connected — ready for calls")
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOngoing(true)
            .setShowWhen(false)
            .setContentIntent(openIntent)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID, "Connection Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description    = "Keeps XamePage connected for calls"
                setShowBadge(false)
                enableVibration(false)
                setSound(null, null)
            }
            (getSystemService(NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "xamepage:SocketKeepalive"
        ).apply { acquire(12 * 60 * 60 * 1000L) }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
