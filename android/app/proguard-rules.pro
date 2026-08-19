-keep class org.webrtc.** { *; }
-dontwarn org.webrtc.**

# Keep XamePage native classes
-keep class com.xamepage.app.** { *; }

# Keep Flutter engine
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Keep Socket.IO
-keep class io.socket.** { *; }
-dontwarn io.socket.**

# Keep OkHttp
-keep class okhttp3.** { *; }
-dontwarn okhttp3.**

# Keep Kotlin coroutines
-keep class kotlinx.coroutines.** { *; }
-dontwarn kotlinx.coroutines.**