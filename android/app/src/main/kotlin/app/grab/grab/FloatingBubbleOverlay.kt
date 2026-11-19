package app.grab.grab

import android.animation.ValueAnimator
import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.PixelFormat
import android.graphics.RectF
import android.graphics.Typeface
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.HapticFeedbackConstants
import android.view.MotionEvent
import android.view.View
import android.view.ViewConfiguration
import android.view.WindowManager
import android.view.animation.OvershootInterpolator
import kotlin.math.hypot
import kotlin.math.roundToInt

/**
 * Native Android WindowManager floating progress bubble (`TYPE_APPLICATION_OVERLAY` on API 26+).
 *
 * Gated on [Settings.canDrawOverlays] and the user's `floatingBubbleEnabled` preference.
 * Supports:
 * - Material 3 Expressive custom Canvas orb (`58dp`) synced to Grab's active M3 palette.
 * - Live radial progress arc, active count badge, and celebratory checkmark morph (`1.8s` auto-hide).
 * - Smooth drag physics, magnetic left/right edge snap with [OvershootInterpolator],
 *   bottom-center `×` dismiss zone, and tap-to-open Grab Downloads tab.
 * - 5-second interactive preview mode for Settings.
 */
@SuppressLint("StaticFieldLeak")
object FloatingBubbleOverlay {
    private const val PREFS_NAME = "grab_bubble"
    private const val KEY_ENABLED = "enabled"
    private const val KEY_PRIMARY = "primary"
    private const val KEY_ON_PRIMARY = "onPrimary"
    private const val KEY_SURFACE = "surface"
    private const val KEY_ON_SURFACE = "onSurface"
    private const val KEY_PRIMARY_CONTAINER = "primaryContainer"
    private const val KEY_ON_PRIMARY_CONTAINER = "onPrimaryContainer"
    private const val KEY_POS_X = "posX"
    private const val KEY_POS_Y = "posY"

    private const val DEFAULT_PRIMARY = 0xFFFFC107.toInt()
    private const val DEFAULT_ON_PRIMARY = 0xFF141414.toInt()
    private const val DEFAULT_SURFACE = 0xFF1F1F1F.toInt()
    private const val DEFAULT_ON_SURFACE = 0xFFF4F4F4.toInt()
    private const val DEFAULT_PRIMARY_CONTAINER = 0xFF5D4200.toInt()
    private const val DEFAULT_ON_PRIMARY_CONTAINER = 0xFFFFE082.toInt()

    private val main = Handler(Looper.getMainLooper())

    private var windowManager: WindowManager? = null
    private var bubbleView: BubbleView? = null
    private var bubbleParams: WindowManager.LayoutParams? = null
    private var dismissView: DismissZoneView? = null
    private var dismissParams: WindowManager.LayoutParams? = null

    private var snapAnimator: ValueAnimator? = null
    private var previewAnimator: ValueAnimator? = null
    private var hideRunnable: Runnable? = null

    private var activeCount = 0
    private var activePercent = 0
    private var activeTitle = ""
    private var doneSuccess = false
    private var isPreview = false
    private var dismissedForBatch = false

    private var colorPrimary = DEFAULT_PRIMARY
    private var colorOnPrimary = DEFAULT_ON_PRIMARY
    private var colorSurface = DEFAULT_SURFACE
    private var colorOnSurface = DEFAULT_ON_SURFACE
    private var colorPrimaryContainer = DEFAULT_PRIMARY_CONTAINER
    private var colorOnPrimaryContainer = DEFAULT_ON_PRIMARY_CONTAINER

    fun hasOverlayPermission(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    fun isEnabled(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_ENABLED, true)

    fun setConfig(
        context: Context,
        enabled: Boolean,
        primary: Int,
        onPrimary: Int = DEFAULT_ON_PRIMARY,
        surface: Int,
        onSurface: Int,
        primaryContainer: Int,
        onPrimaryContainer: Int,
    ) {
        val app = context.applicationContext
        app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENABLED, enabled)
            .putInt(KEY_PRIMARY, primary)
            .putInt(KEY_ON_PRIMARY, onPrimary)
            .putInt(KEY_SURFACE, surface)
            .putInt(KEY_ON_SURFACE, onSurface)
            .putInt(KEY_PRIMARY_CONTAINER, primaryContainer)
            .putInt(KEY_ON_PRIMARY_CONTAINER, onPrimaryContainer)
            .apply()

        main.post {
            loadPalette(app)
            bubbleView?.invalidate()
            if (!enabled) {
                dismissedForBatch = false
                if (!isPreview) hideInternal()
            }
        }
    }

