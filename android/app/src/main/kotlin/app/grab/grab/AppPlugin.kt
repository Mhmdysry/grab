package app.grab.grab

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File

/**
 * App-level helpers. Channel "grab/app":
 *   abis()            -> List<String>, best first (picks the right APK from a release)
 *   openUrl(url)      -> opens a link in the browser
 *   installApk(path)  -> "started" | "needsPermission"
 *
 * Installing an APK signed with the same key and a higher version updates Grab in place:
 * downloads, settings and history all stay.
 */
class AppPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activity: () -> Activity?,
) {
    init {
        MethodChannel(messenger, "grab/app").setMethodCallHandler { call, result ->
            when (call.method) {
                "abis" -> result.success(Build.SUPPORTED_ABIS.toList())
                "dynamicColor" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                        val color = try {
                            context.getColor(android.R.color.system_accent1_500)
                        } catch (_: Throwable) {
                            null
                        }
                        result.success(color)
                    } else {
                        result.success(null)
                    }
                }
                "openUrl" -> {
                    start(Intent(Intent.ACTION_VIEW, Uri.parse(call.argument<String>("url")!!)))
                    result.success(null)
                }
                "installApk" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !context.packageManager.canRequestPackageInstalls()
                    ) {
                        // Android asks the user to allow Grab to install updates, once.
                        start(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                .setData(Uri.parse("package:${context.packageName}")),
                        )
                        result.success("needsPermission")
                        return@setMethodCallHandler
                    }
                    val file = File(call.argument<String>("path")!!)
                    val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
                    start(
                        Intent(Intent.ACTION_VIEW)
                            .setDataAndType(uri, "application/vnd.android.package-archive")
                            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION),
                    )
                    result.success("started")
                }
                "canDrawOverlays" -> result.success(FloatingBubbleOverlay.hasOverlayPermission(context))
                "requestOverlayPermission" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        !Settings.canDrawOverlays(context)
                    ) {
                        start(
                            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION)
                                .setData(Uri.parse("package:${context.packageName}")),
                        )
                    }
                    result.success(null)
                }
                "setBubbleConfig" -> {
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val primary = call.argument<Number>("primary")?.toInt() ?: 0xFFFFC107.toInt()
                    val onPrimary = call.argument<Number>("onPrimary")?.toInt() ?: 0xFF141414.toInt()
                    val surface = call.argument<Number>("surface")?.toInt() ?: 0xFF1F1F1F.toInt()
                    val onSurface = call.argument<Number>("onSurface")?.toInt() ?: 0xFFF4F4F4.toInt()
                    val primaryContainer = call.argument<Number>("primaryContainer")?.toInt() ?: 0xFF5D4200.toInt()
                    val onPrimaryContainer = call.argument<Number>("onPrimaryContainer")?.toInt() ?: 0xFFFFE082.toInt()
                    FloatingBubbleOverlay.setConfig(
                        context = context,
                        enabled = enabled,
                        primary = primary,
                        onPrimary = onPrimary,
                        surface = surface,
                        onSurface = onSurface,
                        primaryContainer = primaryContainer,
                        onPrimaryContainer = onPrimaryContainer,
                    )
                    result.success(null)
                }
                "previewBubble" -> {
                    if (FloatingBubbleOverlay.hasOverlayPermission(context)) {
                        FloatingBubbleOverlay.showPreview(context)
                        result.success(true)
                    } else {
                        result.success(false)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun start(intent: Intent) {
        val a = activity()
        if (a != null) a.startActivity(intent)
        else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
