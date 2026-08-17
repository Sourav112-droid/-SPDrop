package com.example.p2p_sync_app

import android.annotation.SuppressLint
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.wifi.p2p.*
import android.os.Build
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * Manages Android Wi-Fi Direct (P2P) group formation and peer discovery.
 *
 * Provides Group Owner IP assignment (standard: 192.168.49.1) enabling
 * direct socket transport when local network infrastructure is absent.
 */
class WifiDirectService(private val context: Context) {

    companion object {
        private const val TAG = "SpDrop_WiFiDirect"
        const val CHANNEL_NAME = "com.example.p2p_sync_app/wifi_p2p"
    }

    private var manager: WifiP2pManager? = null
    private var channel: WifiP2pManager.Channel? = null
    private var receiver: BroadcastReceiver? = null
    private var methodChannel: MethodChannel? = null

    // Cached state
    private var peers: MutableList<WifiP2pDevice> = mutableListOf()
    private var isGroupOwner = false
    private var groupOwnerAddress: String? = null

    fun initialize() {
        manager = context.getSystemService(Context.WIFI_P2P_SERVICE) as? WifiP2pManager
        channel = manager?.initialize(context, Looper.getMainLooper(), null)
        Log.d(TAG, "Wi-Fi Direct initialized")
    }

    fun setMethodChannel(mc: MethodChannel) {
        methodChannel = mc
    }

    // Broadcast Receiver — Handles Wi-Fi P2P system events

