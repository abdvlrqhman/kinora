package io.github.abdvlrqhman.kinora

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import java.io.File

/// After a restart, says how many downloads wait for Kinora to open
/// (torrents need the app running). The count is written by the app's
/// downloads service (`pending_downloads` in its support folder).
class DownloadsBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val count = try {
            File(context.filesDir, "pending_downloads").readText().trim().toInt()
        } catch (e: Exception) {
            0
        }
        if (count <= 0) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        manager.createNotificationChannel(
            NotificationChannel(CHANNEL, "Paused downloads", NotificationManager.IMPORTANCE_DEFAULT)
        )
        val open = PendingIntent.getActivity(
            context,
            0,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        val title = if (count == 1) "1 download is paused" else "$count downloads are paused"
        val notification = Notification.Builder(context, CHANNEL)
            .setSmallIcon(R.drawable.ic_stat_kinora)
            .setContentTitle(title)
            .setContentText("Your phone restarted. Open Kinora to continue.")
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        // Without the notification permission this shows nothing; downloads
        // still continue when Kinora opens.
        try {
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: SecurityException) {
        }
    }

    private companion object {
        const val CHANNEL = "kinora_paused_downloads"
        const val NOTIFICATION_ID = 7301
    }
}
