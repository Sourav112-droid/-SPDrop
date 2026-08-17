package com.example.p2p_sync_app

import android.app.Activity
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.localbroadcastmanager.content.LocalBroadcastManager

/**
 * Transparent transient activity used to access clipboard content in background on Android 10+.
 */
class InvisibleClipboardActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        
        try {
            val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            if (clipboard.hasPrimaryClip()) {
                val clipData = clipboard.primaryClip
                if (clipData != null && clipData.itemCount > 0) {
                    val text = clipData.getItemAt(0).text?.toString()
                    if (!text.isNullOrEmpty()) {
                        Log.d("InvisibleClipboard", "Clipboard read successfully. Writing to file...")
                        val file = java.io.File(filesDir, "clipboard_buffer.txt")
                        file.writeText(text)
                    }
                }
            }
        } catch (e: Exception) {
            Log.e("InvisibleClipboard", "Error reading clipboard", e)
        }
        
        // Finish immediately so the user never sees this activity
        finish()
        overridePendingTransition(0, 0)
    }
}
