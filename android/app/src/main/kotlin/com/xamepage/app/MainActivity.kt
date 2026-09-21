package com.xamepage.app

import android.os.Build
import android.os.Bundle
import android.os.StatFs
import android.net.Uri
import android.content.Intent
import android.content.Context
import android.media.AudioManager
import androidx.core.content.FileProvider
import java.io.File
import android.provider.Settings
import android.view.WindowManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    companion object {
        var channel: MethodChannel? = null
    }

    private val CHANNEL = "com.xamepage.app/call"

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

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

        // Cold start (app was fully killed): the Answer/Decline intent
        // arrives via getIntent() here, not onNewIntent, which is only
        // called when the Activity already exists. Handling it in both
        // places is what makes the notification's Answer button work on
        // the first tap regardless of whether the app was already running.
        // Wrapped defensively: this must never be able to crash a normal,
        // non-call app launch.
        try {
            handleCallIntent(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.xamepage.app/android_bridge")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "startNativePresence" -> {
                        val token = call.argument<String>("token")
                        if (token.isNullOrBlank()) {
                            result.success(false)
                        } else {
                            NativePresenceService.start(this@MainActivity, token)
                            result.success(true)
                        }
                    }
                    "stopNativePresence" -> {
                        NativePresenceService.stop(this@MainActivity)
                        result.success(true)
                    }
                    "getPresenceDiagnostics" -> {
                        val diagPrefs = getSharedPreferences("xamepage_native_presence", MODE_PRIVATE)
                        result.success(mapOf(
                            "started" to diagPrefs.getLong("diag_started", 0L),
                            "taskRemoved" to diagPrefs.getLong("diag_task_removed", 0L),
                            "destroyed" to diagPrefs.getLong("diag_destroyed", 0L),
                            "lastHeartbeat" to diagPrefs.getLong("diag_last_heartbeat", 0L),
                            "lastResponse" to diagPrefs.getInt("diag_last_response", 0),
                            "lastCallPushReceived" to diagPrefs.getLong("diag_last_call_push_received", 0L),
                            "lastCallNotifyPosted" to diagPrefs.getLong("diag_last_call_notify_posted", 0L),
                            "tokenStatus" to diagPrefs.getString("diag_token_status", "never"),
                            "tokenDetail" to diagPrefs.getString("diag_token_detail", ""),
                            "tokenTime" to diagPrefs.getLong("diag_token_time", 0L)
                        ))
                    }
                    "writeTokenDiagnostic" -> {
                        val status = call.argument<String>("status") ?: "unknown"
                        val detail = call.argument<String>("detail") ?: ""
                        getSharedPreferences("xamepage_native_presence", MODE_PRIVATE)
                            .edit()
                            .putString("diag_token_status", status)
                            .putString("diag_token_detail", detail)
                            .putLong("diag_token_time", System.currentTimeMillis())
                            .apply()
                        result.success(true)
                    }
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
                    "getStorageInfo" -> {
                        try {
                            val stat = StatFs(android.os.Environment.getDataDirectory().path)
                            result.success(
                                mapOf(
                                    "availableBytes" to stat.availableBytes,
                                    "totalBytes" to stat.totalBytes
                                )
                            )
                        } catch (e: Exception) {
                            android.util.Log.e(
                                "XamePage",
                                "Storage information lookup failed",
                                e
                            )
                            result.error("STORAGE_INFO_FAILED", e.message, null)
                        }
                    }
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
                    "installApk" -> {
                        val path = call.argument<String>("path") ?: ""
                        try {
                            val apkFile = File(path)
                            if (!apkFile.exists()) {
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val apkUri = FileProvider.getUriForFile(
                                this,
                                "$packageName.fileprovider",
                                apkFile
                            )

                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                                !packageManager.canRequestPackageInstalls()
                            ) {
                                val settingsIntent = Intent(
                                    Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                    Uri.parse("package:$packageName")
                                )
                                startActivity(settingsIntent)
                                result.success(false)
                                return@setMethodCallHandler
                            }

                            val installIntent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                                setDataAndType(
                                    apkUri,
                                    "application/vnd.android.package-archive"
                                )
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                clipData = android.content.ClipData.newRawUri(
                                    "XamePage APK",
                                    apkUri
                                )
                            }

                            startActivity(installIntent)
                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e(
                                "XamePage",
                                "APK installation failed for: $path",
                                e
                            )
                            result.success(false)
                        }
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
                    "prepareCallAudio" -> {
                        val audioManager =
                            getSystemService(Context.AUDIO_SERVICE) as AudioManager

                        audioManager.mode = AudioManager.MODE_IN_COMMUNICATION
                        audioManager.isMicrophoneMute = false

                        @Suppress("DEPRECATION")
                        run {
                            audioManager.isSpeakerphoneOn = false
                        }

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

    private fun handleCallIntent(intent: android.content.Intent?) {
        val engine = flutterEngine ?: return
        when (intent?.action) {
            CallService.ACTION_ANSWER -> {
                CallService.stop(this)
                val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                mgr.cancel(CallService.NOTIF_ID + 1)
                val callerId   = intent.getStringExtra("caller_id")   ?: ""
                val callerName = intent.getStringExtra("caller_name") ?: ""
                val callType   = intent.getStringExtra("call_type")   ?: "voice"
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigateToIncomingCall", mapOf(
                        "callerId"   to callerId,
                        "callerName" to callerName,
                        "callType"   to callType
                    ))
            }
            CallService.ACTION_DECLINE -> {
                CallService.stop(this)
                val mgr = getSystemService(NOTIFICATION_SERVICE) as android.app.NotificationManager
                mgr.cancel(CallService.NOTIF_ID + 1)
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("onCallDeclined", null)
            }
            CallService.ACTION_VIEW_INCOMING_CALL -> {
                // Tapped the notification body (not the Answer button).
                // Show the incoming call screen and start the ringtone
                // immediately, but don't dismiss the notification or stop
                // CallService yet — the call hasn't actually been answered,
                // just viewed. Answering is still decided from within the
                // incoming call screen itself.
                val callerId   = intent.getStringExtra("caller_id")   ?: ""
                val callerName = intent.getStringExtra("caller_name") ?: ""
                val callType   = intent.getStringExtra("call_type")   ?: "voice"
                MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                    .invokeMethod("navigateToIncomingCall", mapOf(
                        "callerId"   to callerId,
                        "callerName" to callerName,
                        "callType"   to callType
                    ))
            }
        }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        try {
            handleCallIntent(intent)
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
