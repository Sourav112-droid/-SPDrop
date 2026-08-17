package com.example.p2p_sync_app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/**
 * Quick Settings Tile Service for toggling peer connection state.
 *
 * Dispatches an in-place broadcast when the Flutter engine is active,
 * or launches the main activity in the background to initialize the engine on cold start.
 */
class SpDropTileService : TileService() {

    companion object {
        const val ACTION_QS_TOGGLE = "com.example.p2p_sync_app.QS_TOGGLE"
    }

    override fun onStartListening() {
        super.onStartListening()
        updateTileDisplay()
    }

    override fun onClick() {
        super.onClick()

        val prefs = applicationContext.getSharedPreferences("sp_drop_tile", Context.MODE_PRIVATE)
        val engineRunning = prefs.getBoolean("flutter_engine_started", false)

        // Always update tile display immediately for responsive feel
        val currentlyConnected = prefs.getBoolean("is_connected", false)
        prefs.edit()
            .putBoolean("tile_toggle_requested", true)
            .putBoolean("tile_toggle_target", !currentlyConnected)
            .apply()
        updateTileDisplay()

        if (engineRunning) {
            // Flutter engine is alive — send broadcast to toggle in-place.
            // The RECEIVER_EXPORTED fix in MainActivity ensures this is received.
            val broadcastIntent = Intent(ACTION_QS_TOGGLE)
            broadcastIntent.setPackage(applicationContext.packageName)
            applicationContext.sendBroadcast(broadcastIntent)
        } else {
            // Cold start: launch Activity to initialize Flutter engine.
            // from_qs_tile flag causes immediate moveTaskToBack (no UI flash).
            val intent = Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                putExtra("start_receive_mode", true)
                putExtra("toggle_connection", true)
                putExtra("from_qs_tile", true)
            }
            launchIntent(intent)
        }
    }

    private fun launchIntent(intent: Intent) {
        if (Build.VERSION.SDK_INT >= 34) {
            val pendingIntent = PendingIntent.getActivity(
                this,
                0,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pendingIntent)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }

    private fun updateTileDisplay() {
        val tile = qsTile ?: return
        val prefs = applicationContext.getSharedPreferences("sp_drop_tile", Context.MODE_PRIVATE)
        val isConnected = prefs.getBoolean("is_connected", false)
        val deviceName = prefs.getString("connected_device", "") ?: ""

        if (isConnected && deviceName.isNotEmpty()) {
            tile.state = Tile.STATE_ACTIVE
            tile.label = "SpDrop"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = deviceName
            }
        } else {
            tile.state = Tile.STATE_INACTIVE
            tile.label = "SpDrop"
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                tile.subtitle = "Tap to connect"
            }
        }
        tile.updateTile()
    }
}
