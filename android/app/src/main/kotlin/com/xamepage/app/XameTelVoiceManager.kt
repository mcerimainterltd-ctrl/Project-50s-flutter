package com.xamepage.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.twilio.voice.Call
import com.twilio.voice.CallInvite
import com.twilio.voice.CancelledCallInvite
import com.twilio.voice.MessageListener
import com.twilio.voice.Voice
import io.flutter.plugin.common.MethodChannel
import java.util.ArrayDeque

object XameTelVoiceManager {

    private const val TAG = "XameTelVoice"
    private const val MAX_PENDING_EVENTS = 16

    private val mainHandler = Handler(Looper.getMainLooper())
    private val lock = Any()
    private val pendingEvents = ArrayDeque<Map<String, Any?>>()

    @Volatile
    private var pendingInvite: CallInvite? = null

    @Volatile
    private var activeCall: Call? = null

    @Volatile
    private var applicationContext: Context? = null

    @Volatile
    private var flutterChannel: MethodChannel? = null

    @Volatile
    private var flutterReady = false

    fun attachFlutterChannel(channel: MethodChannel) {
        flutterChannel = channel
        flutterReady = false

        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "xametelReady" -> {
                    flutterReady = true
                    flushPendingEvents()
                    result.success(true)
                }

                "acceptIncomingCall" -> {
                    val callSid = call.argument<String>("callSid")
                    result.success(acceptIncomingCall(callSid))
                }

                "rejectIncomingCall" -> {
                    val callSid = call.argument<String>("callSid")
                    result.success(rejectIncomingCall(callSid))
                }

                "disconnectActiveCall" -> {
                    val callSid = call.argument<String>("callSid")
                    result.success(disconnectActiveCall(callSid))
                }

                "registerForIncomingCalls" -> {
                    val accessToken = call.argument<String>("accessToken")
                    val fcmToken = call.argument<String>("fcmToken")

                    if (accessToken.isNullOrBlank() || fcmToken.isNullOrBlank()) {
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    try {
                        Voice.register(
                            accessToken,
                            Voice.RegistrationChannel.FCM,
                            fcmToken,
                            object : com.twilio.voice.RegistrationListener {
                                override fun onRegistered(
                                    registeredAccessToken: String,
                                    registeredFcmToken: String
                                ) {
                                    Log.i(TAG, "XameTel FCM registration successful")
                                    result.success(true)
                                }

                                override fun onError(
                                    registrationException: com.twilio.voice.RegistrationException,
                                    failedAccessToken: String,
                                    failedFcmToken: String
                                ) {
                                    Log.e(
                                        TAG,
                                        "XameTel FCM registration failed: " +
                                            registrationException.message,
                                        registrationException
                                    )
                                    result.success(false)
                                }
                            }
                        )
                    } catch (e: Exception) {
                        Log.e(
                            TAG,
                            "Failed to start XameTel FCM registration",
                            e
                        )
                        result.success(false)
                    }
                }

                else -> result.notImplemented()
            }
        }

