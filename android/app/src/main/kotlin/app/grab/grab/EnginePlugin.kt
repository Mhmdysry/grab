package app.grab.grab

import android.content.Context
import android.media.MediaScannerConnection
import android.os.Build
import android.os.Environment
import android.os.Handler
import android.os.Looper
import com.yausername.ffmpeg.FFmpeg
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

/**
 * Bridge between Dart and yt-dlp (via youtubedl-android).
 *
 * Methods on "grab/engine":
 *   init()                              -> yt-dlp version
 *   update()                            -> "updated" | "already_up_to_date" | null
 *   fetch(url)                          -> yt-dlp JSON (--dump-single-json) as a string
 *   download(id, url, args, suffix, match, title) -> starts a job; results come as events
 *   cancel(id)                          -> Boolean
 *   outputDir()                         -> folder files are saved in
 *
 * Events on "grab/engine/progress": maps with id, status, progress, eta, line, paths, error.
 * status: starting | running | done | canceled | error
 */
class EnginePlugin(private val context: Context, messenger: BinaryMessenger) {
    private val main = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    init {
        MethodChannel(messenger, "grab/engine").setMethodCallHandler { call, result -> handle(call, result) }
        EventChannel(messenger, "grab/engine/progress").setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) { sink = events }
            override fun onCancel(arguments: Any?) { sink = null }
        })
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> background(result) {
                ensureReady(context)
                YoutubeDL.getInstance().versionName(context)
                    ?: YoutubeDL.getInstance().execute(YoutubeDLRequest(emptyList()).apply { addOption("--version") }).out.trim()
            }
            "update" -> background(result) {
                ensureReady(context)
                when (YoutubeDL.getInstance().updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)) {
                    YoutubeDL.UpdateStatus.DONE -> "updated"
                    YoutubeDL.UpdateStatus.ALREADY_UP_TO_DATE -> "already_up_to_date"
                    else -> null
                }
            }
            "fetch" -> {
                val url = call.argument<String>("url")!!
                background(result) {
                    ensureReady(context)
                    val req = YoutubeDLRequest(url)
                    // Keep the cookies the site hands out, so the preview player
                    // can open the video the way yt-dlp did (TikTok needs them).
                    val jar = File(context.cacheDir, "preview-cookies.txt")
                    jar.writeText("# Netscape HTTP Cookie File\n")
                    req.addOption("--cookies", jar.absolutePath)
                    req.addOption("--dump-single-json")
                    req.addOption("--no-warnings")
                    req.addOption("--flat-playlist")
                    // Big channels and profiles: list the newest 300 items.
                    req.addOption("--playlist-items", "1:300")
                    val json = YoutubeDL.getInstance().execute(req).out
                    // Hand back the JSON plus the cookie jar, split by a marker line.
                    json + "\n\u0000GRAB-COOKIES\u0000\n" + (if (jar.exists()) jar.readText() else "")
                }
            }
            // A small low-quality copy in the cache, for sites that refuse direct
            // playback (TikTok). Returns the file path.
            "previewFile" -> {
                val url = call.argument<String>("url")!!
                background(result) {
                    ensureReady(context)
                    val dir = File(context.cacheDir, "preview").apply {
                        deleteRecursively()
                        mkdirs()
                    }
                    val req = YoutubeDLRequest(url)
                    req.addOption("-f", "w[vcodec!=none][acodec!=none][ext=mp4]/w[vcodec!=none][acodec!=none]/w")
                    req.addOption("-o", File(dir, "preview.%(ext)s").absolutePath)
                    req.addOption("--no-playlist")
                    req.addOption("--no-part")
                    req.addOption("--print", "after_move:filepath")
                    req.addOption("--no-simulate")
                    YoutubeDL.getInstance().execute(req).out.lines()
                        .map { it.trim() }.lastOrNull { it.isNotEmpty() && File(it).exists() }
                        ?: dir.listFiles()?.firstOrNull()?.absolutePath
                }
            }
            "download" -> {
                val job = Job(
                    id = call.argument<String>("id")!!,
                    url = call.argument<String>("url")!!,
                    args = call.argument<List<String>>("args") ?: emptyList(),
                    suffix = call.argument<String>("suffix") ?: "",
                    match = call.argument<String>("match"),
                    template = call.argument<String>("template").orEmpty(),
                    title = call.argument<String>("title") ?: "Download",
                )
                if (active.putIfAbsent(job.id, job.title to 0f) == null) {
                    pool.execute { runDownload(job) }
                }
                result.success(null)
            }
            "activeIds" -> result.success(active.keys.toList())
            "extractAudio" -> {
                val id = call.argument<String>("id")!!
                val input = call.argument<String>("input")!!
                val format = call.argument<String>("format") ?: "mp3"
                val title = call.argument<String>("title") ?: File(input).nameWithoutExtension
                pool.execute { runExtract(id, File(input), format, title) }
                result.success(null)
            }
            "cancel" -> {
                val id = call.argument<String>("id")!!
                val local = processes.remove(id)
                if (local != null) {
                    local.destroy()
                    result.success(true)
                } else {
                    result.success(YoutubeDL.getInstance().destroyProcessById(id))
                }
            }
            "outputDir" -> result.success(outputDir().absolutePath)
            "setOutputDir" -> {
                val base = call.argument<String>("base") ?: "download"
                val folder = (call.argument<String>("folder") ?: "Grab")
                    .replace(Regex("[\\\\/:*?\"<>|]"), " ").trim().take(40).ifEmpty { "Grab" }
                prefs.edit().putString("base", base).putString("folder", folder).apply()
                result.success(outputDir().absolutePath)
            }
            else -> result.notImplemented()
        }
    }

    private data class Job(
        val id: String,
        val url: String,
        val args: List<String>,
        val suffix: String,
        val match: String?,
        val title: String,
        /** yt-dlp output name without extension; blank = "%(title).80B [%(id)s]". */
        val template: String = "",
    )

    private val prefs by lazy { context.getSharedPreferences("grab_engine", Context.MODE_PRIVATE) }

    /** Where files go: a public folder (Download, Movies or Music) plus a folder name. */
    private fun outputDir(): File {
        val base = when (prefs.getString("base", "download")) {
            "movies" -> Environment.DIRECTORY_MOVIES
            "music" -> Environment.DIRECTORY_MUSIC
            else -> Environment.DIRECTORY_DOWNLOADS
        }
        val name = prefs.getString("folder", "Grab").orEmpty().ifBlank { "Grab" }
        val dir = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            File(Environment.getExternalStoragePublicDirectory(base), name)
        } else {
            File(context.getExternalFilesDir(base), name)
        }
        dir.mkdirs()
        return dir
    }

    private fun runDownload(job: Job) {
        emit(mapOf("id" to job.id, "status" to "starting"))
        active[job.id] = job.title to 0f
        refreshService()
        val startedAt = System.currentTimeMillis() - 2_000
        var finishedOk: Boolean? = null
        try {
            ensureReady(context)
            val dir = outputDir()
            val req = YoutubeDLRequest(job.url)
            val name = job.template.ifBlank { "%(title).80B [%(id)s]" }
            req.addOption("-o", File(dir, "$name${job.suffix}.%(ext)s").absolutePath)
            req.addOption("--no-mtime")
            req.addOption("--no-playlist")
            req.addOption("--print", "after_move:filepath")
            req.addOption("--no-simulate")
            // --print turns on quiet mode, which hides the progress lines the
            // percentage is read from. Ask for them back, one per line.
            req.addOption("--progress")
            req.addOption("--newline")
            // Faster: fetch 4 pieces of a video at once (DASH/HLS), and request
            // big files in 10 MB chunks, which avoids YouTube's per-request throttling.
            req.addOption("--concurrent-fragments", "4")
            req.addOption("--http-chunk-size", "10M")
            for (a in job.args) req.addOption(a)
            val resp = YoutubeDL.getInstance().execute(req, job.id) { progress, eta, line ->
                active[job.id] = job.title to progress
                refreshService()
                val speed = speedRegex.find(line ?: "")?.groupValues?.get(1)
                emit(mapOf("id" to job.id, "status" to "running", "progress" to progress.toDouble(), "eta" to eta, "line" to line, "speed" to speed))
            }
            val paths = collectOutputs(dir, resp.out, job.match, startedAt)
            if (paths.isNotEmpty()) MediaScannerConnection.scanFile(context, paths.toTypedArray(), null, null)
            emit(mapOf("id" to job.id, "status" to "done", "progress" to 100.0, "paths" to paths))
            finishedOk = true
        } catch (e: YoutubeDL.CanceledException) {
            emit(mapOf("id" to job.id, "status" to "canceled"))
        } catch (e: Throwable) {
            val msg = e.message ?: e.toString()
            emit(mapOf("id" to job.id, "status" to "error", "error" to msg))
            // Connection drops are retried by the app, so don't announce a failure for them.
            if (!networkError.containsMatchIn(msg)) {
                finishedOk = false
            }
        } finally {
            active.remove(job.id)
            refreshService()
            finishedOk?.let { ok ->
                main.post { DownloadService.notifyFinished(context, job.id, job.title, ok = ok) }
            }
        }
    }

    /** "[download]  42.0% of 120.50MiB at 2.30MiB/s ETA 00:41" -> "2.30MiB/s" */
    private val speedRegex = Regex("at\\s+([\\d.]+\\s*[KMG]?i?B/s)")

    private val networkError = Regex(
        "Unable to download|timed out|time out|Connection (reset|refused|aborted)|Network is unreachable|" +
            "No route to host|Temporary failure in name resolution|getaddrinfo|Name or service not known|" +
            "No address associated|Remote end closed|IncompleteRead|Software caused connection abort|HTTP Error 5\\d\\d|SSL|EOF occurred",
        RegexOption.IGNORE_CASE,
    )

    /**
     * Extracts the audio of a file already on the phone with the bundled FFmpeg,
     * so nothing has to be fetched again. Reports progress like a download.
     */
    private fun runExtract(id: String, input: File, format: String, title: String) {
        emit(mapOf("id" to id, "status" to "starting"))
        active[id] = title to 0f
        refreshService()
        var finishedOk = false
        try {
            ensureReady(context)
            if (!input.exists()) throw IllegalStateException("The file is no longer on the phone")
            val output = uniqueFile(input.parentFile!!, input.nameWithoutExtension, format)
            val codec = when (format) {
                "m4a" -> listOf("-c:a", "aac", "-b:a", "192k")
                "opus" -> listOf("-c:a", "libopus", "-b:a", "160k")
                "flac" -> listOf("-c:a", "flac")
                else -> listOf("-c:a", "libmp3lame", "-q:a", "0")
            }
            val cmd = listOf(File(context.applicationInfo.nativeLibraryDir, "libffmpeg.so").absolutePath,
                "-hide_banner", "-nostdin", "-y", "-i", input.absolutePath, "-vn", "-map", "0:a:0") +
                codec + output.absolutePath
            val packages = File(context.noBackupFilesDir, "youtubedl-android/packages")
            val pb = ProcessBuilder(cmd).redirectErrorStream(true)
            pb.environment()["LD_LIBRARY_PATH"] =
                "${File(packages, "python/usr/lib").absolutePath}:${File(packages, "ffmpeg/usr/lib").absolutePath}"
            val process = pb.start()
            processes[id] = process

            // FFmpeg prints "Duration: 00:01:02.50" once, then "time=00:00:31.20" as it goes.
            var totalSec = 0.0
            val log = StringBuilder()
            process.inputStream.bufferedReader().forEachLine { line ->
                if (log.length < 8000) log.appendLine(line)
                Regex("Duration: (\\d+):(\\d+):([\\d.]+)").find(line)?.let { totalSec = seconds(it) }
                Regex("time=(\\d+):(\\d+):([\\d.]+)").find(line)?.let {
                    if (totalSec > 0) {
                        val p = (seconds(it) / totalSec * 100).coerceIn(0.0, 100.0).toFloat()
                        active[id] = title to p
                        refreshService()
                        emit(mapOf("id" to id, "status" to "running", "progress" to p.toDouble(), "line" to line.trim()))
                    }
                }
            }
            val code = process.waitFor()
            val canceled = processes.remove(id) == null
            when {
                canceled -> { output.delete(); emit(mapOf("id" to id, "status" to "canceled")) }
                code != 0 -> {
                    output.delete()
                    val reason = log.lines().lastOrNull { it.isNotBlank() && !it.startsWith("size=") } ?: "FFmpeg exited with $code"
                    throw IllegalStateException(if (log.contains("does not contain any stream") || log.contains("matches no streams"))
                        "This file has no audio track" else reason)
                }
                else -> {
                    MediaScannerConnection.scanFile(context, arrayOf(output.absolutePath), null, null)
                    emit(mapOf("id" to id, "status" to "done", "progress" to 100.0, "paths" to listOf(output.absolutePath)))
                    finishedOk = true
                }
            }
        } catch (e: Throwable) {
            emit(mapOf("id" to id, "status" to "error", "error" to (e.message ?: e.toString())))
        } finally {
            processes.remove(id)
            active.remove(id)
            refreshService()
            if (finishedOk) {
                main.post { DownloadService.notifyFinished(context, id, title, ok = true) }
            }
        }
    }

    private fun seconds(m: MatchResult): Double {
        val (h, min, s) = m.destructured
        return h.toDouble() * 3600 + min.toDouble() * 60 + s.toDouble()
    }

    /** "name.mp3", or "name (audio).mp3", "name (audio 2).mp3"… if taken. */
    private fun uniqueFile(dir: File, base: String, ext: String): File {
        var f = File(dir, "$base.$ext")
        var n = 1
        while (f.exists()) {
            f = File(dir, if (n == 1) "$base (audio).$ext" else "$base (audio $n).$ext")
            n++
        }
        return f
    }

    /**
     * The media file comes from yt-dlp's --print output. Subtitle files (.srt) are not printed,
     * so we also pick up files written during this job whose name carries the item's id.
     */
    private fun collectOutputs(dir: File, out: String, match: String?, since: Long): List<String> {
        val printed = out.lines().map { it.trim() }.filter { it.isNotEmpty() && File(it).exists() }
        // Subtitles share the media file's name ("<name>.en.srt"), and older names carry "[id]".
        val keys = (printed.map { File(it).nameWithoutExtension + "." } + listOfNotNull(match)).filter { it.isNotEmpty() }
        val fresh = dir.listFiles().orEmpty()
            .filter { it.isFile && it.lastModified() >= since && !it.name.endsWith(".part") }
        var extra = fresh.filter { f -> keys.any { f.name.contains(it) } }.map { it.absolutePath }
        if (printed.isEmpty() && extra.isEmpty()) {
            // Subtitles-only with a name template that has no id: take the new subtitle files.
            extra = fresh.filter { it.extension in setOf("srt", "vtt", "ass") }.map { it.absolutePath }
        }
        return (printed + extra).distinct()
    }

    private fun refreshService() {
        val snapshot = active.values.toList()
        main.post { DownloadService.update(context, snapshot) }
    }

    private fun emit(event: Map<String, Any?>) = main.post { sink?.success(event) }

    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        pool.execute {
            try {
                val value = work()
                main.post { result.success(value) }
            } catch (e: Throwable) {
                main.post { result.error("engine", e.message ?: e.toString(), null) }
            }
        }
    }

    companion object {
        private val pool = Executors.newCachedThreadPool()
        @Volatile private var ready = false

        /** Active jobs across all engines in this process: id -> (title, progress). */
        private val active = ConcurrentHashMap<String, Pair<String, Float>>()

        /** FFmpeg processes started by [runExtract], so they can be canceled. */
        private val processes = ConcurrentHashMap<String, Process>()

        @Synchronized
        private fun ensureReady(context: Context) {
            if (ready) return
            val app = context.applicationContext
            YoutubeDL.getInstance().init(app)
            FFmpeg.getInstance().init(app)
            ready = true
        }
    }
}
