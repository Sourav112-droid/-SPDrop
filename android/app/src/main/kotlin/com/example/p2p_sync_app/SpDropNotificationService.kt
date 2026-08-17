package com.example.p2p_sync_app

import android.app.Notification
import android.content.Intent
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import androidx.localbroadcastmanager.content.LocalBroadcastManager

/**
 * Notification listener service forwarding incoming notifications across trusted peer devices.
 */
class SpDropNotificationService : NotificationListenerService() {

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        val packageName = sbn.packageName
        val extras = sbn.notification?.extras
        val title = extras?.getString(Notification.EXTRA_TITLE) ?: ""
        val text = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""

        if (title.isNotEmpty() || text.isNotEmpty()) {
            val intent = Intent("SpDropNotification")
            intent.putExtra("package", packageName)
            intent.putExtra("title", title)
            intent.putExtra("text", text)
            
            LocalBroadcastManager.getInstance(this).sendBroadcast(intent)
        }
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Intentionally empty
    }
}