    fun update(context: Context, count: Int, percent: Int, title: String) {
        val app = context.applicationContext
        main.post {
            loadPalette(app)
            if (!hasOverlayPermission(app) || !isEnabled(app)) {
                if (!isPreview) hideInternal()
                return@post
            }

            if (count <= 0) {
                activeCount = 0
                dismissedForBatch = false
                if (!isPreview && !doneSuccess && bubbleView != null) {
                    scheduleHide(280L)
                }
                return@post
            }

            if (dismissedForBatch) {
                activeCount = count
                activePercent = percent.coerceIn(0, 100)
                activeTitle = title
                return@post
            }

            cancelHide()
            cancelPreview()
            doneSuccess = false
            activeCount = count
            activePercent = percent.coerceIn(0, 100)
            activeTitle = title
            ensureAttached(app)
            bubbleView?.setProgressState(activeCount, activePercent, doneSuccess = false)
        }
    }

    fun notifyFinished(context: Context, ok: Boolean) {
        val app = context.applicationContext
        main.post {
            if (isPreview) return@post
            if (bubbleView == null || activeCount > 0) return@post
            if (!hasOverlayPermission(app) || !isEnabled(app)) {
                hideInternal()
                return@post
            }
            cancelHide()
            if (ok) {
                doneSuccess = true
                activePercent = 100
                bubbleView?.setProgressState(0, 100, doneSuccess = true)
                scheduleHide(1800L)
            } else {
                hideInternal()
            }
        }
    }

    fun showPreview(context: Context) {
        val app = context.applicationContext
        main.post {
            if (!hasOverlayPermission(app)) return@post
            loadPalette(app)
            cancelHide()
            cancelPreview()
            dismissedForBatch = false
            isPreview = true
            doneSuccess = false
            activeCount = 1
            activePercent = 0
            activeTitle = "Preview"
            ensureAttached(app)
            bubbleView?.setProgressState(1, 0, doneSuccess = false)

            var canceled = false
            previewAnimator = ValueAnimator.ofInt(0, 100).apply {
                duration = 3200L
                addUpdateListener { anim ->
                    val p = anim.animatedValue as Int
                    activePercent = p
                    bubbleView?.setProgressState(1, p, doneSuccess = false)
                }
                addListener(object : android.animation.AnimatorListenerAdapter() {
                    override fun onAnimationCancel(animation: android.animation.Animator) {
                        canceled = true
                    }

                    override fun onAnimationEnd(animation: android.animation.Animator) {
                        if (canceled || !isPreview) return
                        doneSuccess = true
                        bubbleView?.setProgressState(0, 100, doneSuccess = true)
                        scheduleHide(1800L)
                    }
                })
                start()
            }
        }
    }

    private fun loadPalette(app: Context) {
        val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        colorPrimary = prefs.getInt(KEY_PRIMARY, DEFAULT_PRIMARY)
        colorOnPrimary = prefs.getInt(KEY_ON_PRIMARY, DEFAULT_ON_PRIMARY)
        colorSurface = prefs.getInt(KEY_SURFACE, DEFAULT_SURFACE)
        colorOnSurface = prefs.getInt(KEY_ON_SURFACE, DEFAULT_ON_SURFACE)
        colorPrimaryContainer = prefs.getInt(KEY_PRIMARY_CONTAINER, DEFAULT_PRIMARY_CONTAINER)
        colorOnPrimaryContainer = prefs.getInt(KEY_ON_PRIMARY_CONTAINER, DEFAULT_ON_PRIMARY_CONTAINER)
    }

    private fun overlayWindowType(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
        } else {
            @Suppress("DEPRECATION")
            WindowManager.LayoutParams.TYPE_PHONE
        }

