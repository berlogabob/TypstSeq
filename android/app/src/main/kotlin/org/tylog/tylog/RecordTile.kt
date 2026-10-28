package org.tylog.tylog

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.TileService

/// Quick Settings tile: the same "record an audio note" action as the assistant.
class RecordTile : TileService() {
    @Suppress("DEPRECATION")
    override fun onClick() {
        val intent = Intent(this, MainActivity::class.java)
            .setAction(MainActivity.RECORD_ACTION)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        if (Build.VERSION.SDK_INT >= 34) {
            startActivityAndCollapse(
                PendingIntent.getActivity(this, 0, intent, PendingIntent.FLAG_IMMUTABLE)
            )
        } else {
            startActivityAndCollapse(intent)
        }
    }
}
