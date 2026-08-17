package com.example.p2p_sync_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.Log

/**
 * Restarts background receiver service after device reboot to maintain peer connectivity.
 */
class BootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "SpDrop_BootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON"
        ) {
            Log.d(TAG, "Boot completed — starting SP Drop service")

            // Launch MainActivity in background mode to initialize Flutter engine
            // and start the foreground service. The activity will immediately
            // move to background without showing UI.
            val launchIntent = Intent(context, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                putExtra("start_receive_mode", true)
                putExtra("from_boot", true)
                putExtra("from_qs_tile", true) // Reuse the "move to background" logic
            }

            try {
                context.startActivity(launchIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start activity after boot: ${e.message}")
            }
        }
    }
}
