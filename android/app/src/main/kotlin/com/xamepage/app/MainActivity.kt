package com.xamepage.app

import android.os.Build
import android.os.Bundle
import android.net.Uri
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        var channel: MethodChannel? = null
    }

    private val CHANNEL = "com.xamepage.app/call"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // If launched silently by SocketKeepaliveService on boot,
        // initialize the Flutter engine but move immediately to background
        // so the user never sees the app pop up.
        if (intent?.getBooleanExtra("boot_launch", false) == true) {
            moveTaskToBack(true)
        }

        // Allow activity to show on lock screen and wake device
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON or
                WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD
            )
        }
        requestOneTimePermissions()
        SocketKeepaliveService.start(this)
        AlarmReceiver.schedule(this)
    }

    private fun requestOneTimePermissions() {
        val prefs = getSharedPreferences("xamepage_prefs", MODE_PRIVATE)
        val versionCode = packageManager.getPackageInfo(packageName, 0).versionCode
        if (prefs.getInt("permissions_asked_version", -1) == versionCode) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(this)) {
            startActivity(android.content.Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:$packageName")))
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            val pm = getSystemService(android.os.PowerManager::class.java)
            if (!pm.isIgnoringBatteryOptimizations(packageName)) {
                startActivity(android.content.Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:$packageName")))
            }
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            androidx.core.app.ActivityCompat.requestPermissions(
                this,
                arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
                1001
            )
        }
        prefs.edit().putInt("permissions_asked_version", versionCode).apply()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.xamepage.app/keepalive")
        NetworkReceiver.register(this)
        super.configureFlutterEngine(flutterEngine)
        FlutterEngineCache.getInstance().put("main", flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger,
            SocketKeepaliveService.CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                if (call.method == "heartbeat") result.success(null)
                else result.notImplemented()
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.xamepage.app/android_bridge")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openBatterySettings" -> {
                        var launched = false
                        // Try battery optimization settings first
                        try {
                            val i = android.content.Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
                            i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(i)
                            launched = true
                        } catch (_: Exception) {}
                        // Fallback: app details settings
                        if (!launched) {
                            try {
                                val i = android.content.Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName"))
                                i.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                            } catch (_: Exception) {}
                        }
                        result.success(null)
                    }
                    "getDeviceBrand" -> result.success(android.os.Build.MANUFACTURER)
                    "isBatteryOptimized" -> {
                        val pm = getSystemService(android.os.PowerManager::class.java)
                        result.success(!pm.isIgnoringBatteryOptimizations(packageName))
                    }
                    "saveMedia" -> {
                        val url      = call.argument<String>("url")      ?: ""
                        val fileName = call.argument<String>("fileName")  ?: "xamepage_file"
                        val mimeType = call.argument<String>("mimeType")  ?: "image/jpeg"
                        Thread {
                            val success = MediaSaverService.saveFromUrl(this, url, fileName, mimeType)
                            runOnUiThread { result.success(success) }
                        }.start()
                    }
                    else -> result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startCallService" -> {
                        val caller   = call.argument<String>("callerName") ?: "Unknown"
                        val callType = call.argument<String>("callType")   ?: "voice"
                        CallService.start(this, caller, callType)
                        result.success(null)
                    }
                    "stopCallService" -> {
                        CallService.stop(this)
                        result.success(null)
                    }
                    "dismissIncomingCall" -> {
                        val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                        mgr.cancel(CallService.NOTIF_ID + 1)
                        CallService.stop(this)
                        result.success(null)
                    }
                    "keepScreenOn" -> {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    "releaseScreen" -> {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val engine = FlutterEngineCache.getInstance().get("main") ?: return
        when (intent.action) {
            CallService.ACTION_ANSWER -> {
                CallService.stop(this)
                val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                mgr.cancel(CallService.NOTIF_ID + 1)
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigateToIncomingCall", null)
            }
            CallService.ACTION_DECLINE -> {
                CallService.stop(this)
                val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                mgr.cancel(CallService.NOTIF_ID + 1)
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onCallDeclined", null)
            }
        }
    }

    override fun onDestroy() {
        FlutterEngineCache.getInstance().remove("main")
        super.onDestroy()
    }
}
