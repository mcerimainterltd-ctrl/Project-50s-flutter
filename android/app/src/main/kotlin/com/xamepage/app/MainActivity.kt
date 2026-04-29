package com.xamepage.app

import android.os.Bundle
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
                    // Flutter will handle this via platform channel listener
                    result.success(null)
                } else {
                    result.notImplemented()
                }
            }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Start keepalive service when app opens
        SocketKeepaliveService.start(this)
    }

    override fun onDestroy() {
        FlutterEngineCache.getInstance().remove("main")
        super.onDestroy()
    }
}
