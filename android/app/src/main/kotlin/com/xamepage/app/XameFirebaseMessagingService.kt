package com.xamepage.app

import android.app.*
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage

class XameFirebaseMessagingService : FirebaseMessagingService() {

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        val data       = message.data
        val type       = data["type"]       ?: return
        val callerName = data["callerName"] ?: "Unknown"
        val callType   = data["callType"]   ?: "voice"

        when (type) {
            "incoming_call" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // Android 12+: foreground service blocked from FCM background
                    // Show heads-up only — MainActivity starts CallService on resume
                    showHeadsUpNotification(callerName, callType)
                } else {
                    // Android 11 and below: start CallService first for wake lock + lock screen
                    CallService.start(this, callerName, callType)
                    showHeadsUpNotification(callerName, callType)
                }
            }
            "scheduled_call_due" -> {
                // Wake app so Flutter socket listener can fire the call
                val wakeIntent = Intent(this, MainActivity::class.java).apply {
                    flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                    action = "SCHEDULED_CALL_DUE"
                    putExtra("scheduleId",  data["scheduleId"]  ?: "")
                    putExtra("recipientId", data["recipientId"] ?: "")
                    putExtra("callType",    data["callType"]    ?: "voice")
                }
                startActivity(wakeIntent)
            }
            "call_ended" -> {
                CallService.stop(this)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
        // Token refresh handled by Flutter side
    }

    private fun showHeadsUpNotification(callerName: String, callType: String) {
        val channelId = CallService.CHANNEL_ID
        val isVideo   = callType == "video"

        // Full screen intent
        val fullScreenIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra("incoming_call", true)
            putExtra("caller_name",   callerName)
            putExtra("call_type",     callType)
        }
        val fullScreenPi = PendingIntent.getActivity(
            this, 0, fullScreenIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Answer
        val answerPi = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java).apply {
                action = CallService.ACTION_ANSWER
                flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("caller_name", callerName)
                putExtra("call_type",   callType)
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        // Decline
        val declinePi = PendingIntent.getActivity(
            this, 2,
            Intent(this, MainActivity::class.java).apply {
                action = CallService.ACTION_DECLINE
                flags  = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(callerName)
            .setContentText("Incoming ${if (isVideo) "Video" else "Voice"} Call · XamePage")
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setFullScreenIntent(fullScreenPi, true)
            .addAction(android.R.drawable.ic_menu_call, "Answer",  answerPi)
            .addAction(android.R.drawable.ic_delete,    "Decline", declinePi)
            .setContentIntent(fullScreenPi)
            .build()

        val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(CallService.NOTIF_ID + 1, notification)
    }
}
