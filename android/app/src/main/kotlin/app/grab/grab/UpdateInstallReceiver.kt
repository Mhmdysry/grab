package app.grab.grab

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * Receives callbacks from [PackageInstaller.Session.commit] when installing an in-app APK update.
 *
 * - On [PackageInstaller.STATUS_PENDING_USER_ACTION], launches the system confirmation activity.
 * - On success or any failure ([PackageInstaller.STATUS_FAILURE_CONFLICT],
 *   [PackageInstaller.STATUS_FAILURE_INCOMPATIBLE], etc.), forwards the exact status code and
 *   system message to [AppPlugin.onInstallStatus] so Dart can log and display an actionable reason.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(
            PackageInstaller.EXTRA_STATUS,
            PackageInstaller.STATUS_FAILURE,
        )
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: ""

        if (status == PackageInstaller.STATUS_PENDING_USER_ACTION) {
            val confirmIntent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
            } else {
                @Suppress("DEPRECATION")
                intent.getParcelableExtra(Intent.EXTRA_INTENT)
            }
            if (confirmIntent != null) {
                try {
                    confirmIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirmIntent)
                    AppPlugin.notifyInstallResult(
                        status = "prompted",
                        code = status,
                        message = "System install confirmation opened.",
                    )
                    return
                } catch (e: Throwable) {
                    AppPlugin.notifyInstallResult(
                        status = "error",
                        code = status,
                        message = "Failed to launch installer confirmation: ${e.message}",
                    )
                    return
                }
            }
        }

        val statusKey = when (status) {
            PackageInstaller.STATUS_SUCCESS -> "success"
            PackageInstaller.STATUS_FAILURE_ABORTED -> "aborted"
            PackageInstaller.STATUS_FAILURE_BLOCKED -> "blocked"
            PackageInstaller.STATUS_FAILURE_CONFLICT -> "conflict"
            PackageInstaller.STATUS_FAILURE_INCOMPATIBLE -> "incompatible"
            PackageInstaller.STATUS_FAILURE_INVALID -> "invalid"
            PackageInstaller.STATUS_FAILURE_STORAGE -> "storage"
            else -> "failure"
        }
        AppPlugin.notifyInstallResult(
            status = statusKey,
            code = status,
            message = message,
        )
    }
}
