package com.xamepage.app

import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    override fun provideFlutterEngine(context: android.content.Context): FlutterEngine? {
        return super.provideFlutterEngine(context)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Cache engine so SocketKeepaliveService can reach it
        FlutterEngineCache.getInstance().put("main", flutterEngine)

        // Keepalive channel — Flutter handles heartbeat
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            SocketKeepaliveService.CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "heartbeat") {
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }

        // Call control channel — dismiss heads-up notification
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            "com.xamepage.app/call")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "dismissIncomingCall" -> {
                        val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                        mgr.cancel(CallService.NOTIF_ID + 1)
                        CallService.stop(this)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Show over lock screen and turn screen on
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
        // Request display over other apps permission if not granted
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
            !Settings.canDrawOverlays(this)) {
            val intent = android.content.Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:$packageName")
            )
            startActivity(intent)
        }
        // Request battery optimization exemption for reliable background delivery
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(android.os.PowerManager::class.java)
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                val intent = android.content.Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")
                )
                startActivity(intent)
            }
        }
        SocketKeepaliveService.start(this)
        handleCallIntent(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        handleCallIntent(intent)
    }

    private fun handleCallIntent(intent: android.content.Intent?) {
        if (intent == null) return
        val callerName = intent.getStringExtra("caller_name") ?: return
        val callType   = intent.getStringExtra("call_type")   ?: "voice"
        when (intent.action) {
            CallService.ACTION_ANSWER -> {
                // Start service then let Flutter handle the answer
                CallService.start(this, callerName, callType)
            }
            CallService.ACTION_DECLINE -> {
                CallService.stop(this)
            }
            else -> {
                // App opened from full-screen notification — start call service
                if (intent.getBooleanExtra("incoming_call", false)) {
                    CallService.start(this, callerName, callType)
                }
            }
        }
    }

    override fun onDestroy() {
        FlutterEngineCache.getInstance().remove("main")
        super.onDestroy()
    }
}
