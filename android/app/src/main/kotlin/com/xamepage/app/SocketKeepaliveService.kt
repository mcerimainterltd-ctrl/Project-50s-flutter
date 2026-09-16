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

    private val handler = Handler(Looper.getMainLooper())
    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIF_ID, buildNotification())

        // This service is a short-lived wake bridge for FCM incoming calls.
        // SocketService remains the single Socket.IO owner.
        handler.post {
            pingFlutter()
            handler.postDelayed({
                stopSelf()
            }, 15_000L)
        }
    }

    private fun pingFlutter() {
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
        } else {
            // Flutter is not running. Do not launch an Activity from the
            // background. The incoming-call notification/full-screen intent
            // is responsible for bringing the call UI forward.
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
            .setContentText("Preparing XamePage call")
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
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
