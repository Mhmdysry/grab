package app.grab.grab

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.android.RenderMode
import io.flutter.embedding.android.TransparencyMode
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import java.lang.ref.WeakReference

/**
 * Translucent floating overlay Activity for ACTION_SEND shares.
 *
 * Uses `RenderMode.texture` + `TransparencyMode.transparent` inside the caller's
 * task stack (standard launchMode) so the source app (YouTube/TikTok/Browser)
 * remains live and visible behind the dimmed scrim with zero special permissions.
 *
 * Uses a process-wide cached [FlutterEngine] (`grab_share_engine`) running the
 * `shareMain` Dart entrypoint with `shouldDestroyEngineWithHost() = false`, so:
 * 1) downloads queued from the share card continue cleanly in the background
 *    and record completion into SQLite even after this Activity closes back to
 *    the source app, and
 * 2) subsequent shares open nearly instantaneously.
 */
class ShareActivity : FlutterActivity() {
    override fun getRenderMode(): RenderMode = RenderMode.texture

    override fun getTransparencyMode(): TransparencyMode = TransparencyMode.transparent

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode =
        FlutterActivityLaunchConfigs.BackgroundMode.transparent

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        getOrCreateEngine(context.applicationContext)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        // Plugins and MethodChannels are registered once inside getOrCreateEngine
        // so re-attaching never overwrites EnginePlugin's active EventChannel sink.
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        intent?.putExtra("background_mode", "transparent")
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
        val hadEngine = FlutterEngineCache.getInstance().get(ENGINE_ID) != null
        val text = extractSharedText(intent)
        if (!hadEngine) pendingSharedText = text
        super.onCreate(savedInstanceState)
        window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
        window.decorView.setBackgroundColor(Color.TRANSPARENT)
        ensureViewsTransparent(window.decorView)
        window.decorView.post { ensureViewsTransparent(window.decorView) }
        activeActivity = WeakReference(this)
        suppressTransition(isOpen = true)
        if (hadEngine) {
            pendingSharedText = null
            shareChannel?.invokeMethod("sharedText", text ?: "")
        }
    }

    private fun ensureViewsTransparent(view: android.view.View?) {
        if (view == null) return
        view.setBackgroundColor(Color.TRANSPARENT)
        if (view is android.view.TextureView) {
            view.isOpaque = false
        } else if (view is android.view.SurfaceView) {
            view.setZOrderOnTop(true)
            view.holder.setFormat(android.graphics.PixelFormat.TRANSPARENT)
        } else if (view is android.view.ViewGroup) {
            for (i in 0 until view.childCount) {
                ensureViewsTransparent(view.getChildAt(i))
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val text = extractSharedText(intent)
        pendingSharedText = null
        shareChannel?.invokeMethod("sharedText", text ?: "")
    }

    override fun onDestroy() {
        if (activeActivity?.get() === this) activeActivity = null
        super.onDestroy()
    }

    private fun closeWithNoAnim() {
        finish()
        suppressTransition(isOpen = false)
    }

    private fun openMainApp(url: String?, tab: String?) {
        val mainIntent = Intent(this, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP,
            )
            if (!url.isNullOrBlank()) putExtra(MainActivity.EXTRA_OPEN_URL, url)
            if (!tab.isNullOrBlank()) putExtra(MainActivity.EXTRA_OPEN_TAB, tab)
        }
        startActivity(mainIntent)
        closeWithNoAnim()
    }

    @Suppress("DEPRECATION")
    private fun suppressTransition(isOpen: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            overrideActivityTransition(
                if (isOpen) OVERRIDE_TRANSITION_OPEN else OVERRIDE_TRANSITION_CLOSE,
                0,
                0,
            )
        } else {
            overridePendingTransition(0, 0)
        }
    }

    private fun extractSharedText(intent: Intent?): String? {
        if (intent?.action != Intent.ACTION_SEND) return null
        val extra = intent.getStringExtra(Intent.EXTRA_TEXT)?.trim()
        if (!extra.isNullOrEmpty()) return extra
        val subject = intent.getStringExtra(Intent.EXTRA_SUBJECT)?.trim()
        if (!subject.isNullOrEmpty()) return subject
        return intent.clipData?.takeIf { it.itemCount > 0 }
            ?.getItemAt(0)
            ?.coerceToText(this)
            ?.toString()
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
    }

    companion object {
        const val ENGINE_ID = "grab_share_engine"
        private const val CHANNEL = "grab/share"

        private var activeActivity: WeakReference<ShareActivity>? = null
        private var shareChannel: MethodChannel? = null
        private var pendingSharedText: String? = null

        @Synchronized
        private fun getOrCreateEngine(appContext: Context): FlutterEngine {
            FlutterEngineCache.getInstance().get(ENGINE_ID)?.let { return it }

            val loader = FlutterInjector.instance().flutterLoader()
            if (!loader.initialized()) {
                loader.startInitialization(appContext)
                loader.ensureInitializationComplete(appContext, null)
            }

            val engine = FlutterEngine(appContext)
            GeneratedPluginRegistrant.registerWith(engine)
            val messenger = engine.dartExecutor.binaryMessenger
            EnginePlugin(appContext, messenger)
            HapticsPlugin(appContext, messenger)
            AppPlugin(appContext, messenger) { activeActivity?.get() }

            shareChannel = MethodChannel(messenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takeSharedText" -> {
                            result.success(pendingSharedText)
                            pendingSharedText = null
                        }
                        "closeOverlay" -> {
                            activeActivity?.get()?.closeWithNoAnim()
                            result.success(null)
                        }
                        "openMainApp" -> {
                            val url = call.argument<String>("url")
                            val tab = call.argument<String>("tab")
                            activeActivity?.get()?.openMainApp(url, tab)
                            result.success(null)
                        }
                        else -> result.notImplemented()
                    }
                }
            }

            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "shareMain"),
            )
            FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
            return engine
        }
    }
}
