package com.xamepage.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.os.*
import android.content.pm.ServiceInfo
import androidx.core.app.NotificationCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class SocketKeepaliveService : Service() {

    companion object {
        const val CHANNEL_ID   = "xamepage_keepalive"
        const val NOTIF_ID     = 2001
        const val CHANNEL_NAME = "com.xamepage.app/keepalive"
        const val PREFS_NAME   = "FlutterSharedPreferences"
        const val PREFS_KEY    = "flutter.xamepage_user_id"

        fun start(context: Context, userId: String? = null) {
            if (!userId.isNullOrBlank()) {
                context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    .edit()
                    .putString(PREFS_KEY, userId)
                    .apply()
            }

            val intent = Intent(context, SocketKeepaliveService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                context.startForegroundService(intent)
            else
                context.startService(intent)
        }

        fun stop(context: Context) {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .remove(PREFS_KEY)
                .apply()
            context.stopService(Intent(context, SocketKeepaliveService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private var wakeLock: PowerManager.WakeLock? = null

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            renewWakeLock()
            pingFlutter()
            handler.postDelayed(this, 25_000L)
        }
    }

    override fun onCreate() {
        super.onCreate()

        val userId = getSharedPreferences(PREFS_NAME, MODE_PRIVATE)
            .getString(PREFS_KEY, null)

        if (userId.isNullOrBlank()) {
            stopSelf()
            return
        }

        createNotificationChannel()

        val notification = buildNotification()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIF_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIF_ID, notification)
        }

        acquireWakeLock()
        handler.post(heartbeatRunnable)
    }

    private fun pingFlutter() {
        val engine = getOrCreateFlutterEngine() ?: return

        try {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL_NAME)
                .invokeMethod("heartbeat", null)
        } catch (_: Exception) {
            // Flutter engine temporarily unavailable.
        }
    }

    private fun getOrCreateFlutterEngine(): FlutterEngine? {
        FlutterEngineCache.getInstance().get("main")?.let {
            return it
        }

        return try {
            val engine = FlutterEngine(applicationContext)

            FlutterEngineCache.getInstance().put("main", engine)

            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault()
            )

            engine
        } catch (_: Exception) {
            null
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager

        if (wakeLock?.isHeld == true) return

        wakeLock = pm.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "xamepage:SocketKeepalive"
        ).apply {
            acquire(12 * 60 * 60 * 1000L)
        }
    }

    private fun renewWakeLock() {
        if (wakeLock?.isHeld != true) {
            acquireWakeLock()
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
            .setContentText("XamePage is connected and ready for calls")
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

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        renewWakeLock()
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        wakeLock?.release()
        wakeLock = null
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
