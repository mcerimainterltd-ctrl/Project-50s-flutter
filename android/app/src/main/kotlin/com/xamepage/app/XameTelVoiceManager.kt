package com.xamepage.app

import android.content.Context
import android.util.Log
import com.twilio.voice.CallInvite
import com.twilio.voice.CancelledCallInvite
import com.twilio.voice.MessageListener
import com.twilio.voice.Voice

object XameTelVoiceManager {

    private const val TAG = "XameTelVoice"

    @Volatile
    private var pendingInvite: CallInvite? = null

    fun handleIncomingMessage(
        context: Context,
        data: Map<String, String>
    ): Boolean {
        return try {
            Voice.handleMessage(
                context,
                data,
                object : MessageListener {

                    override fun onCallInvite(callInvite: CallInvite) {
                        pendingInvite = callInvite

                        Log.i(
                            TAG,
                            "Incoming XameTel CallInvite: ${callInvite.callSid}"
                        )

                        context.getSharedPreferences(
                            "xamepage_native_presence",
                            Context.MODE_PRIVATE
                        ).edit()
                            .putLong(
                                "diag_last_xametel_invite",
                                System.currentTimeMillis()
                            )
                            .putString(
                                "diag_last_xametel_call_sid",
                                callInvite.callSid
                            )
                            .apply()
                    }

                    override fun onCancelledCallInvite(
                        cancelledCallInvite: CancelledCallInvite,
                        callException: com.twilio.voice.CallException?
                    ) {
                        val callSid = cancelledCallInvite.callSid

                        if (pendingInvite?.callSid == callSid) {
                            pendingInvite = null
                        }

                        Log.i(
                            TAG,
                            "XameTel CallInvite cancelled: $callSid"
                        )
                    }
                }
            )
        } catch (e: Exception) {
            Log.e(
                TAG,
                "Failed to process Twilio Voice message",
                e
            )
            false
        }
    }

    fun getPendingInvite(): CallInvite? = pendingInvite

    fun clearPendingInvite(callSid: String? = null) {
        if (callSid == null || pendingInvite?.callSid == callSid) {
            pendingInvite = null
        }
    }
}
