package com.example.p2p_sync_app

import android.content.Context
import android.content.BroadcastReceiver
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.localbroadcastmanager.content.LocalBroadcastManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val QS_CHANNEL = "com.example.p2p_sync_app/quick_settings"
    private val HOTSPOT_CHANNEL = "com.example.p2p_sync_app/wifi_direct"
    private val NOTIFICATION_CHANNEL = "com.example.p2p_sync_app/notifications"
    private val NOTIFICATION_SETTINGS_CHANNEL = "com.example.p2p_sync_app/notification_settings"
    private val WIFI_P2P_CHANNEL = "com.example.p2p_sync_app/wifi_p2p"

    private var pendingReceiveMode = false
    private var reservation: WifiManager.LocalOnlyHotspotReservation? = null
    private var notificationSink: EventChannel.EventSink? = null

    // Wi-Fi Direct service
    private var wifiDirectService: WifiDirectService? = null

    // QS tile broadcast receiver
    private val qsTileReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            if (intent?.action == SpDropTileService.ACTION_QS_TOGGLE) {
                // Forward toggle to Flutter without touching the Activity UI
                flutterEngine?.dartExecutor?.binaryMessenger?.let {
                    MethodChannel(it, QS_CHANNEL).invokeMethod("toggleConnection", null)
                }
            }
        }
    }

    private val notificationReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val packageName = intent?.getStringExtra("package") ?: ""
            val title = intent?.getStringExtra("title") ?: ""
            val text = intent?.getStringExtra("text") ?: ""
            
            val map = mapOf(
                "package" to packageName,
                "title" to title,
                "text" to text
            )
            notificationSink?.success(map)
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (intent?.getBooleanExtra("start_receive_mode", false) == true) {
            pendingReceiveMode = true
        }
        if (intent?.getBooleanExtra("from_qs_tile", false) == true) {
            moveTaskToBack(true)
        }

        // Set flag so QS tile knows it can use broadcast
        val prefs = getSharedPreferences("sp_drop_tile", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("flutter_engine_started", true).apply()

        // Register broadcast receivers
        LocalBroadcastManager.getInstance(this).registerReceiver(
            notificationReceiver, IntentFilter("SpDropNotification")
        )

        // Register global broadcast receiver for Quick Settings tile toggle.
        // Requires RECEIVER_EXPORTED on Android 14+ because TileService runs in a separate system context.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(
                qsTileReceiver,
                IntentFilter(SpDropTileService.ACTION_QS_TOGGLE),
                Context.RECEIVER_EXPORTED
            )
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(
                qsTileReceiver,
                IntentFilter(SpDropTileService.ACTION_QS_TOGGLE)
            )
        }
    }

    override fun onDestroy() {
        // Clear engine flag and unregister receivers
        val prefs = getSharedPreferences("sp_drop_tile", Context.MODE_PRIVATE)
        prefs.edit().putBoolean("flutter_engine_started", false).apply()

        LocalBroadcastManager.getInstance(this).unregisterReceiver(notificationReceiver)
        try { unregisterReceiver(qsTileReceiver) } catch (_: Exception) {}
        wifiDirectService?.cleanup()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        if (intent.getBooleanExtra("start_receive_mode", false) == true) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, QS_CHANNEL).invokeMethod("triggerReceiveMode", null)
            }
        }
        // If from QS tile, move to background immediately
        if (intent.getBooleanExtra("from_qs_tile", false) == true) {
            moveTaskToBack(true)
        }
        // Handle quick settings connect/disconnect
        if (intent.getBooleanExtra("toggle_connection", false) == true) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let {
                MethodChannel(it, QS_CHANNEL).invokeMethod("toggleConnection", null)
            }
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Quick Settings channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, QS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "checkPendingReceiveMode" -> {
                    val wasPending = pendingReceiveMode
                    pendingReceiveMode = false
                    result.success(wasPending)
                }
                "updateTileState" -> {
                    val isConnected = call.argument<Boolean>("isConnected") ?: false
                    val deviceName = call.argument<String>("deviceName") ?: ""
                    val prefs = getSharedPreferences("sp_drop_tile", Context.MODE_PRIVATE)
                    prefs.edit()
                        .putBoolean("is_connected", isConnected)
                        .putString("connected_device", deviceName)
                        .apply()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Hotspot channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HOTSPOT_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startHotspot" -> {
                    startLocalHotspot(result)
                }
                "stopHotspot" -> {
                    stopLocalHotspot()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Notification settings channel
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_SETTINGS_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "openNotificationSettings" -> {
                    val intent = Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }

        // Wi-Fi Direct P2P channel
        wifiDirectService = WifiDirectService(this)
        wifiDirectService!!.initialize()

        val wifiP2pMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, WIFI_P2P_CHANNEL)
        wifiDirectService!!.setMethodChannel(wifiP2pMethodChannel)

        wifiP2pMethodChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "initialize" -> {
                    result.success(true)
                }
                "registerReceiver" -> {
                    wifiDirectService!!.registerReceiver()
                    result.success(true)
                }
                "unregisterReceiver" -> {
                    wifiDirectService!!.unregisterReceiver()
                    result.success(true)
                }
                "createGroup" -> {
                    wifiDirectService!!.createGroup(result)
                }
                "removeGroup" -> {
                    wifiDirectService!!.removeGroup(result)
                }
                "discoverPeers" -> {
                    wifiDirectService!!.discoverPeers(result)
                }
                "stopDiscovery" -> {
                    wifiDirectService!!.stopDiscovery(result)
                }
                "connectToPeer" -> {
                    val address = call.argument<String>("deviceAddress") ?: ""
                    wifiDirectService!!.connectToPeer(address, result)
                }
                "disconnect" -> {
                    wifiDirectService!!.disconnect(result)
                }
                else -> result.notImplemented()
            }
        }

        // Notification EventChannel
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFICATION_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    notificationSink = events
                }

                override fun onCancel(arguments: Any?) {
                    notificationSink = null
                }
            }
        )
    }

    private fun startLocalHotspot(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val wifiManager = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            try {
                wifiManager.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                    override fun onStarted(res: WifiManager.LocalOnlyHotspotReservation) {
                        super.onStarted(res)
                        reservation = res
                        var ssid = ""
                        var password = ""
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            val softApConfig = res.softApConfiguration
                            if (softApConfig != null) {
                                ssid = softApConfig.ssid ?: ""
                                password = softApConfig.passphrase ?: ""
                            }
                        } else {
                            @Suppress("DEPRECATION")
                            val config = res.wifiConfiguration
                            if (config != null) {
                                ssid = config.SSID ?: ""
                                password = config.preSharedKey ?: ""
                            }
                        }
                        val map = mapOf(
                            "ssid" to ssid,
                            "password" to password
                        )
                        result.success(map)
                    }

                    override fun onStopped() {
                        super.onStopped()
                        reservation = null
                    }

                    override fun onFailed(reason: Int) {
                        super.onFailed(reason)
                        result.error("HOTSPOT_FAILED", "Failed to start hotspot. Reason: $reason", null)
                    }
                }, Handler(Looper.getMainLooper()))
            } catch (e: SecurityException) {
                result.error("PERMISSION_DENIED", "Missing permissions to start hotspot: ${e.message}", null)
            } catch (e: Exception) {
                result.error("ERROR", "Exception starting hotspot: ${e.message}", null)
            }
        } else {
            result.error("UNSUPPORTED", "LocalOnlyHotspot requires Android 8.0+", null)
        }
    }

    private fun stopLocalHotspot() {
        reservation?.close()
        reservation = null
    }
}
