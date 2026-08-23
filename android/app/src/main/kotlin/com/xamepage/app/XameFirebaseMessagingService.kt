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
                // Show full-screen heads-up notification on all Android versions
                showHeadsUpNotification(callerName, callType)
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
                    // Android 11 and below: start CallService for wake lock + lock screen
                    CallService.start(this, callerName, callType)
                } else {
                    // Android 12+: wake Flutter engine via SocketKeepaliveService
                    SocketKeepaliveService.start(this)
                }
            }
            "scheduled_call_due" -> {
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
            "contact_request" -> {
                val fromName = data["fromName"] ?: "Someone"
                showAlertNotification("👤 Contact Request", "$fromName wants to connect with you")
            }
            "wallet_request" -> {
                val fromName = data["fromName"] ?: "Someone"
                val amount   = data["amount"]   ?: ""
                val currency = data["currency"] ?: ""
                showAlertNotification("🙏 Payment Request", "$fromName is requesting $currency $amount")
            }
            "wallet_credit" -> {
                val message = data["message"] ?: "Your wallet has been credited"
                showAlertNotification("💰 Wallet Credited", message)
            }
            "wallet_debit" -> {
                val message = data["message"] ?: "A debit was made from your wallet"
                showAlertNotification("💸 Wallet Debited", message)
            }
        }
    }

    override fun onNewToken(token: String) {
        super.onNewToken(token)
    }

    private fun showAlertNotification(title: String, body: String) {
        val channelId = "xamepage_alerts"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId, "XamePage Alerts", NotificationManager.IMPORTANCE_HIGH
            ).apply {
                setShowBadge(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 200)
            }
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        val pi = PendingIntent.getActivity(this, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val notification = NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        mgr.notify(System.currentTimeMillis().toInt(), notification)
    }

    private fun showHeadsUpNotification(callerName: String, callType: String) {
        val channelId = "xamepage_headsup_v3"
        val isVideo   = callType == "video"

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                channelId,
                "XamePage Calls",
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
                setShowBadge(true)
                enableVibration(true)
                vibrationPattern = longArrayOf(0, 400, 200, 400)
                // Silent — XamePage plays its own ringtone via AudioService
                setSound(null, null)
            }
            val mgr = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            mgr.createNotificationChannel(channel)
        }

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