        Log.i(TAG, "Flutter channel attached")
    }

    fun detachFlutterChannel(channel: MethodChannel) {
        if (flutterChannel === channel) {
            flutterReady = false
            flutterChannel = null
            Log.i(TAG, "Flutter channel detached")
        }
    }

    fun handleIncomingMessage(
        context: Context,
        data: Map<String, String>
    ): Boolean {
        applicationContext = context.applicationContext

        return try {
            Voice.handleMessage(
                context,
                data,
                object : MessageListener {
                    override fun onCallInvite(callInvite: CallInvite) {
                        pendingInvite = callInvite

                        val event = mapOf<String, Any?>(
                            "event" to "incoming_call",
                            "callSid" to callInvite.callSid,
                            "from" to callInvite.from,
                            "to" to callInvite.to
                        )

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

                        publishEvent(event)
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

                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_cancelled",
                                "callSid" to callSid
                            )
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

    private fun acceptIncomingCall(callSid: String?): Boolean {
        val invite = pendingInvite ?: return false
        if (!callSid.isNullOrBlank() && invite.callSid != callSid) return false

        val context = applicationContext ?: return false

        return try {
            invite.accept(
                context,
                object : Call.Listener {
                    override fun onRinging(call: Call) {
                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_ringing",
                                "callSid" to call.sid
                            )
                        )

                        Log.i(
                            TAG,
                            "XameTel call ringing: ${call.sid}"
                        )
                    }

                    override fun onConnected(call: Call) {
                        activeCall = call
                        pendingInvite = null

                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_connected",
                                "callSid" to call.sid
                            )
                        )

                        Log.i(
                            TAG,
                            "XameTel call connected: ${call.sid}"
                        )
                    }

                    override fun onConnectFailure(
                        call: Call,
                        callException: com.twilio.voice.CallException
                    ) {
                        if (activeCall?.sid == call.sid) {
                            activeCall = null
                        }

                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_error",
                                "callSid" to call.sid,
                                "message" to callException.message
                            )
                        )

                        Log.e(
                            TAG,
                            "XameTel call connection failed: ${call.sid}",
                            callException
                        )
                    }

                    override fun onDisconnected(
                        call: Call,
                        callException: com.twilio.voice.CallException?
                    ) {
                        if (activeCall?.sid == call.sid) {
                            activeCall = null
                        }

                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_disconnected",
                                "callSid" to call.sid
                            )
                        )

                        Log.i(
                            TAG,
                            "XameTel call disconnected: ${call.sid}"
                        )
                    }

                    override fun onReconnecting(
                        call: Call,
                        callException: com.twilio.voice.CallException
                    ) {
                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_reconnecting",
                                "callSid" to call.sid
                            )
                        )
                    }

                    override fun onReconnected(call: Call) {
                        publishEvent(
                            mapOf<String, Any?>(
                                "event" to "call_reconnected",
                                "callSid" to call.sid
                            )
                        )
                    }
                }
            )

            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to accept XameTel call", e)
            false
        }
    }

    private fun rejectIncomingCall(callSid: String?): Boolean {
        val invite = pendingInvite ?: return false
        if (!callSid.isNullOrBlank() && invite.callSid != callSid) return false

        return try {
            invite.reject(applicationContext ?: return false)
            pendingInvite = null

            publishEvent(
                mapOf<String, Any?>(
                    "event" to "call_rejected",
                    "callSid" to invite.callSid
                )
            )

            Log.i(TAG, "XameTel call rejected: ${invite.callSid}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to reject XameTel call", e)
            false
        }
    }

    private fun disconnectActiveCall(callSid: String?): Boolean {
        val call = activeCall ?: return false
        if (!callSid.isNullOrBlank() && call.sid != callSid) return false

        return try {
            call.disconnect()
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to disconnect XameTel call", e)
            false
        }
    }

    private fun publishEvent(event: Map<String, Any?>) {
        mainHandler.post {
            val eventName = event["event"] as? String
            val callSid = event["callSid"] as? String

            if (
                callSid != null &&
                eventName in setOf(
                    "call_cancelled",
                    "call_rejected",
                    "call_disconnected",
                    "call_error"
                )
            ) {
                synchronized(lock) {
                    pendingEvents.removeIf {
                        it["callSid"] == callSid &&
                            it["event"] == "incoming_call"
                    }
                }
            }

            val channel = flutterChannel

            if (!flutterReady || channel == null) {
                synchronized(lock) {
                    while (pendingEvents.size >= MAX_PENDING_EVENTS) {
                        pendingEvents.removeFirst()
                    }
                    pendingEvents.addLast(event)
                }

                Log.i(
                    TAG,
                    "Queued XameTel event until Flutter is ready: ${event["event"]}"
                )
                return@post
            }

            try {
                channel.invokeMethod("xametelEvent", event)
            } catch (e: Exception) {
                Log.e(
                    TAG,
                    "Failed to deliver XameTel event to Flutter",
                    e
                )

                synchronized(lock) {
                    while (pendingEvents.size >= MAX_PENDING_EVENTS) {
                        pendingEvents.removeFirst()
                    }
                    pendingEvents.addLast(event)
                }
            }
        }
    }

    private fun flushPendingEvents() {
        mainHandler.post {
            val channel = flutterChannel
            if (!flutterReady || channel == null) return@post

            while (true) {
                val event = synchronized(lock) {
                    pendingEvents.firstOrNull()
                } ?: return@post

                try {
                    channel.invokeMethod("xametelEvent", event)

                    synchronized(lock) {
                        if (pendingEvents.firstOrNull() === event) {
                            pendingEvents.removeFirst()
                        }
                    }
                } catch (e: Exception) {
                    Log.e(
                        TAG,
                        "Failed to flush XameTel event to Flutter",
                        e
                    )
                    return@post
                }
            }
        }
    }
}
