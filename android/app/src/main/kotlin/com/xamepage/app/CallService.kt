package com.xamepage.app

import android.app.*
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.*
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class CallService : Service() {

    companion object {
        const val CHANNEL_ID       = "xamepage_call_v3"
        const val NOTIF_ID         = 1001
        const val ACTION_ANSWER    = "ACTION_ANSWER"
        const val ACTION_DECLINE   = "ACTION_DECLINE"
        const val ACTION_VIEW_INCOMING_CALL = "ACTION_VIEW_INCOMING_CALL"
        const val EXTRA_CALLER     = "caller_name"
        const val EXTRA_CALL_TYPE  = "call_type"
        const val EXTRA_CALLER_ID  = "caller_id"

        // CALLSVC_A14_V1: Android 14 forbids starting a microphone-type foreground
        // service from the background. Ringing (started from a push) therefore uses
        // PHONE_CALL only; the microphone type is added once the user acts on the call.
        const val EXTRA_WITH_MIC     = "with_mic"
        const val EXTRA_UPGRADE_MIC  = "upgrade_mic"

        @Volatile private var running = false

        fun start(context: Context, callerName: String, callType: String, callerId: String = "", withMic: Boolean = false) {
            val intent = Intent(context, CallService::class.java).apply {
                putExtra(EXTRA_CALLER,    callerName)
                putExtra(EXTRA_CALL_TYPE, callType)
                putExtra(EXTRA_CALLER_ID, callerId)
                putExtra(EXTRA_WITH_MIC,  withMic)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.startForegroundService(intent)
                else
                    context.startService(intent)
            } catch (e: Exception) {
                android.util.Log.e("CallService", "start refused", e)
            }
        }

        fun upgradeToMicrophone(context: Context) {
            if (!running) return
            val intent = Intent(context, CallService::class.java).apply {
                putExtra(EXTRA_UPGRADE_MIC, true)
            }
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O)
                    context.startForegroundService(intent)
                else
                    context.startService(intent)
            } catch (e: Exception) {
                android.util.Log.w("CallService", "mic upgrade refused", e)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CallService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        acquireWakeLock()
    }

    private var curCaller   = "Unknown"
    private var curCallType = "voice"
    private var curCallerId = ""

    private fun micGranted(): Boolean =
        androidx.core.content.ContextCompat.checkSelfPermission(
            this, android.Manifest.permission.RECORD_AUDIO
        ) == android.content.pm.PackageManager.PERMISSION_GRANTED

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // CALLSVC_A14_V1
        val upgrade = intent?.getBooleanExtra(EXTRA_UPGRADE_MIC, false) == true
        if (!upgrade) {
            curCaller   = intent?.getStringExtra(EXTRA_CALLER)    ?: "Unknown"
            curCallType = intent?.getStringExtra(EXTRA_CALL_TYPE) ?: "voice"
            curCallerId = intent?.getStringExtra(EXTRA_CALLER_ID) ?: ""
        }
        val wantMic = upgrade || intent?.getBooleanExtra(EXTRA_WITH_MIC, false) == true
        val notif = buildNotification(curCaller, curCallType, curCallerId)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val phone = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
            val mic   = android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE
            var started = false
            if (wantMic && micGranted()) {
                try {
                    startForeground(NOTIF_ID, notif, phone or mic)
                    started = true
                } catch (e: Exception) {
                    android.util.Log.w("CallService", "microphone type refused, using phone-call only", e)
                }
            }
            if (!started) {
                try {
                    startForeground(NOTIF_ID, notif, phone)
                } catch (e: Exception) {
                    android.util.Log.e("CallService", "startForeground failed", e)
                    stopSelf()
                    return START_NOT_STICKY
                }
            }
        } else {
            startForeground(NOTIF_ID, notif)
        }
        running = true
        return START_NOT_STICKY
    }

    private fun buildNotification(caller: String, callType: String, callerId: String): Notification {
        val isVideo = callType == "video"

        // Full screen intent — shows on lock screen
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_VIEW_INCOMING_CALL
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incoming_call", true)
            putExtra("caller_id",   callerId)
            putExtra("caller_name", caller)
            putExtra("call_type",   callType)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, 0, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Answer action
        val answerIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_ANSWER
            flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("caller_name", caller)
            putExtra("call_type",   callType)
            putExtra("caller_id",   callerId)
        }
        val answerPi = PendingIntent.getActivity(
            this, 1, answerIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Decline action
        val declineIntent = Intent(this, MainActivity::class.java).apply {
            action = ACTION_DECLINE
            flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val declinePi = PendingIntent.getActivity(
            this, 2, declineIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(caller)
            .setContentText("Incoming ${if (isVideo) "Video" else "Voice"} Call")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPi, true)
            .addAction(android.R.drawable.ic_menu_call, "Answer", answerPi)
            .addAction(android.R.drawable.ic_delete,    "Decline", declinePi)
            .setContentIntent(fullScreenPi)
            .build()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Incoming Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description       = "XamePage incoming call notifications"
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                enableVibration(true)
                vibrationPattern  = longArrayOf(0, 500, 200, 500)
                // Silent — XamePage plays its own ringtone via AudioService
                setSound(null, null)
            }
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }
    }

    private fun acquireWakeLock() {
        val pm = getSystemService(POWER_SERVICE) as PowerManager
        wakeLock = pm.newWakeLock(
            PowerManager.SCREEN_BRIGHT_WAKE_LOCK or
            PowerManager.ACQUIRE_CAUSES_WAKEUP or
            PowerManager.ON_AFTER_RELEASE,
            "xamepage:IncomingCall"
        ).apply { acquire(60_000L) }
    }

    override fun onDestroy() {
        running = false
        wakeLock?.release()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?) = null
}