    private fun dp(context: Context, value: Float): Int =
        (value * context.resources.displayMetrics.density).roundToInt()

    private fun ensureAttached(app: Context) {
        if (bubbleView != null) return
        val wm = app.getSystemService(Context.WINDOW_SERVICE) as? WindowManager ?: return
        windowManager = wm

        val metrics = app.resources.displayMetrics
        val sizePx = dp(app, 62f)
        val marginPx = dp(app, 12f)
        val prefs = app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val defaultX = (metrics.widthPixels - sizePx - marginPx).coerceAtLeast(0)
        val defaultY = (metrics.heightPixels * 0.34f).roundToInt()
        val savedX = prefs.getInt(KEY_POS_X, defaultX).coerceIn(0, (metrics.widthPixels - sizePx).coerceAtLeast(0))
        val savedY = prefs.getInt(KEY_POS_Y, defaultY).coerceIn(dp(app, 48f), (metrics.heightPixels - sizePx - dp(app, 64f)).coerceAtLeast(0))

        val dismissSize = dp(app, 64f)
        val dView = DismissZoneView(app)
        val dParams = WindowManager.LayoutParams(
            dismissSize,
            dismissSize,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_NOT_TOUCHABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.BOTTOM or Gravity.CENTER_HORIZONTAL
            y = dp(app, 40f)
        }
        dView.visibility = View.GONE

        val bView = BubbleView(app)
        val bParams = WindowManager.LayoutParams(
            sizePx,
            sizePx,
            overlayWindowType(),
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN,
            PixelFormat.TRANSLUCENT,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = savedX
            y = savedY
        }

        bView.setOnTouchListener(BubbleTouchListener(app, wm, bView, bParams, dView))

        try {
            wm.addView(dView, dParams)
            wm.addView(bView, bParams)
            dismissView = dView
            dismissParams = dParams
            bubbleView = bView
            bubbleParams = bParams
        } catch (_: Throwable) {
            runCatching { wm.removeViewImmediate(dView) }
            runCatching { wm.removeViewImmediate(bView) }
            dismissView = null
            dismissParams = null
            bubbleView = null
            bubbleParams = null
        }
    }

    private fun scheduleHide(delayMs: Long) {
        cancelHide()
        val r = Runnable {
            isPreview = false
            doneSuccess = false
            hideInternal()
        }
        hideRunnable = r
        main.postDelayed(r, delayMs)
    }

    private fun cancelHide() {
        hideRunnable?.let { main.removeCallbacks(it) }
        hideRunnable = null
    }

    private fun cancelPreview() {
        val anim = previewAnimator
        previewAnimator = null
        isPreview = false
        anim?.cancel()
    }

    private fun hideInternal() {
        cancelHide()
        cancelPreview()
        snapAnimator?.cancel()
        snapAnimator = null
        val wm = windowManager
        bubbleView?.let { v ->
            v.stopSpin()
            if (wm != null) runCatching { wm.removeViewImmediate(v) }
        }
        dismissView?.let { d ->
            if (wm != null) runCatching { wm.removeViewImmediate(d) }
        }
        bubbleView = null
        bubbleParams = null
        dismissView = null
        dismissParams = null
    }

