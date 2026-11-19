package app.grab.grab

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** AudioServiceActivity (a FlutterActivity) keeps background audio tied to this screen. */
class MainActivity : AudioServiceActivity() {
    private var launch: MethodChannel? = null

    /** Set when the Quick Settings tile opened the app; Dart takes it once. */
    private var pendingAction: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        EnginePlugin(applicationContext, messenger)
        HapticsPlugin(applicationContext, messenger)
        RingtonePlugin(applicationContext, messenger) { this }
        AppPlugin(applicationContext, messenger) { this }
        pendingAction = actionOf(intent)
        launch = MethodChannel(messenger, "grab/launch").apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "takeAction" -> { result.success(pendingAction); pendingAction = null }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val action = actionOf(intent) ?: return
        launch?.invokeMethod("action", action)
    }

    private fun actionOf(intent: Intent?): String? {
        val tab = intent?.getStringExtra(EXTRA_OPEN_TAB)
        if (tab == "downloads") return "openDownloads"
        val url = intent?.getStringExtra(EXTRA_OPEN_URL)?.trim()
        if (!url.isNullOrEmpty()) return "fetch:$url"
        return if (intent?.action == GrabTileService.ACTION_GRAB_CLIPBOARD) "grabClipboard" else null
    }

    companion object {
        const val EXTRA_OPEN_TAB = "grab_open_tab"
        const val EXTRA_OPEN_URL = "grab_open_url"
    }
}