    fun registerReceiver() {
        val intentFilter = IntentFilter().apply {
            addAction(WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION)
            addAction(WifiP2pManager.WIFI_P2P_THIS_DEVICE_CHANGED_ACTION)
        }

        receiver = object : BroadcastReceiver() {
            @SuppressLint("MissingPermission")
            override fun onReceive(ctx: Context?, intent: Intent?) {
                when (intent?.action) {
                    WifiP2pManager.WIFI_P2P_STATE_CHANGED_ACTION -> {
                        val state = intent.getIntExtra(
                            WifiP2pManager.EXTRA_WIFI_STATE,
                            WifiP2pManager.WIFI_P2P_STATE_DISABLED
                        )
                        val enabled = state == WifiP2pManager.WIFI_P2P_STATE_ENABLED
                        Log.d(TAG, "Wi-Fi P2P state: ${if (enabled) "ENABLED" else "DISABLED"}")
                        methodChannel?.invokeMethod("onWifiP2pStateChanged", mapOf("enabled" to enabled))
                    }

                    WifiP2pManager.WIFI_P2P_PEERS_CHANGED_ACTION -> {
                        manager?.requestPeers(channel) { peerList ->
                            peers.clear()
                            peers.addAll(peerList.deviceList)
                            Log.d(TAG, "Peers found: ${peers.size}")

                            val peerMaps = peers.map { device ->
                                mapOf(
                                    "name" to (device.deviceName ?: "Unknown"),
                                    "address" to device.deviceAddress,
                                    "status" to device.status
                                )
                            }
                            methodChannel?.invokeMethod("onPeersFound", peerMaps)
                        }
                    }

                    WifiP2pManager.WIFI_P2P_CONNECTION_CHANGED_ACTION -> {
                        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            intent.getParcelableExtra(
                                WifiP2pManager.EXTRA_WIFI_P2P_INFO,
                                WifiP2pInfo::class.java
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            intent.getParcelableExtra(WifiP2pManager.EXTRA_WIFI_P2P_INFO)
                        }

                        if (info != null && info.groupFormed) {
                            isGroupOwner = info.isGroupOwner
                            groupOwnerAddress = info.groupOwnerAddress?.hostAddress

                            Log.d(TAG, "Connected! GO=${info.isGroupOwner}, IP=$groupOwnerAddress")

                            methodChannel?.invokeMethod("onConnected", mapOf(
                                "isGroupOwner" to isGroupOwner,
                                "groupOwnerAddress" to (groupOwnerAddress ?: "")
                            ))
                        } else {
                            Log.d(TAG, "Disconnected from Wi-Fi Direct group")
                            methodChannel?.invokeMethod("onDisconnected", null)
                        }
                    }
                }
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.registerReceiver(receiver, intentFilter, Context.RECEIVER_NOT_EXPORTED)
        } else {
            context.registerReceiver(receiver, intentFilter)
        }
        Log.d(TAG, "Broadcast receiver registered")
    }

    fun unregisterReceiver() {
        try {
            receiver?.let { context.unregisterReceiver(it) }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to unregister receiver: ${e.message}")
        }
    }

    // Group Management — Create/Remove Wi-Fi Direct group

    /**
     * Create a Wi-Fi Direct group. This device becomes the Group Owner (GO),
     * essentially creating an invisible hotspot that other devices can join.
     * 
     * The GO's IP is always 192.168.49.1 by Android convention.
     */
    @SuppressLint("MissingPermission")
    fun createGroup(result: MethodChannel.Result) {
        manager?.createGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group created successfully (this device is GO)")
                isGroupOwner = true
                groupOwnerAddress = "192.168.49.1" // Standard Android GO IP
                result.success(mapOf(
                    "success" to true,
                    "groupOwnerIp" to groupOwnerAddress
                ))
            }

            override fun onFailure(reason: Int) {
                val msg = when (reason) {
                    WifiP2pManager.P2P_UNSUPPORTED -> "Wi-Fi Direct not supported"
                    WifiP2pManager.BUSY -> "Framework busy"
                    WifiP2pManager.ERROR -> "Internal error"
                    else -> "Unknown error: $reason"
                }
                Log.e(TAG, "Failed to create group: $msg")
                result.error("GROUP_FAILED", msg, null)
            }
        })
    }

    /**
     * Remove the current Wi-Fi Direct group.
     */
    @SuppressLint("MissingPermission")
    fun removeGroup(result: MethodChannel.Result) {
        manager?.removeGroup(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Group removed")
                isGroupOwner = false
                groupOwnerAddress = null
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Failed to remove group: $reason")
                result.error("REMOVE_FAILED", "Failed to remove group: $reason", null)
            }
        })
    }

    /**
     * Start discovering nearby Wi-Fi Direct peers.
     * Results are delivered asynchronously via the broadcast receiver.
     */
    @SuppressLint("MissingPermission")
    fun discoverPeers(result: MethodChannel.Result) {
        manager?.discoverPeers(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery started")
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Peer discovery failed: $reason")
                result.error("DISCOVER_FAILED", "Failed to discover peers: $reason", null)
            }
        })
    }

    /**
     * Stop peer discovery.
     */
    fun stopDiscovery(result: MethodChannel.Result) {
        manager?.stopPeerDiscovery(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Peer discovery stopped")
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                Log.w(TAG, "Failed to stop discovery: $reason")
                result.success(false) // Non-critical failure
            }
        })
    }

    /**
     * Connect to a specific peer by their MAC address.
     *
     * After successful connection, the broadcast receiver will fire
     * WIFI_P2P_CONNECTION_CHANGED_ACTION with the Group Owner IP.
     */
    @SuppressLint("MissingPermission")
    fun connectToPeer(deviceAddress: String, result: MethodChannel.Result) {
        val config = WifiP2pConfig().apply {
            this.deviceAddress = deviceAddress
        }

        manager?.connect(channel, config, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                Log.d(TAG, "Connection initiated to $deviceAddress")
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                Log.e(TAG, "Connection to $deviceAddress failed: $reason")
                result.error("CONNECT_FAILED", "Failed to connect: $reason", null)
            }
        })
    }

    /**
     * Disconnect from the current peer.
     */
    fun disconnect(result: MethodChannel.Result) {
        manager?.cancelConnect(channel, object : WifiP2pManager.ActionListener {
            override fun onSuccess() {
                result.success(true)
            }

            override fun onFailure(reason: Int) {
                result.error("DISCONNECT_FAILED", "Failed to disconnect: $reason", null)
            }
        })
    }

    /**
     * Get the Group Owner IP address for TCP transport.
     * This is the IP the file transfer engine should connect to.
     */
    fun getGroupOwnerIp(): String? = groupOwnerAddress

    /**
     * Check if this device is the Group Owner.
     */
    fun isGroupOwner(): Boolean = isGroupOwner

    /**
     * Clean up all resources.
     */
    fun cleanup() {
        unregisterReceiver()
        channel = null
        manager = null
    }
}
