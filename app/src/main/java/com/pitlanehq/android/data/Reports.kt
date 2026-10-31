package com.pitlanehq.android.data

import android.content.Context
import org.json.JSONObject
import java.io.File

/**
 * What breaks on the phone, for the admin page's Health (the server's reports.js): a crash is written to crash.txt as it
 * happens and sent (POST /community/crash) the next time the app opens; and the app's own log for "Send the app's logs"
 * in the support chat (POST /community/support/logs).
 */
object Reports {
    private fun file(ctx: Context) = File(ctx.filesDir, "crash.txt")

    /** Once, when the app starts: a crash on any thread goes to crash.txt, then the phone's own handler closes the app. */
    fun install(ctx: Context) {
        val app = ctx.applicationContext
        val prev = Thread.getDefaultUncaughtExceptionHandler()
        Thread.setDefaultUncaughtExceptionHandler { th, e ->
            runCatching {
                file(app).writeText(JSONObject().put("where", "thread:" + th.name).put("msg", (e.javaClass.name + ": " + (e.message ?: "")).take(500))
                    .put("stack", e.stackTraceToString().take(8000)).toString())
            }
            prev?.uncaughtException(th, e)
        }
    }

    /** The crash of the last run, once (the file goes). */
    fun take(ctx: Context): JSONObject? {
        val f = file(ctx)
        if (!f.exists()) return null
        val j = runCatching { JSONObject(f.readText()) }.getOrNull()
        f.delete()
        return j
    }

    /** The end of this app's own log (logcat of its process), with a line naming the app and the phone. */
    fun log(): String {
        val head = "Pitlane HQ " + com.pitlanehq.android.BuildConfig.VERSION_NAME + " · Android " + android.os.Build.VERSION.RELEASE + " · " + android.os.Build.MANUFACTURER + " " + android.os.Build.MODEL + "\n\n"
        val body = runCatching {
            val p = ProcessBuilder("logcat", "-d", "-v", "time", "-t", "800", "--pid=" + android.os.Process.myPid()).redirectErrorStream(true).start()
            p.inputStream.bufferedReader().use { it.readText() }.takeLast(400 * 1024)
        }.getOrDefault("")
        return head + body.ifBlank { "(no log)" }
    }
}