    private class BubbleTouchListener(
        private val app: Context,
        private val wm: WindowManager,
        private val view: BubbleView,
        private val params: WindowManager.LayoutParams,
        private val dismissZone: DismissZoneView,
    ) : View.OnTouchListener {
        private val touchSlop = ViewConfiguration.get(app).scaledTouchSlop
        private var startX = 0
        private var startY = 0
        private var downRawX = 0f
        private var downRawY = 0f
        private var moved = false
        private var insideDismiss = false

        @SuppressLint("ClickableViewAccessibility")
        override fun onTouch(v: View, event: MotionEvent): Boolean {
            val metrics = app.resources.displayMetrics
            val screenW = metrics.widthPixels
            val screenH = metrics.heightPixels
            val sizePx = params.width
            val marginPx = dp(app, 12f)

            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN -> {
                    snapAnimator?.cancel()
                    startX = params.x
                    startY = params.y
                    downRawX = event.rawX
                    downRawY = event.rawY
                    moved = false
                    insideDismiss = false
                    dismissZone.visibility = View.VISIBLE
                    dismissZone.setHot(false)
                    view.animate().scaleX(1.06f).scaleY(1.06f).setDuration(120L).start()
                    return true
                }

                MotionEvent.ACTION_MOVE -> {
                    val dx = event.rawX - downRawX
                    val dy = event.rawY - downRawY
                    if (!moved && hypot(dx.toDouble(), dy.toDouble()) > touchSlop) {
                        moved = true
                    }
                    if (moved) {
                        params.x = (startX + dx.roundToInt()).coerceIn(0, (screenW - sizePx).coerceAtLeast(0))
                        params.y = (startY + dy.roundToInt()).coerceIn(dp(app, 24f), (screenH - sizePx).coerceAtLeast(0))
                        runCatching { wm.updateViewLayout(view, params) }

                        val bubbleCx = params.x + sizePx / 2f
                        val bubbleCy = params.y + sizePx / 2f
                        val dismissCx = screenW / 2f
                        val dismissCy = screenH - dp(app, 72f).toFloat()
                        val hot = hypot((bubbleCx - dismissCx).toDouble(), (bubbleCy - dismissCy).toDouble()) < dp(app, 74f)
                        if (hot != insideDismiss) {
                            insideDismiss = hot
                            dismissZone.setHot(hot)
                            if (hot) {
                                view.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP)
                            }
                        }
                    }
                    return true
                }

                MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                    view.animate().scaleX(1f).scaleY(1f).setDuration(140L).start()
                    dismissZone.visibility = View.GONE

                    if (moved && insideDismiss) {
                        if (!isPreview) dismissedForBatch = true
                        hideInternal()
                        return true
                    }

                    if (!moved && event.actionMasked == MotionEvent.ACTION_UP) {
                        openDownloadsTab(app)
                        return true
                    }

                    // Magnetic snap to closest horizontal edge
                    val centerX = params.x + sizePx / 2
                    val targetX = if (centerX < screenW / 2) {
                        marginPx
                    } else {
                        (screenW - sizePx - marginPx).coerceAtLeast(0)
                    }
                    snapAnimator = ValueAnimator.ofInt(params.x, targetX).apply {
                        duration = 280L
                        interpolator = OvershootInterpolator(1.05f)
                        addUpdateListener { anim ->
                            params.x = anim.animatedValue as Int
                            if (bubbleView === view) {
                                runCatching { wm.updateViewLayout(view, params) }
                            }
                        }
                        start()
                    }
                    app.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
                        .putInt(KEY_POS_X, targetX)
                        .putInt(KEY_POS_Y, params.y)
                        .apply()
                    return true
                }
            }
            return false
        }

        private fun openDownloadsTab(app: Context) {
            val intent = Intent(app, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP,
                )
                putExtra(MainActivity.EXTRA_OPEN_TAB, "downloads")
            }
            app.startActivity(intent)
        }
    }

    private class BubbleView(context: Context) : View(context) {
        private var count = 0
        private var percent = 0
        private var done = false
        private var spinAngle = 0f
        private var spinAnimator: ValueAnimator? = null

        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
        }
        private val trackPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }
        private val arcPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }
        private val innerPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            textAlign = Paint.Align.CENTER
            typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
        }
        private val checkPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
        }
        private val arcRect = RectF()
        private val checkPath = Path()

        init {
            setLayerType(LAYER_TYPE_SOFTWARE, null)
        }

        fun setProgressState(count: Int, percent: Int, doneSuccess: Boolean) {
            this.count = count
            this.percent = percent
            this.done = doneSuccess
            if (!doneSuccess && percent <= 0 && count > 0) {
                startSpin()
            } else {
                stopSpin()
            }
            invalidate()
        }

        private fun startSpin() {
            if (spinAnimator?.isRunning == true) return
            spinAnimator = ValueAnimator.ofFloat(0f, 360f).apply {
                duration = 1200L
                repeatCount = ValueAnimator.INFINITE
                interpolator = android.view.animation.LinearInterpolator()
                addUpdateListener {
                    spinAngle = it.animatedValue as Float
                    invalidate()
                }
                start()
            }
        }

        fun stopSpin() {
            spinAnimator?.cancel()
            spinAnimator = null
        }

        override fun onDraw(canvas: Canvas) {
            val d = resources.displayMetrics.density
            val cx = width / 2f
            val cy = height / 2f
            val outerR = (minOf(width, height) / 2f) - 4f * d

            bgPaint.color = colorSurface
            bgPaint.setShadowLayer(4f * d, 0f, 2f * d, Color.argb(95, 0, 0, 0))
            canvas.drawCircle(cx, cy, outerR, bgPaint)

            borderPaint.color = Color.argb(45, Color.red(colorOnSurface), Color.green(colorOnSurface), Color.blue(colorOnSurface))
            borderPaint.strokeWidth = 1f * d
            canvas.drawCircle(cx, cy, outerR, borderPaint)

            val stroke = 4f * d
            val arcR = outerR - 4.5f * d
            arcRect.set(cx - arcR, cy - arcR, cx + arcR, cy + arcR)

            trackPaint.strokeWidth = stroke
            trackPaint.color = Color.argb(40, Color.red(colorOnSurface), Color.green(colorOnSurface), Color.blue(colorOnSurface))
            canvas.drawCircle(cx, cy, arcR, trackPaint)

            arcPaint.strokeWidth = stroke
            arcPaint.color = colorPrimary
            if (done) {
                canvas.drawArc(arcRect, -90f, 360f, false, arcPaint)
            } else if (percent <= 0) {
                canvas.drawArc(arcRect, -90f + spinAngle, 110f, false, arcPaint)
            } else {
                val sweep = (percent.coerceIn(2, 100) / 100f) * 360f
                canvas.drawArc(arcRect, -90f, sweep, false, arcPaint)
            }

            val innerR = outerR - 9.5f * d
            innerPaint.color = if (done) colorPrimary else colorPrimaryContainer
            canvas.drawCircle(cx, cy, innerR, innerPaint)

            if (done) {
                checkPaint.color = colorOnPrimary
                checkPaint.strokeWidth = 2.8f * d
                checkPath.reset()
                checkPath.moveTo(cx - 6.5f * d, cy + 0.5f * d)
                checkPath.lineTo(cx - 1.5f * d, cy + 5.5f * d)
                checkPath.lineTo(cx + 7.5f * d, cy - 4.5f * d)
                canvas.drawPath(checkPath, checkPaint)
            } else {
                val label = when {
                    count > 1 -> "$count"
                    percent > 0 -> "$percent%"
                    else -> "↓"
                }
                textPaint.color = colorOnPrimaryContainer
                textPaint.textSize = (if (label.length >= 4) 10.5f else 12.5f) * d
                val baseline = cy - (textPaint.descent() + textPaint.ascent()) / 2f
                canvas.drawText(label, cx, baseline, textPaint)
            }
        }
    }

    private class DismissZoneView(context: Context) : View(context) {
        private var hot = false
        private val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG)
        private val xPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            style = Paint.Style.STROKE
            strokeCap = Paint.Cap.ROUND
        }

        fun setHot(hot: Boolean) {
            if (this.hot == hot) return
            this.hot = hot
            animate().scaleX(if (hot) 1.22f else 1.0f).scaleY(if (hot) 1.22f else 1.0f)
                .setDuration(150L).start()
            invalidate()
        }

        override fun onDraw(canvas: Canvas) {
            val d = resources.displayMetrics.density
            val cx = width / 2f
            val cy = height / 2f
            val r = (minOf(width, height) / 2f) - 4f * d
            bgPaint.color = if (hot) 0xFFB3261E.toInt() else Color.argb(210, 32, 32, 36)
            canvas.drawCircle(cx, cy, r, bgPaint)

            xPaint.color = Color.WHITE
            xPaint.strokeWidth = 2.4f * d
            val arm = 8f * d
            canvas.drawLine(cx - arm, cy - arm, cx + arm, cy + arm, xPaint)
            canvas.drawLine(cx + arm, cy - arm, cx - arm, cy + arm, xPaint)
        }
    }
}
