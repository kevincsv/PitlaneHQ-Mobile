package com.pitlanehq.android.data

import okhttp3.OkHttpClient
import okhttp3.Request
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/** A newer Pitlane HQ for this phone: its version ("0.3.1") and where to download it. */
data class AppUpdate(val version: String, val url: String)

/** One piece of news of the app (web/dist/app-news.json on the server, edited by hand). */
data class AppNews(val id: String, val date: String, val title: String, val text: String, val url: String?, val view: String?)

/**
 * Looks at the newest build of the phone apps on the server (pitlanehq.app/dl/phones.json, the
 * same one the downloads page points to) and says whether it is newer than this app.
 */
object Updates {
    private const val API = "https://pitlanehq.app/dl/phones.json"
    private val client = OkHttpClient.Builder().callTimeout(15, TimeUnit.SECONDS).build()

    private fun parts(v: String) = v.trim().removePrefix("v").substringBefore("-").split(".").map { it.toIntOrNull() ?: 0 }

    fun newer(latest: String, current: String): Boolean {
        val a = parts(latest)
        val b = parts(current)
        for (i in 0 until maxOf(a.size, b.size)) {
            val x = a.getOrElse(i) { 0 }
            val y = b.getOrElse(i) { 0 }
            if (x != y) return x > y
        }
        return false
    }

    /** The news of the app, in the phone's language. */
    fun news(server: String, lang: String): List<AppNews> = runCatching {
        val req = Request.Builder().url("$server/app/app-news.json").header("X-Pitlane-Client", CLIENT).build()
        client.newCall(req).execute().use { r ->
            if (!r.isSuccessful) return emptyList()
            val items = JSONObject(r.body.string()).optJSONArray("items") ?: return emptyList()
            val pick = { o: org.json.JSONObject?, k: String -> o?.optString(k)?.ifBlank { null } }
            List(minOf(items.length(), 10)) { i ->
                val it = items.getJSONObject(i)
                val title = it.optJSONObject("title")
                val text = it.optJSONObject("text")
                AppNews(it.optString("id"), it.optString("date"), pick(title, lang) ?: pick(title, "en") ?: "", pick(text, lang) ?: pick(text, "en") ?: "", it.optString("url").ifBlank { null }, it.optString("view").ifBlank { null })
            }
        }
    }.getOrDefault(emptyList())

    fun check(current: String): AppUpdate? = runCatching {
        val req = Request.Builder().url(API).header("X-Pitlane-Client", CLIENT).build()
        client.newCall(req).execute().use { r ->
            if (!r.isSuccessful) return null
            val j = JSONObject(r.body.string())
            val v = j.optString("version").removePrefix("v").removeSuffix("-beta")
            // another version on the server is the one to have (the numbering started again at 0.4.1, so a
            // lower number can be the newer build)
            if (v.isEmpty() || parts(v) == parts(current)) return null
            val apk = j.optString("apk")
            AppUpdate(v, if (apk.isNotEmpty()) "https://pitlanehq.app/dl/$apk" else "https://pitlanehq.app/downloads")
        }
    }.getOrNull()
}
