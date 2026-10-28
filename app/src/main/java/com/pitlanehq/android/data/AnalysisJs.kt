package com.pitlanehq.android.data

import android.content.Context
import androidx.javascriptengine.JavaScriptIsolate
import androidx.javascriptengine.JavaScriptSandbox
import com.pitlanehq.android.model.JsAnalysis
import com.pitlanehq.android.model.JsResult
import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.io.File
import java.util.concurrent.TimeUnit

/**
 * The web's lap analysis and coach on the phone: web/dist/pitwall-analysis.js, the file the PC app and pitlanehq.app run,
 * evaluated in Android's JavaScriptSandbox, so the corners, tips, plan and sectors are the PC's. The newest copy comes from
 * pitlanehq.app (at most every six hours, its ETag says when nothing changed) and is kept on disk; the copy in the app
 * (assets, refreshed from the Pitwall-test repository with tools/sync-analysis.sh) is used until a download succeeds.
 * Null from [analyse] when the phone cannot run it (an old WebView without the sandbox): the screens fall back to LapMath.
 */
class AnalysisJs(private val context: Context, private val client: OkHttpClient) {
    companion object {
        const val NAME = "pitwall-analysis.js"
        const val URL = "https://pitlanehq.app/$NAME"
        private const val EVERY = 6 * 3600_000L
    }
    private val file = File(context.filesDir, NAME)
    private val prefs = context.getSharedPreferences("pitlane-analysis", Context.MODE_PRIVATE)
    private var sandbox: JavaScriptSandbox? = null
    private var isolate: JavaScriptIsolate? = null
    private var loaded = ""        // the copy the isolate has evaluated (its length and hash)
    private var failures = 0       // the engine failing again and again: the fallback for the rest of the run
    private val fetching = java.util.concurrent.atomic.AtomicBoolean(false)

    // a copy that is the module and gives the shape this app reads (its VERSION); a newer shape is never kept nor run
    private val version = Regex("\\bVERSION\\s*=\\s*" + JsAnalysis.VERSION + "\\b")
    private fun valid(s: String) = s.length > 2000 && s.contains("PW_ANALYSIS") && version.containsMatchIn(s)

    /** The file to run: the downloaded copy when there is a good one, else the app's own. */
    private fun source(): String = runCatching { file.readText() }.getOrNull()?.takeIf(::valid)
        ?: context.assets.open(NAME).bufferedReader().use { it.readText() }

    /** Downloads the newest copy from pitlanehq.app, at most every six hours; nothing changes when it fails. */
    fun refresh() {
        val now = System.currentTimeMillis()
        if (now - prefs.getLong("at", 0L) < EVERY && file.exists()) return
        prefs.edit().putLong("at", now).apply()
        runCatching {
            val rq = Request.Builder().url(URL).apply { prefs.getString("etag", null)?.takeIf { file.exists() }?.let { header("If-None-Match", it) } }.build()
            client.newCall(rq).execute().use { r ->
                if (r.code == 304 || !r.isSuccessful) return
                val body = r.body.string()
                if (!valid(body)) return
                val tmp = File(context.filesDir, "$NAME.tmp")
                tmp.writeText(body)
                if (synchronized(this) { tmp.renameTo(file) }) prefs.edit().putString("etag", r.header("ETag")).apply()
            }
        }
    }

    private fun close() {
        runCatching { isolate?.close() }; runCatching { sandbox?.close() }
        isolate = null; sandbox = null; loaded = ""
    }

    /** Evaluates [codes] in order after the file (once per isolate); the last one's result as a string, or null when the
     *  engine cannot. */
    @Synchronized
    private fun run(codes: List<String>): String? {
        if (failures >= 3 || !JavaScriptSandbox.isSupported()) return null
        return try {
            val sb = sandbox ?: JavaScriptSandbox.createConnectedInstanceAsync(context).get(15, TimeUnit.SECONDS).also { sandbox = it }
            // without this feature a call is limited by Android's transaction size: a long lap pair goes to the fallback
            if (codes.any { it.length > 400_000 } && !sb.isFeatureSupported(JavaScriptSandbox.JS_FEATURE_EVALUATE_WITHOUT_TRANSACTION_LIMIT)) return null
            val src = source()
            val key = src.length.toString() + ":" + src.hashCode()
            var iso = isolate
            if (iso == null || loaded != key) {
                runCatching { iso?.close() }
                iso = sb.createIsolate()
                iso.evaluateJavaScriptAsync(src + "\n;typeof PW_ANALYSIS").get(15, TimeUnit.SECONDS)
                isolate = iso; loaded = key
            }
            var out = ""
            for (code in codes) out = iso.evaluateJavaScriptAsync(code).get(20, TimeUnit.SECONDS)
            out.also { failures = 0 }
        } catch (e: Throwable) {
            failures++
            close()
            null
        }
    }

    /** Lap A against lap B as the web analyses them, with the session's [laps] (JsAnalysis.sessionLap) for the coach's plan,
     *  or null (the screens then use LapMath). Call it off the main thread. */
    fun analyse(a: JSONObject, b: JSONObject, ctx: JSONObject, laps: List<JSONObject> = emptyList()): Map<String, JsResult>? {
        // the newest copy is fetched beside it, never in the way: this run uses the one on disk, the next one the new
        if (!fetching.getAndSet(true)) Thread { try { refresh() } finally { fetching.set(false) } }.start()
        return run(JsAnalysis.calls(a, b, ctx, laps))?.let { JsAnalysis.parse(it) }
    }
}
