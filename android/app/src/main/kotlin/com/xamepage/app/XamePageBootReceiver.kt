package com.xamepage.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class XamePageBootReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val prefs = context.getSharedPreferences(
                    SocketKeepaliveService.PREFS_NAME,
                    Context.MODE_PRIVATE
                )

                val userId = prefs.getString(
                    SocketKeepaliveService.PREFS_KEY,
                    null
                )

                if (!userId.isNullOrBlank()) {
                    SocketKeepaliveService.start(context, userId)
                }
            }
        }
    }
}
