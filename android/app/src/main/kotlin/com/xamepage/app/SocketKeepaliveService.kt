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
        const val CHANNEL_ID  = "xamepage_keepalive"
        const val NOTIF_ID    = 2001
        const val CHANNEL_NAME = "com.xamepage.app/keepalive"

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

    private val heartbeatRunnable = object : Runnable {
        override fun run() {
            pingFlutter()
            handler.postDelayed(this, 25_000L) // every 25 seconds
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())
        acquireWakeLock()
        handler.post(heartbeatRunnable)
    }

    private fun pingFlutter() {
        try {
            val engine: FlutterEngine? = FlutterEngineCache.getInstance().get("main")
            engine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL_NAME)
                    .invokeMethod("heartbeat", null)
            }
        } catch (e: Exception) {
            // Engine not ready yet — skip this beat
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
        ).apply { acquire(10 * 60 * 1000L) } // 10 min max
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY // restart if killed
    }

    override fun onDestroy() {
        handler.removeCallbacks(heartbeatRunnable)
        wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
