package com.xamepage.app

import android.app.*
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.Person
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
                // Show heads-up notification immediately
                showHeadsUpNotification(callerName, callType)
                // Start foreground service — FCM high-priority messages are exempt
                // from Android 12+ background start restrictions
                try {
                    CallService.start(this, callerName, callType)
                } catch (_: Exception) {
                    // If blocked (rare), notification already shown above
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
        val channelId = "xamepage_headsup_v2"
        val isVideo   = callType == "video"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "XamePage Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                lockscreenVisibility    = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                enableVibration(true)
                vibrationPattern        = longArrayOf(0, 400, 200, 400)
                setSound(
                    RingtoneManager.getDefaultUri(RingtoneManager.TYPE_RINGTONE),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }

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

        val caller_person = Person.Builder()
            .setName(callerName)
            .setImportant(true)
            .build()

        val builder = NotificationCompat.Builder(this, channelId)
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

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder.setStyle(NotificationCompat.CallStyle.forIncomingCall(
                caller_person, declinePi, answerPi))
        }

        val notification = builder.build()

        val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(CallService.NOTIF_ID + 1, notification)
    }
}
