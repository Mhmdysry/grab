package app.grab.grab

import android.content.Context
import android.content.Intent
import android.graphics.Color
import android.graphics.drawable.ColorDrawable
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.ViewTreeObserver
import android.widget.Toast
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
 * - When **Instant Grab** is enabled in Settings (`flutter.instantGrab == true` in
 *   `FlutterSharedPreferences`), `ShareActivity` shows a native Android [Toast],
 *   dispatches the shared text to the background `grab_share_engine`, and immediately
 *   calls [finish] inside [onCreate] so no floating window appears at all.
 * - When **Instant Grab** is off, renders the translucent M3 Expressive floating card
 *   over the caller's task stack (`RenderMode.texture` + `TransparencyMode.transparent`)
 *   and pins `DecorView` to `Color.TRANSPARENT` so Android/OEM dark-mode window helpers
 *   never reset `DecorView` to `#FF010102`.
 */
class ShareActivity : FlutterActivity() {
    private var globalLayoutListener: ViewTreeObserver.OnGlobalLayoutListener? = null

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
        applyWindowTransparency()
        val hadEngine = FlutterEngineCache.getInstance().get(ENGINE_ID) != null
        val text = extractSharedText(intent)
        val forceUi = intent?.getBooleanExtra(EXTRA_FORCE_UI, false) == true
        val silentInstant = !forceUi && !text.isNullOrBlank() && isInstantGrabEnabled(applicationContext)

        if (!hadEngine) {
            pendingSharedText = text
            pendingSharedSilent = silentInstant
        }

        super.onCreate(savedInstanceState)
        applyWindowTransparency()

