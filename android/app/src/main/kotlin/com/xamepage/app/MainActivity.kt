package com.xamepage.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.media.AudioManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.xamepage.app/android_bridge"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setCallAudioMode" -> {
                        val inCall = call.arguments as Boolean
                        val am = getSystemService(AUDIO_SERVICE) as AudioManager
                        am.mode = if (inCall) AudioManager.MODE_IN_COMMUNICATION else AudioManager.MODE_NORMAL
                        result.success(null)
                    }
                    "setSpeaker" -> {
                        val on = call.arguments as Boolean
                        val am = getSystemService(AUDIO_SERVICE) as AudioManager
                        am.isSpeakerphoneOn = on
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
