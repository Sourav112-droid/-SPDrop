# SP Drop ProGuard Rules
# ──────────────────────────────────────────────────────────────────

# Keep foreground service classes (flutter_foreground_task)
-keep class com.pravera.flutter_foreground_task.** { *; }

# Keep our BootReceiver — it's referenced by name in AndroidManifest.xml
-keep class com.example.p2p_sync_app.BootReceiver { *; }

# Keep notification service classes
-keep class com.example.p2p_sync_app.SpDropNotificationService { *; }

# Keep Wi-Fi Direct service
-keep class com.example.p2p_sync_app.WifiDirectService { *; }

# Keep Flutter plugins that use reflection
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# WorkManager
-keep class androidx.work.** { *; }
-keepclassmembers class * extends androidx.work.Worker { *; }
-keepclassmembers class * extends androidx.work.ListenableWorker { *; }

# NSD (Network Service Discovery)
-keep class com.haberey.flutter.nsd_android.** { *; }

# Ignore missing Play Core classes for Flutter engine deferred components
-dontwarn com.google.android.play.core.**
