package app.grab.grab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat

/**
 * Keeps the app process alive while downloads run, and shows their progress
 * in the notification bar. The downloads themselves run in [EnginePlugin].
 */
class DownloadService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val count = intent?.getIntExtra(EXTRA_COUNT, 0) ?: 0
        val notification = build(
            this,
            intent?.getStringExtra(EXTRA_TITLE) ?: "Downloading",
            maxOf(count, 1),
            intent?.getIntExtra(EXTRA_PERCENT, 0) ?: 0,
        )
        // Android requires startForeground on every start of a foreground service,
        // even when we are about to stop; otherwise it times out and leaves the notification.
        val type = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC else 0
        ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, type)
        if (count == 0) {
            ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL_ID = "downloads"
        private const val NOTIFICATION_ID = 1001
        private const val EXTRA_COUNT = "count"
        private const val EXTRA_TITLE = "title"
        private const val EXTRA_PERCENT = "percent"
        private var running = false
        private var lastPercent = -1
        private var lastCount = -1

        /** Called with the current active jobs (title, progress 0-100). */
        fun update(context: Context, jobs: List<Pair<String, Float>>) {
            val count = jobs.size
            if (count == 0 && !running) return
            val percent = if (count == 0) 0 else jobs.map { it.second.coerceIn(0f, 100f) }.average().toInt()
            // Notifications are rate-limited by Android; only post on visible change.
            if (count == lastCount && percent == lastPercent) return
            lastCount = count
            lastPercent = percent
            val intent = Intent(context, DownloadService::class.java)
                .putExtra(EXTRA_COUNT, count)
                .putExtra(EXTRA_TITLE, jobs.firstOrNull()?.first ?: "")
                .putExtra(EXTRA_PERCENT, percent)
            running = count > 0
            ContextCompat.startForegroundService(context, intent)
        }

        private const val DONE_CHANNEL_ID = "finished"

        /** One notification per finished job: "Saved" or "Download failed". */
        fun notifyFinished(context: Context, jobId: String, title: String, ok: Boolean) {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != android.content.pm.PackageManager.PERMISSION_GRANTED
            ) return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(DONE_CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(DONE_CHANNEL_ID, "Finished downloads", NotificationManager.IMPORTANCE_DEFAULT)
                )
            }
            val open = PendingIntent.getActivity(
                context, 1,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val n = NotificationCompat.Builder(context, DONE_CHANNEL_ID)
                .setSmallIcon(if (ok) R.drawable.ic_stat_grab else android.R.drawable.stat_notify_error)
                .setContentTitle(if (ok) "Saved" else "Download failed")
                .setContentText(title)
                .setAutoCancel(true)
                .setContentIntent(open)
                .build()
            manager.notify(jobId.hashCode(), n)
        }

        private fun build(context: Context, title: String, count: Int, percent: Int): Notification {
            val manager = context.getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && manager.getNotificationChannel(CHANNEL_ID) == null) {
                manager.createNotificationChannel(
                    NotificationChannel(CHANNEL_ID, "Downloads", NotificationManager.IMPORTANCE_LOW)
                )
            }
            val open = PendingIntent.getActivity(
                context, 0,
                Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_IMMUTABLE,
            )
            val heading = if (count == 1) title else "Downloading $count items"
            return NotificationCompat.Builder(context, CHANNEL_ID)
                .setSmallIcon(R.drawable.ic_stat_grab)
                .setContentTitle(heading)
                .setContentText("$percent%")
                .setProgress(100, percent, percent == 0)
                .setOngoing(true)
                .setOnlyAlertOnce(true)
                .setContentIntent(open)
                .build()
        }
    }
}
