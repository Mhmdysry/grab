package app.grab.grab

import android.app.Activity
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.CopyOnWriteArrayList

/**
 * App-level helpers. Channel "grab/app":
 *   abis()                  -> List<String>, best first (picks the right APK from a release)
 *   openUrl(url)            -> opens a link in the browser
 *   installApk(path)        -> Map<String, Any?> { "status": "started" | "needsPermission" | "invalidApk" | "error", ... }
 *   installApkDirect(path)  -> fallback ACTION_VIEW system package installer intent
 *
 * Installing an APK signed with the same key and a higher version updates Grab in place:
 * downloads, settings and history all stay.
 */
class AppPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
    private val activity: () -> Activity?,
) {
    private val channel = MethodChannel(messenger, "grab/app")

    init {
        channels.add(channel)
        channel.setMethodCallHandler { call, result ->
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
                    val path = call.argument<String>("path")
                    if (path.isNullOrBlank()) {
                        result.success("invalidApk:Empty APK path")
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !context.packageManager.canRequestPackageInstalls()
                    ) {
                        start(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                .setData(Uri.parse("package:${context.packageName}")),
                        )
                        result.success("needsPermission")
                        return@setMethodCallHandler
                    }
                    val file = File(path)
                    if (!file.exists() || file.length() <= 0L) {
                        result.success("invalidApk:Downloaded APK file is missing or empty")
                        return@setMethodCallHandler
                    }
                    // Verify that Android can parse the downloaded APK archive before installing.
                    val archiveInfo = try {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                            context.packageManager.getPackageArchiveInfo(
                                file.absolutePath,
                                PackageManager.PackageInfoFlags.of(0),
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            context.packageManager.getPackageArchiveInfo(file.absolutePath, 0)
                        }
                    } catch (_: Throwable) {
                        null
                    }
                    if (archiveInfo == null) {
                        result.success("invalidApk:Downloaded APK is corrupted or incomplete (${file.length()} bytes)")
                        return@setMethodCallHandler
                    }
                    try {
                        installViaPackageInstallerSession(file, archiveInfo.packageName)
                        result.success("started")
                    } catch (e: Throwable) {
                        // Fall back to direct FileProvider ACTION_VIEW if PackageInstaller session creation fails.
                        try {
                            launchDirectViewInstaller(file)
                            result.success("started")
                        } catch (e2: Throwable) {
                            result.success("error:${e.message ?: e2.message}")
                        }
                    }
                }
                "installApkDirect" -> {
                    val path = call.argument<String>("path") ?: ""
                    val file = File(path)
                    if (!file.exists()) {
                        result.success("invalidApk:File not found")
                        return@setMethodCallHandler
                    }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                        !context.packageManager.canRequestPackageInstalls()
                    ) {
                        start(
                            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                                .setData(Uri.parse("package:${context.packageName}")),
                        )
                        result.success("needsPermission")
                        return@setMethodCallHandler
                    }
                    try {
                        launchDirectViewInstaller(file)
                        result.success("started")
                    } catch (e: Throwable) {
                        result.success("error:${e.message}")
                    }
                }
                "getLogcat" -> {
                    try {
                        val pid = android.os.Process.myPid().toString()
                        val proc = Runtime.getRuntime().exec(
                            arrayOf("logcat", "-d", "-v", "time", "-t", "300", "--pid=$pid"),
                        )
                        val text = proc.inputStream.bufferedReader().readText()
                        if (text.isNotBlank()) {
                            result.success(text)
                        } else {
                            val fallback = Runtime.getRuntime().exec(
                                arrayOf("logcat", "-d", "-v", "time", "-t", "250"),
                            )
                            result.success(fallback.inputStream.bufferedReader().readText())
                        }
                    } catch (e: Throwable) {
                        result.success("Could not read logcat: ${e.message}")
                    }
                }
                "clearLogcat" -> {
                    try {
                        Runtime.getRuntime().exec(arrayOf("logcat", "-c"))
                    } catch (_: Throwable) {}
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun installViaPackageInstallerSession(file: File, pkgName: String?) {
        val installer = context.packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(
            PackageInstaller.SessionParams.MODE_FULL_INSTALL,
        ).apply {
            if (!pkgName.isNullOrBlank()) setAppPackageName(pkgName)
            setSize(file.length())
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
            }
        }
        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
            file.inputStream().use { input ->
                session.openWrite("grab_update.apk", 0, file.length()).use { output ->
                    input.copyTo(output, bufferSize = 64 * 1024)
                    session.fsync(output)
                }
            }
            val callbackIntent = Intent(context, UpdateInstallReceiver::class.java).apply {
                setPackage(context.packageName)
            }
            val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                sessionId,
                callbackIntent,
                flags,
            )
            session.commit(pendingIntent.intentSender)
        }
    }

    @Suppress("DEPRECATION")
    private fun launchDirectViewInstaller(file: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val intent = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        start(intent)
    }

    private fun start(intent: Intent) {
        val a = activity()
        if (a != null) a.startActivity(intent)
        else context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    companion object {
        private val mainHandler = Handler(Looper.getMainLooper())
        private val channels = CopyOnWriteArrayList<MethodChannel>()

        fun notifyInstallResult(status: String, code: Int, message: String) {
            mainHandler.post {
                val payload = mapOf(
                    "status" to status,
                    "code" to code,
                    "message" to message,
                )
                for (ch in channels) {
                    runCatching { ch.invokeMethod("installStatus", payload) }
                }
            }
        }
    }
}
