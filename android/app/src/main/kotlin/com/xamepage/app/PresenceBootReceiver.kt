package com.xamepage.app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class PresenceBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return

        val token = context
            .getSharedPreferences("xamepage_native_presence", Context.MODE_PRIVATE)
            .getString("session_token", null)

        if (!token.isNullOrBlank()) {
            NativePresenceService.start(context, token)
        }
    }
}