        val decor = window.decorView
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            applyWindowTransparency()
        }
        globalLayoutListener = listener
        decor.viewTreeObserver.addOnGlobalLayoutListener(listener)
        decor.post { applyWindowTransparency() }

        activeActivity = WeakReference(this)
        suppressTransition(isOpen = true)

        if (hadEngine) {
            pendingSharedText = null
            pendingSharedSilent = false
            shareChannel?.invokeMethod(
                if (silentInstant) "instantShareText" else "sharedText",
                text ?: "",
            )
        }

        if (silentInstant) {
            showNativeToast(applicationContext, "Instant Grab: starting download…")
            closeWithNoAnim()
        }
    }

    override fun onStart() {
        super.onStart()
        applyWindowTransparency()
    }

    override fun onResume() {
        super.onResume()
        applyWindowTransparency()
        window.decorView.post { applyWindowTransparency() }
    }

    override fun onPostResume() {
        super.onPostResume()
        applyWindowTransparency()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        applyWindowTransparency()
    }

    private fun applyWindowTransparency() {
        runCatching {
            window.setBackgroundDrawable(ColorDrawable(Color.TRANSPARENT))
            window.clearFlags(android.view.WindowManager.LayoutParams.FLAG_DIM_BEHIND)
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isNavigationBarContrastEnforced = false
                window.isStatusBarContrastEnforced = false
            }
            val decor = window.peekDecorView() ?: return
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                decor.isForceDarkAllowed = false
            }
            ensureViewsTransparent(decor)
        }
    }

    private fun ensureViewsTransparent(view: android.view.View?) {
        if (view == null) return
        when (view) {
            is android.view.TextureView -> {
                // TextureView throws UnsupportedOperationException if setBackgroundDrawable/setBackgroundColor is called!
                runCatching { view.isOpaque = false }
            }
            is android.view.SurfaceView -> {
                runCatching {
                    view.setZOrderOnTop(true)
                    view.holder.setFormat(android.graphics.PixelFormat.TRANSPARENT)
                }
            }
            is android.view.ViewGroup -> {
                runCatching { view.background = null }
                for (i in 0 until view.childCount) {
                    ensureViewsTransparent(view.getChildAt(i))
                }
            }
            else -> {
                runCatching { view.background = null }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyWindowTransparency()
        val text = extractSharedText(intent)
        val forceUi = intent.getBooleanExtra(EXTRA_FORCE_UI, false)
        val silentInstant = !forceUi && !text.isNullOrBlank() && isInstantGrabEnabled(applicationContext)
        pendingSharedText = null
        pendingSharedSilent = false
        shareChannel?.invokeMethod(
            if (silentInstant) "instantShareText" else "sharedText",
            text ?: "",
        )
        if (silentInstant) {
            showNativeToast(applicationContext, "Instant Grab: starting download…")
            closeWithNoAnim()
        }
    }

    override fun onDestroy() {
        globalLayoutListener?.let { l ->
            runCatching {
                window.peekDecorView()?.viewTreeObserver?.removeOnGlobalLayoutListener(l)
            }
        }
        globalLayoutListener = null
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
        private const val EXTRA_FORCE_UI = "grab_force_ui"

        private val mainHandler = Handler(Looper.getMainLooper())
        private var activeActivity: WeakReference<ShareActivity>? = null
        private var shareChannel: MethodChannel? = null
        private var pendingSharedText: String? = null
        private var pendingSharedSilent: Boolean = false

        private fun isInstantGrabEnabled(context: Context): Boolean {
            return try {
                val prefs = context.getSharedPreferences(
                    "FlutterSharedPreferences",
                    Context.MODE_PRIVATE,
                )
                prefs.getBoolean("flutter.instantGrab", false)
            } catch (_: Throwable) {
                false
            }
        }

        private fun showNativeToast(context: Context, message: String) {
            if (message.isBlank()) return
            mainHandler.post {
                runCatching {
                    Toast.makeText(context.applicationContext, message, Toast.LENGTH_SHORT).show()
                }
            }
        }

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
            // Remove AudioServicePlugin from the share overlay engine before ShareActivity attaches
            // so it never hijacks MainActivity's AudioServiceActivity binding.
            runCatching {
                engine.plugins.remove(com.ryanheise.audioservice.AudioServicePlugin::class.java)
            }
            val messenger = engine.dartExecutor.binaryMessenger
            EnginePlugin(appContext, messenger)
            HapticsPlugin(appContext, messenger)
            AppPlugin(appContext, messenger) { activeActivity?.get() }

            shareChannel = MethodChannel(messenger, CHANNEL).apply {
                setMethodCallHandler { call, result ->
                    when (call.method) {
                        "takeSharedPayload" -> {
                            val text = pendingSharedText
                            val silent = pendingSharedSilent
                            pendingSharedText = null
                            pendingSharedSilent = false
                            if (text == null) {
                                result.success(null)
                            } else {
                                result.success(
                                    mapOf(
                                        "text" to text,
                                        "silent" to silent,
                                    ),
                                )
                            }
                        }
                        "takeSharedText" -> {
                            result.success(pendingSharedText)
                            pendingSharedText = null
                            pendingSharedSilent = false
                        }
                        "showToast" -> {
                            val msg = call.argument<String>("message") ?: ""
                            showNativeToast(appContext, msg)
                            result.success(null)
                        }
                        "closeOverlay" -> {
                            activeActivity?.get()?.closeWithNoAnim()
                            result.success(null)
                        }
                        "openMainApp" -> {
                            val url = call.argument<String>("url")
                            val tab = call.argument<String>("tab")
                            val act = activeActivity?.get()
                            if (act != null) {
                                act.openMainApp(url, tab)
                            } else {
                                val mainIntent = Intent(appContext, MainActivity::class.java).apply {
                                    addFlags(
                                        Intent.FLAG_ACTIVITY_NEW_TASK or
                                            Intent.FLAG_ACTIVITY_CLEAR_TOP or
                                            Intent.FLAG_ACTIVITY_SINGLE_TOP,
                                    )
                                    if (!url.isNullOrBlank()) putExtra(MainActivity.EXTRA_OPEN_URL, url)
                                    if (!tab.isNullOrBlank()) putExtra(MainActivity.EXTRA_OPEN_TAB, tab)
                                }
                                appContext.startActivity(mainIntent)
                            }
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
