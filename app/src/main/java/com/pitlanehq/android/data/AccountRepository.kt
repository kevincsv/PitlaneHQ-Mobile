package com.pitlanehq.android.data

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.pitlanehq.android.model.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.net.URLEncoder
import java.security.KeyStore
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

const val SERVER = "https://pitlanehq.app"

data class AccountState(
    val signedIn: Boolean = false,
    val email: String = "",
    val display: String = "",
    val verified: Boolean = true,
    val admin: Boolean = false,         // what the screens use: false while an admin looks as a normal user
    val realAdmin: Boolean = false,     // an admin of the server, whatever the view
    val busy: Boolean = false,
    val syncedFiles: Int = 0,
    val syncVersion: Long = 0,
    val syncUpdated: Long = 0,
    val error: String? = null,
    val needCode: Boolean = false,      // the password was right: the authenticator code comes next
    val twoFactor: Boolean = false,     // two-step sign-in is on for this account
    val recoveryLeft: Int = 0,
    val supporter: Boolean = false,     // the supporter badge (donates)
    val supporterHidden: Boolean = false
)

/** What the server gives to set up two-step sign-in: the key and the otpauth link for the app. */
data class TwoFactorSetup(val secret: String, val url: String)

/** Errors the screens show in the user's language: the message is a key of I18n. */
open class AppError(key: String) : Exception(key)
class SignedOut : AppError("signed_out")
class Offline : AppError("no_internet")

/** Data from the server, or the copy saved on this phone when the server cannot be reached ([stale]). */
class Got<T>(val data: T, val stale: Boolean = false)

/**
 * The Pitlane HQ account, exactly like the PC and the web app: the password only derives the
 * keys on this phone, the server gets the login key and gives back the data key sealed with
 * the wrap key. The session token, the data key and everything saved for offline use are kept
 * sealed with an Android Keystore key.
 */
/** The model's references for a lap: the record and the next level (each a trace with its time), and the corner card. */
data class ModelRefs(val rec: Pair<Trace, Double>?, val lvl: Pair<Trace, Double>?, val corners: List<CornerCard> = emptyList())

/** What the coach learnt from everyone's tips: the tips turned off, how many drivers each bucket helped, the confidence switch. */
data class CoachInfo(val off: Set<String>, val conf: Map<String, Pair<Int, Int>>, val confidence: Boolean, val min: Int)
/** A kind of tip that repeats across the driver's tracks. */
data class Habit(val kind: String, val tracks: Int, val sessions: Int)

class AccountRepository(context: Context) {
    private val client = OkHttpClient.Builder().connectTimeout(10, TimeUnit.SECONDS).callTimeout(30, TimeUnit.SECONDS).build()
    private val prefs = context.getSharedPreferences("pitlane-account", Context.MODE_PRIVATE)
    private val app = context.getSharedPreferences("pitlane-app", Context.MODE_PRIVATE)
    private val cacheDir = File(context.filesDir, "saved").apply { mkdirs() }

    // demo data is only for the admins of the server (ADMINS), for testing
    var demo: Boolean
        get() = app.getBoolean("demo", false) && prefs.getBoolean("admin", false) && !asUser
        set(v) = app.edit().putBoolean("demo", v).apply()
    // an admin can see the app as everyone else does (to test it), on this phone
    var asUser: Boolean
        get() = app.getBoolean("asUser", false)
        set(v) = app.edit().putBoolean("asUser", v).apply()
    var language: String
        get() = app.getString("lang", "system") ?: "system"
        set(v) = app.edit().putString("lang", v).apply()

    fun storedState() = AccountState(
        signedIn = prefs.getString("token", null) != null,
        email = prefs.getString("email", "") ?: "",
        display = prefs.getString("display", "") ?: "",
        verified = prefs.getBoolean("verified", true),
        admin = prefs.getBoolean("admin", false) && !asUser,
        realAdmin = prefs.getBoolean("admin", false),
        syncedFiles = prefs.getInt("syncedFiles", 0),
        syncVersion = prefs.getLong("syncVersion", 0),
        syncUpdated = prefs.getLong("syncUpdated", 0),
        twoFactor = prefs.getBoolean("twoFactor", false),
        recoveryLeft = prefs.getInt("recoveryLeft", 0),
        supporter = prefs.getBoolean("supporter", false),
        supporterHidden = prefs.getBoolean("supporterHidden", false)
    )

    // ---------- device storage ----------
    private fun deviceKey(): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (ks.getEntry("pitlanehq-account", null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val g = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        g.init(
            KeyGenParameterSpec.Builder("pitlanehq-account", KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build()
        )
        return g.generateKey()
    }

    private fun protectBytes(v: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.ENCRYPT_MODE, deviceKey())
        return c.iv + c.doFinal(v)
    }

    private fun unprotectBytes(b: ByteArray): ByteArray {
        val c = Cipher.getInstance("AES/GCM/NoPadding")
        c.init(Cipher.DECRYPT_MODE, deviceKey(), GCMParameterSpec(128, b, 0, 12))
        return c.doFinal(b, 12, b.size - 12)
    }

    private fun protect(v: ByteArray) = Base64.encodeToString(protectBytes(v), Base64.NO_WRAP)
    private fun unprotect(v: String) = unprotectBytes(Base64.decode(v, Base64.NO_WRAP))

    /** Live: you pressed Connect for your own PC (it stays connected until Disconnect). */
    /** This phone for your PC's question (Accept / Decline): an id that stays. */
    val devId: String
        get() = prefs.getString("devId", null)?.takeIf { it.length == 16 } ?: java.util.UUID.randomUUID().toString().replace("-", "").take(16).also { prefs.edit().putString("devId", it).apply() }

    var liveOwn: Boolean
        get() = prefs.getBoolean("liveOwn", false)
        set(v) { prefs.edit().putBoolean("liveOwn", v).apply() }

    fun token(): String = runCatching { String(unprotect(prefs.getString("token", null)!!)) }.getOrElse { throw SignedOut() }
    fun dataKey(): ByteArray = runCatching { unprotect(prefs.getString("dataKey", null)!!) }.getOrElse { throw SignedOut() }

    // saved copies for offline use, sealed like the token
    private fun save(name: String, text: String) = runCatching { File(cacheDir, name).writeBytes(protectBytes(text.toByteArray())) }
    private fun saved(name: String): String? = runCatching { String(unprotectBytes(File(cacheDir, name).readBytes())) }.getOrNull()
    private fun safeName(s: String) = s.replace(Regex("[^A-Za-z0-9_.-]"), "_").take(120)

    private fun clearAll() {
        prefs.edit().clear().apply()
        cacheDir.listFiles()?.forEach { it.delete() }
    }

    // ---------- server ----------
    private fun call(method: String, path: String, body: JSONObject? = null, auth: Boolean = true): String {
        val q = Request.Builder().url(SERVER + path).method(method, body?.toString()?.toRequestBody("application/json".toMediaType()))
        if (auth) q.header("Authorization", "Bearer " + token())
        val r = try {
            client.newCall(q.build()).execute()
        } catch (e: IOException) {
            throw Offline()
        }
        r.use {
            val txt = it.body.string()
            if (it.code == 401 && auth) {
                clearAll()
                throw SignedOut()
            }
            if (!it.isSuccessful) {
                if (it.code >= 500) throw AppError("server_down")
                throw AppError(runCatching { JSONObject(txt).optString("error") }.getOrNull()?.ifBlank { null } ?: "server_down")
            }
            return txt
        }
    }

    /** A GET whose answer is saved, so the screen still has it without a connection. */
    private fun cachedGet(path: String): Got<String> = try {
        call("GET", path).also { save(safeName(path), it) }.let { Got(it) }
    } catch (e: Offline) {
        Got(saved(safeName(path)) ?: throw e, stale = true)
    } catch (e: AppError) {
        if (e.message == "server_down") Got(saved(safeName(path)) ?: throw e, stale = true) else throw e
    }

    // a sign-in waiting for its authenticator code (5 minutes): the key stays here, never stored
    private var pending: Triple<String, String, ByteArray>? = null // pending token, email, wrap key

    fun login(email0: String, password: String): AccountState {
        val email = email0.trim().lowercase()
        if (!Regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$").matches(email)) throw AppError("bad_email")
        if (password.isEmpty()) throw AppError("enter_pw")
        val k = Crypto.derive(email, password)
        val j = JSONObject(call("POST", "/account/login", JSONObject().put("email", email).put("auth", k.auth).put("device", "Android"), auth = false))
        if (j.optBoolean("twoFactor") && j.has("pending")) {
            pending = Triple(j.getString("pending"), email, k.wrap)
            return AccountState(email = email, needCode = true)
        }
        return signedIn(j, email, k.wrap)
    }

    /** Second step: the 6-digit code of the authenticator app, or a recovery code. */
    fun loginCode(code: String): AccountState {
        val p = pending ?: throw AppError("sign_in_again")
        val j = JSONObject(call("POST", "/account/login/2fa", JSONObject().put("pending", p.first).put("code", code.trim()), auth = false))
        pending = null
        return signedIn(j, p.second, p.third)
    }

    private fun signedIn(j: JSONObject, email: String, wrap: ByteArray): AccountState {
        val key = Crypto.open(wrap, j.getString("wrappedKey"), Crypto.ACCOUNT_AAD)
        require(key.size == 32) { "The account key is damaged" }
        prefs.edit()
            .putString("token", protect(j.getString("token").toByteArray()))
            .putString("dataKey", protect(key))
            .putString("email", email)
            .putString("display", j.optString("display", ""))
            .putBoolean("verified", j.optBoolean("verified", true))
            .putBoolean("admin", j.optBoolean("admin", false))
            .putBoolean("twoFactor", j.optBoolean("twoFactor", false))
            .apply()
        return runCatching { sync() }.getOrElse { storedState() }
    }

    // ---------- two-step sign-in (optional, recommended) ----------
    fun setup2fa(password: String): TwoFactorSetup {
        val k = Crypto.derive(email(), password)
        val j = JSONObject(call("POST", "/account/2fa/setup", JSONObject().put("auth", k.auth)))
        return TwoFactorSetup(j.getString("secret"), j.getString("url"))
    }

    /** Confirms the first code; gives the recovery codes (shown once). */
    fun enable2fa(code: String): List<String> {
        val j = JSONObject(call("POST", "/account/2fa/enable", JSONObject().put("code", code.trim())))
        val a = j.optJSONArray("codes") ?: JSONArray()
        prefs.edit().putBoolean("twoFactor", true).putInt("recoveryLeft", a.length()).apply()
        return List(a.length()) { a.getString(it) }
    }

    fun disable2fa(password: String, code: String) {
        val k = Crypto.derive(email(), password)
        call("POST", "/account/2fa/disable", JSONObject().put("auth", k.auth).put("code", code.trim()))
        prefs.edit().putBoolean("twoFactor", false).putInt("recoveryLeft", 0).apply()
    }

    private fun email() = prefs.getString("email", "") ?: ""

    // the inbox: which items were dismissed (ids), kept on this phone
    fun inboxSeen(): Set<String> = prefs.getStringSet("inboxSeen", emptySet()) ?: emptySet()
    fun inboxMark(ids: Collection<String>) { prefs.edit().putStringSet("inboxSeen", inboxSeen() + ids).apply() }

    /** Pulls the encrypted settings bundle the PC keeps in the account and opens it here: your races come from it. */
    fun sync(): AccountState {
        val j = JSONObject(call("GET", "/account/sync"))
        val blob = j.optString("blob", "")
        var files = 0
        if (blob.isNotEmpty()) {
            val all = JSONObject(String(Crypto.gunzip(Crypto.open(dataKey(), blob, Crypto.ACCOUNT_AAD))))
            files = all.length()
            // Go writes the files as base64 strings
            all.optString("races.json").takeIf { it.isNotEmpty() }?.let { b64 ->
                runCatching { save("races", trimRaces(JSONArray(String(Base64.decode(b64, Base64.DEFAULT))))) }
            }
            save("ratings", all.optString("ratings.json").takeIf { it.isNotEmpty() }?.let { runCatching { String(Base64.decode(it, Base64.DEFAULT)) }.getOrNull() } ?: "{}")
            save("drivers", all.optString("drivers.json").takeIf { it.isNotEmpty() }?.let { runCatching { String(Base64.decode(it, Base64.DEFAULT)) }.getOrNull() } ?: "{}")
            save("notes", all.optString("notes.json").takeIf { it.isNotEmpty() }?.let { runCatching { String(Base64.decode(it, Base64.DEFAULT)) }.getOrNull() } ?: "{}")
        }
        prefs.edit()
            .putInt("syncedFiles", files)
            .putLong("syncVersion", j.optLong("version", 0))
            .putLong("syncUpdated", j.optLong("updated", 0))
            .apply()
        runCatching {
            val me = JSONObject(call("GET", "/account/me"))
            prefs.edit().putString("display", me.optString("display", "")).putBoolean("verified", me.optBoolean("verified", true)).putBoolean("admin", me.optBoolean("admin", false))
                .putBoolean("twoFactor", me.optBoolean("twoFactor", false)).putInt("recoveryLeft", me.optInt("recoveryLeft", 0))
                .putBoolean("supporter", me.optBoolean("supporter", false)).putBoolean("supporterHidden", me.optBoolean("supporterHidden", false)).apply()
        }
        return storedState()
    }

    /** Your iRating of every discipline as the PC last saw it (ratings.json): discipline → (iRating, licence, when). */
    fun ratings(): Map<String, Triple<Int, String, Long>> {
        val o = (if (demo) null else saved("ratings"))?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return emptyMap()
        return o.keys().asSequence().mapNotNull { k -> o.optJSONObject(k)?.takeIf { it.optInt("ir") > 1 }?.let { k to Triple(it.optInt("ir"), it.optString("lic"), it.optLong("at")) } }.toMap() // 1 / "R 0.01": an offline session's placeholder
    }

    /** Your notes on other drivers, by their key (or "n:" and their name for older races). */
    fun driverNotes(): Map<String, DriverNote> {
        val o = (if (demo) prefs.getString("demoDrivers", null) else saved("drivers"))?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return emptyMap()
        return o.keys().asSequence().mapNotNull { k -> o.optJSONObject(k)?.let { k to DriverNote(it.optString("name"), it.optString("tag"), it.optString("note")) } }.toMap()
    }

    /**
     * Saves your note on a driver (no tag and no note removes it) in the account's bundle, the same file the PC
     * and the web keep: the bundle is read, only drivers.json changes, and it goes back sealed with your key.
     */
    fun setDriverNote(key: String, name: String, tag: String, note: String) {
        val k = key.takeIf { Regex("^[0-9a-f]{32}$").matches(it) } ?: nameKey(name)
        if (k.isEmpty()) return
        val nk = nameKey(name)
        val t = tag.takeIf { it in listOf("danger", "careful", "clean", "friend") } ?: ""
        val n = note.trim().take(500)
        fun change(dv: JSONObject) {
            if (nk.isNotEmpty() && nk != k) dv.remove(nk)
            if (t.isEmpty() && n.isEmpty()) dv.remove(k)
            else dv.put(k, JSONObject().put("name", name.take(80)).put("tag", t).put("note", n).put("updated", System.currentTimeMillis()))
        }
        if (demo) {
            val dv = prefs.getString("demoDrivers", null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            change(dv); prefs.edit().putString("demoDrivers", dv.toString()).apply(); return
        }
        for (attempt in 0..2) {
            val j = JSONObject(call("GET", "/account/sync"))
            val blob = j.optString("blob", "")
            val all = if (blob.isEmpty()) JSONObject() else JSONObject(String(Crypto.gunzip(Crypto.open(dataKey(), blob, Crypto.ACCOUNT_AAD))))
            val dv = all.optString("drivers.json").takeIf { it.isNotEmpty() }?.let { runCatching { JSONObject(String(Base64.decode(it, Base64.DEFAULT))) }.getOrNull() } ?: JSONObject()
            change(dv)
            all.put("drivers.json", Base64.encodeToString(dv.toString().toByteArray(), Base64.NO_WRAP))
            val sealed = Crypto.seal(dataKey(), Crypto.gzip(all.toString().toByteArray()), Crypto.ACCOUNT_AAD)
            try {
                val r = JSONObject(call("PUT", "/account/sync", JSONObject().put("blob", sealed).put("base", j.optLong("version", 0))))
                prefs.edit().putLong("syncVersion", r.optLong("version", 0)).apply()
                save("drivers", dv.toString())
                return
            } catch (e: AppError) {
                // another device wrote the account meanwhile: read it again and redo the change on top
                if (attempt == 2 || e.message?.contains("conflict", true) != true) throw e
            }
        }
    }

    /** Your notes on each track, by its id. */
    fun trackNotes(): Map<Long, TrackNote> {
        val o = (if (demo) prefs.getString("demoNotes", null) else saved("notes"))?.let { runCatching { JSONObject(it) }.getOrNull() } ?: return emptyMap()
        return o.keys().asSequence().mapNotNull { k ->
            val v = o.optJSONObject(k) ?: return@mapNotNull null
            val id = v.optLong("trackId").takeIf { it != 0L } ?: k.toLongOrNull() ?: return@mapNotNull null
            val ca = v.optJSONArray("corners") ?: JSONArray()
            val cs = (0 until ca.length()).mapNotNull { ca.optJSONObject(it) }
                .map { CornerNote(it.optInt("n"), it.optDouble("dist", 0.0), it.optString("name"), it.optString("note")) }
                .filter { it.note.isNotEmpty() }.sortedBy { it.dist }
            id to TrackNote(id, v.optString("track"), v.optString("general"), cs, v.optString("updated"))
        }.toMap()
    }

    /**
     * Saves your general note on a track in the account's bundle (its corner notes stay as they are; no note and no
     * corner removes it), like the PC and the web: only notes.json changes, and it goes back sealed with your key.
     */
    fun setTrackNote(trackId: Long, track: String, general: String) {
        if (trackId == 0L) return
        val g = general.trim().take(2000)
        val k = trackId.toString()
        fun change(nv: JSONObject) {
            val cur = nv.optJSONObject(k) ?: JSONObject().put("trackId", trackId).put("track", track.take(120))
            if (g.isEmpty()) cur.remove("general") else cur.put("general", g)
            if (cur.optString("track").isEmpty()) cur.put("track", track.take(120))
            cur.put("updated", java.time.Instant.now().toString())
            if (g.isEmpty() && (cur.optJSONArray("corners")?.length() ?: 0) == 0) nv.remove(k) else nv.put(k, cur)
        }
        if (demo) {
            val nv = prefs.getString("demoNotes", null)?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
            change(nv); prefs.edit().putString("demoNotes", nv.toString()).apply(); return
        }
        for (attempt in 0..2) {
            val j = JSONObject(call("GET", "/account/sync"))
            val blob = j.optString("blob", "")
            val all = if (blob.isEmpty()) JSONObject() else JSONObject(String(Crypto.gunzip(Crypto.open(dataKey(), blob, Crypto.ACCOUNT_AAD))))
            val nv = all.optString("notes.json").takeIf { it.isNotEmpty() }?.let { runCatching { JSONObject(String(Base64.decode(it, Base64.DEFAULT))) }.getOrNull() } ?: JSONObject()
            change(nv)
            all.put("notes.json", Base64.encodeToString(nv.toString().toByteArray(), Base64.NO_WRAP))
            val sealed = Crypto.seal(dataKey(), Crypto.gzip(all.toString().toByteArray()), Crypto.ACCOUNT_AAD)
            try {
                val r = JSONObject(call("PUT", "/account/sync", JSONObject().put("blob", sealed).put("base", j.optLong("version", 0))))
                prefs.edit().putLong("syncVersion", r.optLong("version", 0)).apply()
                save("notes", nv.toString())
                return
            } catch (e: AppError) {
                // another device wrote the account meanwhile: read it again and redo the change on top
                if (attempt == 2 || e.message?.contains("conflict", true) != true) throw e
            }
        }
    }

    private fun nameKey(name: String) = name.trim().lowercase().split(Regex("\\s+")).filter { it.isNotEmpty() }.joinToString(" ").let { if (it.isEmpty()) "" else "n:$it" }

    // only what the phone shows, newest first: races.json also has braking points and more
    private fun trimRaces(a: JSONArray): String {
        val out = (0 until a.length()).mapNotNull { a.optJSONObject(it) }
            .filter { it.optString("game", "").let { g -> g.isEmpty() || g == "iracing" } }
            .sortedByDescending { it.optLong("when") }
            .take(60)
            .map { r ->
                val laps = r.optJSONArray("laps") ?: JSONArray()
                // the race's incident total, like the web: the largest of the report's total, the laps' and the events'
                val ev = r.optJSONArray("incidents")
                val fromLaps = (0 until laps.length()).sumOf { laps.optJSONObject(it)?.optInt("i") ?: 0 }
                val fromEv = ev?.let { e -> (0 until e.length()).sumOf { e.optJSONObject(it)?.let { x -> x.optInt("pts", x.optInt("p")) } ?: 0 } } ?: 0
                r.put("inc", maxOf(r.optInt("inc"), fromLaps, fromEv))
                r.remove("brakes"); r.remove("incidents")
                val slim = JSONArray()
                for (i in 0 until laps.length()) laps.optJSONObject(i)?.let { l ->
                    slim.put(JSONObject().put("n", l.optInt("n")).put("t", l.optDouble("t")).put("p", l.optInt("p")).put("i", l.optInt("i")).put("pit", l.optBoolean("pit")).put("cut", l.optBoolean("cut")).apply { l.optString("drv").takeIf { it.isNotBlank() }?.let { put("drv", it) } })
                }
                r.put("laps", slim)
            }
        return JSONArray(out).toString()
    }

    fun races(): List<Race> {
        if (demo) return Demo.races()
        val a = saved("races")?.let { JSONArray(it) } ?: return emptyList()
        return (0 until a.length()).map { i ->
            val r = a.getJSONObject(i)
            val laps = r.optJSONArray("laps") ?: JSONArray()
            val res = r.optJSONArray("results") ?: JSONArray()
            Race(
                id = r.optString("id"), whenMs = r.optLong("when"), track = fixTxt(r.optString("track")), car = fixTxt(r.optString("car")),
                official = r.optBoolean("official"), start = r.optInt("start"), finish = r.optInt("finish"), field = r.optInt("field"),
                inc = maxOf(r.optInt("inc"), (0 until laps.length()).sumOf { laps.getJSONObject(it).optInt("i") }), best = r.optDouble("best").pos(), fieldBest = r.optDouble("fieldBest").pos(),
                avg = r.optDouble("avg").pos(), consistency = r.optDouble("consistency").pos(), pits = r.optInt("pits"),
                fuelUsed = r.optDouble("fuelUsed").pos(), ir = r.optInt("ir"), irChange = r.optInt("irChange"), sof = r.optInt("sof"),
                dnf = r.optBoolean("dnf"), cat = r.optStr("cat"),
                drinks = r.optJSONArray("drinks")?.let { d -> (0 until d.length()).map { fixTxt(d.optString(it)) }.filter { it.isNotBlank() } } ?: emptyList(),
                ai = isAIRace(r),
                laps = (0 until laps.length()).map { k -> laps.getJSONObject(k).let { RaceLap(it.optInt("n"), it.optDouble("t"), it.optInt("p"), it.optInt("i"), it.optBoolean("pit"), it.optBoolean("cut"), fixTxt(it.optString("drv"))) } },
                results = (0 until res.length()).map { k ->
                    // an offline race has only you as a real driver: everyone else there is an AI driver
                    res.getJSONObject(k).let { RaceResult(it.optInt("cpos").takeIf { p -> p > 0 } ?: it.optInt("pos"), fixTxt(it.optString("name")), it.optInt("ir"), it.optDouble("best").pos(), it.optInt("inc"), it.optInt("laps"), it.optString("k"), it.optBoolean("me"), !it.optBoolean("me") && (it.optBoolean("ai") || (isAIRace(r) && r.optInt("subsession") == 0))) }
                }.sortedBy { it.pos }
            )
        }
    }

    private fun Double.pos() = takeIf { !it.isNaN() && it > 0 }

    /** Text saved with the wrong encoding by an older PC ("AutÃ³dromo"): only the damaged pieces are repaired. */
    private val mojibake = Regex("[\u00C2-\u00DF][\u0080-\u00BF]|[\u00E0-\u00EF][\u0080-\u00BF]{2}")
    private fun fixTxt(s: String): String = mojibake.replace(s) { m ->
        val b = ByteArray(m.value.length) { m.value[it].code.toByte() }
        val d = String(b, Charsets.UTF_8)
        if (d.contains('\uFFFD')) m.value else d
    }

    fun logout() {
        runCatching { call("POST", "/account/logout") }
        clearAll()
    }

    fun devices(): List<Device> {
        val a = JSONObject(call("GET", "/account/sessions")).optJSONArray("sessions") ?: JSONArray()
        return (0 until a.length()).map { i -> a.getJSONObject(i).let { Device(it.optString("id"), it.optString("device"), it.optLong("lastSeen"), it.optBoolean("current")) } }
    }

    fun revoke(id: String) {
        call("POST", "/account/sessions/revoke", JSONObject().put("id", id))
    }

    // ---------- Discord: link it (Discord's sign-in, in the browser), show it on your profile, unlink it ----------
    fun discord(): DiscordLink = JSONObject(call("GET", "/account/discord")).let {
        DiscordLink(it.optBoolean("linked"), it.optStr("id") ?: "", it.optStr("handle") ?: "", it.optBoolean("shown"), it.optBoolean("oauth"))
    }

    /** The address of Discord's sign-in, to open in the browser. */
    fun discordStart(): String = JSONObject(call("POST", "/account/discord/start", JSONObject())).optString("url")

    fun discordShow(shown: Boolean) { call("POST", "/account/discord/show", JSONObject().put("shown", shown)) }

    fun discordUnlink() { call("POST", "/account/discord/unlink", JSONObject()) }

    // ---------- your laps (uploaded by PitlaneHQ.exe) ----------
    fun sessions(): Got<List<CloudSession>> {
        if (demo) return Got(Demo.sessions())
        val g = cachedGet("/api/sessions?limit=100")
        val a = JSONArray(g.data)
        return Got((0 until a.length()).map { i ->
            val s = a.getJSONObject(i)
            val id = s.getString("id")
            val kind = s.optString("kind").takeUnless { it == "null" } ?: ""
            CloudSession(
                id = id, started = s.optLong("started"), track = s.optString("track"),
                trackConfig = s.optString("track_config").takeUnless { it == "null" } ?: "", car = s.optString("car"),
                kind = kind, laps = s.optInt("laps"), best = s.optDouble("best").pos(),
                cat = s.optStr("cat"), lic = s.optStr("lic"),
                drvs = s.optStr("drvs")?.split(",")?.map { it.trim() }?.filter { it.isNotEmpty() } ?: emptyList(),
                ai = s.optInt("ai", 0) == 1 || offlineAI(id, kind, s.optStr("game"))
            )
        }, g.stale)
    }

    /** A session against iRacing's AI the server has no flag for (recorded by an older agent): an iRacing session
     *  without a subsession (id "t-…" after the account's "acct_…:" prefix) that is not a test is a single-player
     *  session, so against the AI. */
    private fun offlineAI(id: String, kind: String, game: String?) =
        (game == null || game == "iracing") && id.substringAfterLast(':').startsWith("t-") && !kind.contains("test", ignoreCase = true)

    // session and lap ids look like acct_<id>:<…>; the ':' stays as it is in the path
    private fun idPath(id: String) = URLEncoder.encode(id, "UTF-8").replace("+", "%20").replace("%3A", ":")

    fun laps(sessionId: String): Got<List<CloudLap>> {
        if (demo) return Got(Demo.laps(sessionId))
        val g = cachedGet("/api/sessions/" + idPath(sessionId))
        val a = JSONObject(g.data).optJSONArray("laps") ?: JSONArray()
        return Got((0 until a.length()).map { i ->
            val l = a.getJSONObject(i)
            CloudLap(l.optString("id"), l.optInt("n"), l.optDouble("time"), l.optInt("valid", 1) == 1, doubles(l.optJSONArray("sectors")), l.optInt("inc", 0), l.optStr("drv") ?: "")
        }, g.stale)
    }

    private fun doubles(a: JSONArray?) = a?.let { s -> (0 until s.length()).map { s.optDouble(it) } } ?: emptyList()

    private fun parseTrace(j: JSONObject?): Trace? {
        val d = j?.optJSONArray("d") ?: return null
        if (d.length() == 0) return null
        val x = j.optJSONArray("x")?.let { doubles(it) }
        val y = j.optJSONArray("y")?.let { doubles(it) }
        val xy = x != null && y != null && x.size == d.length() && y.size == d.length()
        return Trace(j.optDouble("bin", 10.0), (0 until d.length()).map { i -> d.getJSONArray(i).let { r -> DoubleArray(6) { k -> r.optDouble(k, 0.0) } } }, if (xy) x else null, if (xy) y else null, j.optJSONArray("inc")?.let { doubles(it) } ?: emptyList(),
            j.optJSONArray("incK")?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList(), g = if (xy) j.optJSONArray("g")?.let { doubles(it) }?.takeIf { it.size == 2 } else null)
    }

    /**
     * The model's references for a lap time, as the PC and the web take them: the record (the fastest lap really
     * driven) and the next level (the real lap of the driver just ahead, 0.3–3 % faster). Their points come every 5 m
     * (the record) or every 10 m (the next level, put back to 5 m like the web's up()); null when there is none.
     */
    fun modelRefs(trackId: Long, carId: Long, lapTime: Double): ModelRefs {
        if (demo || trackId <= 0 || carId <= 0) return ModelRefs(null, null)
        val m = runCatching { JSONObject(cachedGet("/community/model?game=iracing&trackId=$trackId&carId=$carId").data) }.getOrNull() ?: return ModelRefs(null, null)
        // the corner card: where the fastest drivers here brake and how fast they take each corner of the record lap
        val cards = m.optJSONArray("corners")?.let { a -> (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { o ->
            CornerCard(o.optDouble("d", 0.0), o.optDouble("apex", 0.0), o.optDouble("b0", 0.0), o.optDouble("b1", 0.0), o.optDouble("v0", 0.0), o.optDouble("v1", 0.0), o.optInt("n", 0)) } } ?: emptyList()
        fun row(b: JSONArray) = doubleArrayOf(b.optDouble(0, 0.0), b.optDouble(2, 0.0), b.optDouble(3, 0.0), b.optDouble(4, 0.0), 0.0, b.optDouble(1, 0.0))
        // a path with its origin g when it comes from the game's position (the apps put two paths in one frame by it)
        fun xy(o: JSONObject?, n: Int): Triple<List<Double>, List<Double>, List<Double>?>? {
            if (o == null) return null
            val x = o.optJSONArray("x")?.let { doubles(it) } ?: return null; val y = o.optJSONArray("y")?.let { doubles(it) } ?: return null
            return if (x.size == n && y.size == n) Triple(x, y, o.optJSONArray("g")?.let { doubles(it) }?.takeIf { it.size == 2 }) else null
        }
        var rec: Pair<Trace, Double>? = null
        val ideal = m.optJSONArray("ideal")
        val idealTime = m.optDouble("idealTime", 0.0)
        if (ideal != null && ideal.length() > 40 && idealTime > 0) {
            val rows = (0 until ideal.length()).mapNotNull { ideal.optJSONArray(it)?.let { b -> row(b) } }
            val p = xy(m.optJSONObject("idealXY"), rows.size) ?: xy(m.optJSONObject("lineXY"), rows.size)
            rec = Trace(5.0, rows, p?.first, p?.second, g = p?.third) to idealTime
        }
        var lvl: Pair<Trace, Double>? = null
        val lad = m.optJSONArray("ladder")
        val nb = m.optInt("nb", 0)
        if (lad != null && lad.length() > 0 && lapTime > 0) {
            val l = (0 until lad.length()).mapNotNull { lad.optJSONObject(it) }
            var i = l.indexOfFirst { lapTime <= it.optDouble("upTo", 0.0) }
            if (i < 0) i = l.size - 1
            while (i > 0 && !(l[i].optDouble("time", 0.0) < lapTime * 0.997)) i--
            val x = l[i]
            val raw = x.optJSONArray("bins")
            val t = x.optDouble("time", 0.0)
            if (raw != null && raw.length() > 20 && t > 0 && t < lapTime - 0.001) {
                val bins = (0 until raw.length()).mapNotNull { raw.optJSONArray(it) }
                val rows = ArrayList<DoubleArray>()
                bins.forEachIndexed { k, b ->
                    val a = row(b); rows.add(a)
                    val nx = bins.getOrNull(k + 1)?.let { row(it) }
                    rows.add(if (nx != null) doubleArrayOf((a[0] + nx[0]) / 2, a[1], a[2], a[3], 0.0, (a[5] + nx[5]) / 2) else a.copyOf())
                }
                val cut = if (nb > 0) rows.take(nb) else rows
                val rx = x.optJSONArray("x")?.let { doubles(it) }; val ry = x.optJSONArray("y")?.let { doubles(it) }
                var pg: List<Double>? = x.optJSONArray("g")?.let { doubles(it) }?.takeIf { it.size == 2 }
                var px: List<Double>? = null; var py: List<Double>? = null
                if (rx != null && ry != null && rx.size >= 6 && rx.size == ry.size) {
                    val ox = ArrayList<Double>(); val oy = ArrayList<Double>()
                    rx.forEachIndexed { k, v -> val n = if (k + 1 < rx.size) k + 1 else k; ox.add(v); ox.add((v + rx[n]) / 2); oy.add(ry[k]); oy.add((ry[k] + ry[n]) / 2) }
                    if (ox.size >= cut.size) { px = ox.take(cut.size); py = oy.take(cut.size) }
                }
                if (px == null) xy(m.optJSONObject("lineXY"), cut.size)?.let { px = it.first; py = it.second; pg = it.third }
                lvl = Trace(5.0, cut, px, py, g = pg) to t
            }
        }
        return ModelRefs(rec, lvl, cards)
    }

    /** A thumb on one of the coach's tips (1 up, -1 down, 0 takes it back), kept with the account on the server (coachtips.js). */
    fun rateTip(trackId: Long, carId: Long, sid: String, started: Long, n: Int, apexM: Int, kind: String, cls: String, up: Int) {
        if (demo || trackId <= 0 || carId <= 0) return
        call("POST", "/community/coach/rate", JSONObject().put("game", "iracing").put("trackId", trackId).put("carId", carId).put("sid", sid).put("started", started)
            .put("n", n).put("apex", apexM).put("kind", kind).put("cls", cls).put("up", up))
    }

    fun lapTrace(lapId: String): Trace? {
        if (demo) return Demo.trace(lapId)
        return parseTrace(JSONObject(cachedGet("/api/laps/" + idPath(lapId)).data).optJSONObject("trace"))
    }

    fun bests(): Got<List<PersonalBest>> {
        if (demo) return Got(Demo.bests())
        val g = cachedGet("/api/bests")
        val a = JSONArray(g.data)
        return Got((0 until a.length()).mapNotNull { i ->
            val b = a.getJSONObject(i)
            if (b.optString("game", "iracing") != "iracing") return@mapNotNull null
            PersonalBest(
                b.optString("track"), b.optString("track_config").takeUnless { it == "null" } ?: "", b.optString("car"),
                b.optDouble("best"), b.optInt("laps"), b.optLong("last"),
                b.optString("bestLapId").takeUnless { it.isEmpty() || it == "null" }, b.optString("bestSessionId").takeUnless { it.isEmpty() || it == "null" }
            )
        }.sortedByDescending { it.last }, g.stale)
    }

    // ---------- community ----------
    /** The card of a car: what it does on every track it was driven on (its hardest braking, where the fast drivers
     *  shift up, its top speed), learnt by the server from its laps; null when the server has no laps of it. */
    fun carCard(carId: Long): JSONObject? {
        if (demo) return null
        return runCatching { JSONObject(cachedGet("/community/car?game=iracing&carId=$carId").data) }.getOrNull()?.takeIf { it.optInt("n") > 0 }
    }
    /** A track's layout drawn by the community from clean laps (x/y of n points along the lap), null when none yet. */
    fun trackLayout(trackId: Long): Pair<List<Double>, List<Double>>? {
        if (demo || trackId <= 0) return null
        val j = runCatching { JSONObject(cachedGet("/community/trackmaps?game=iracing&trackId=$trackId").data) }.getOrNull() ?: return null
        val x = j.optJSONArray("x") ?: return null; val y = j.optJSONArray("y") ?: return null
        if (x.length() < 20 || x.length() != y.length()) return null
        return (0 until x.length()).map { x.optDouble(it) } to (0 until y.length()).map { y.optDouble(it) }
    }
    /** A track's official turns (T1 … Tn as fractions of the lap from the line), placed by an admin on its map. */
    /** What the coach learnt from everyone's tips (coachtips.js): the tips an admin turned off ("kind|cls"), how many drivers each
     *  bucket helped and whether a tip may say it; null without a connection. */
    fun coachInfo(): CoachInfo? {
        if (demo) return null
        val j = runCatching { JSONObject(cachedGet("/community/coach/weights").data) }.getOrNull() ?: return null
        val off = j.optJSONArray("off")?.let { a -> (0 until a.length()).map { a.optString(it) } }?.toSet() ?: emptySet()
        val conf = HashMap<String, Pair<Int, Int>>()
        j.optJSONArray("buckets")?.let { a -> for (i in 0 until a.length()) { val b = a.optJSONObject(i) ?: continue; conf[b.optString("kind") + "|" + b.optString("cls")] = b.optInt("win") to b.optInt("n") } }
        return CoachInfo(off, conf, j.optBoolean("confidence"), j.optInt("min", 30))
    }
    /** The driver's own memory: the kinds of tip that repeat across their tracks (habits), the most repeated first. */
    fun coachHabits(): List<Habit> {
        if (demo) return emptyList()
        val a = runCatching { JSONObject(cachedGet("/community/coach/me").data) }.getOrNull()?.optJSONArray("habits") ?: return emptyList()
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { Habit(it.optString("kind"), it.optInt("tracks"), it.optInt("sessions")) }
    }
    fun turns(trackId: Long): List<Double> {
        if (demo || trackId <= 0) return emptyList()
        val a = JSONObject(cachedGet("/community/turns?game=iracing&trackId=$trackId").data).optJSONArray("turns") ?: return emptyList()
        return (0 until a.length()).map { a.optDouble(it) }.filter { it >= 0 && it < 1 }
    }
    /** The pit lane of a track, learnt from laps through the pits (null until someone has driven through them). */
    fun pitLane(trackId: Long): com.pitlanehq.android.viewmodel.PitLane? {
        if (demo || trackId <= 0) return null
        val j = JSONObject(cachedGet("/community/pitlane?game=iracing&trackId=$trackId").data)
        val a = j.optJSONArray("pts") ?: return null
        val pts = (0 until a.length()).mapNotNull { a.optJSONArray(it)?.let { q -> q.optInt(0) to q.optDouble(1) } }
        return if (pts.size >= 10 && j.optInt("n") > 0) com.pitlanehq.android.viewmodel.PitLane(j.optInt("n"), pts) else null
    }
    fun combos(): Got<List<Combo>> {
        if (demo) return Got(Demo.combos())
        val g = cachedGet("/community/combos?game=iracing")
        val a = JSONObject(g.data).optJSONArray("combos") ?: JSONArray()
        return Got((0 until a.length()).map { i ->
            val c = a.getJSONObject(i)
            Combo(c.optLong("trackId"), c.optString("track"), c.optLong("carId"), c.optString("car"), c.optInt("laps"), c.optDouble("best").pos(), c.optStr("cat"))
        }, g.stale)
    }

    /** The records: the fastest lap of every car and track, the newest first, with the lap it beat. */
    fun records(): Got<List<RecordItem>> {
        if (demo) return Got(emptyList())
        val g = cachedGet("/community/records?game=iracing&limit=40")
        val a = JSONObject(g.data).optJSONArray("records") ?: JSONArray()
        return Got((0 until a.length()).map { recordOf(a.getJSONObject(it), 0L, "") }, g.stale)
    }

    private fun recordOf(r: JSONObject, trackId: Long, track: String): RecordItem {
        val p = r.optJSONObject("prev")
        return RecordItem(r.optString("id"), if (r.has("trackId")) r.optLong("trackId") else trackId, r.optStr("track") ?: track, r.optLong("carId"), r.optStr("car") ?: "", r.optStr("cat"),
            r.optDouble("time"), r.optLong("created"), r.optStr("alias") ?: "Driver", r.optInt("n"), r.optBoolean("hasTrace"), r.optBoolean("mine"), r.optBoolean("prof"), r.optBoolean("sup"),
            p?.optDouble("time")?.takeIf { it > 0 }, p?.optStr("alias"))
    }

    /** One track: its layout and official turns, how many drivers and laps it has, and the record of every car on it. */
    fun trackPage(trackId: Long): Got<TrackPage> {
        if (demo || trackId <= 0) return Got(TrackPage(trackId, "", 0, 0, null, emptyList(), emptyList()))
        val g = cachedGet("/community/track?game=iracing&trackId=$trackId")
        val j = JSONObject(g.data)
        val lay = j.optJSONObject("layout")?.let { l ->
            val x = l.optJSONArray("x"); val y = l.optJSONArray("y")
            if (x == null || y == null || x.length() < 20 || x.length() != y.length()) null else (0 until x.length()).map { x.optDouble(it) } to (0 until y.length()).map { y.optDouble(it) }
        }
        val turns = j.optJSONArray("turns")?.let { a -> (0 until a.length()).map { a.optDouble(it) }.filter { it >= 0 && it < 1 } } ?: emptyList()
        val name = j.optStr("track") ?: ""
        val cars = j.optJSONArray("cars") ?: JSONArray()
        return Got(TrackPage(trackId, name, j.optInt("drivers"), j.optInt("laps"), lay, turns, (0 until cars.length()).map { recordOf(cars.getJSONObject(it), trackId, name) }), g.stale)
    }

    /** One line per driver: their best lap. */
    fun leaderboard(trackId: Long, carId: Long): Got<List<CommunityLap>> {
        if (demo) return Got(Demo.board(trackId, carId))
        val g = cachedGet("/community/laps?game=iracing&trackId=$trackId&carId=$carId")
        val a = JSONObject(g.data).optJSONArray("laps") ?: JSONArray()
        val seen = HashSet<String>()
        val out = ArrayList<CommunityLap>()
        for (i in 0 until a.length()) {
            val l = a.getJSONObject(i)
            val lap = CommunityLap(l.optString("id"), l.optString("alias", "Driver"), l.optDouble("time"), l.optLong("created"), l.optBoolean("hasTrace"), doubles(l.optJSONArray("sectors")), l.optBoolean("mine"),
                l.optStr("lic"), l.optBoolean("prof"), l.optBoolean("sup"), l.optBoolean("field"))
            if (lap.alias != "Anonymous" && !seen.add(lap.alias)) continue
            out.add(lap)
        }
        return Got(out.sortedBy { it.time }, g.stale)
    }

    private fun JSONObject.optStr(k: String): String? = optString(k, "").takeUnless { it.isEmpty() || it == "null" }

    /** A driver's profile, from one of their laps on a leaderboard, or yours (lapId null). */
    fun profile(lapId: String?): DriverProfile {
        if (demo) return Demo.profile(lapId)
        val signed = runCatching { token() }.isSuccess
        val tz = -java.util.TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60000
        val j = JSONObject(call("GET", "/community/profile?" + (if (lapId == null) "me=1" else if (lapId.startsWith("acct:")) "id=" + URLEncoder.encode(lapId.removePrefix("acct:"), "UTF-8") else "lap=" + URLEncoder.encode(lapId, "UTF-8")) + "&tz=$tz", null, signed))
        val dj = j.optJSONObject("days") ?: JSONObject()
        val l = j.optJSONObject("lics") ?: JSONObject()
        val rs = j.optJSONArray("races") ?: JSONArray()
        val ls = j.optJSONArray("laps") ?: JSONArray()
        val dc = j.optJSONObject("discord")
        return DriverProfile(
            j.optString("name", "Driver"), j.optLong("since"), j.optBoolean("mine"), j.optBoolean("admin"), j.optBoolean("anonymous"), j.optBoolean("supporter"), j.optBoolean("supporterHidden"),
            l.keys().asSequence().associateWith { l.optString(it) },
            (0 until rs.length()).mapNotNull { rs.optJSONObject(it) }.map { r ->
                ProfileRace(r.optLong("when"), fixTxt(r.optString("track")), fixTxt(r.optString("car")), r.optStr("cat"), r.optStr("lic"), r.optBoolean("official"), r.optInt("start"), r.optInt("finish"), r.optInt("field"),
                    r.optInt("inc"), r.optDouble("best").pos(), r.optInt("irChange"), r.optBoolean("dnf"))
            },
            (0 until ls.length()).mapNotNull { ls.optJSONObject(it) }.map { x -> ProfileLap(fixTxt(x.optString("track")), fixTxt(x.optString("car")), x.optDouble("time"), x.optLong("created"), x.optStr("cat"), x.optStr("lic"), x.optBoolean("anon"),
                x.optLong("trackId"), x.optLong("carId"), x.optInt("pos"), x.optInt("of")) },
            dj.keys().asSequence().associateWith { dj.optInt(it) },
            dc?.optStr("id") ?: "", dc?.optStr("handle") ?: ""
        )
    }

    /** Leagues (in development: admins only for now): post one with a Discord invite, edit or remove yours. */
    @Volatile var leagueLimit = LeagueLimit()
    fun leagues(): List<League> {
        val r = JSONObject(call("GET", "/community/leagues"))
        val lim = r.optJSONObject("limits")
        leagueLimit = LeagueLimit(r.optInt("limit", 3), r.optBoolean("supporter"), lim?.optInt("free", 3) ?: 3, lim?.optInt("supporter", 10) ?: 10)
        val a = r.optJSONArray("leagues") ?: JSONArray()
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { x ->
            val ints = { k: String -> x.optJSONArray(k)?.let { a -> (0 until a.length()).map { a.optInt(it) } } ?: emptyList() }
            val strs = { k: String -> x.optJSONArray(k)?.let { a -> (0 until a.length()).map { a.optString(it) } } ?: emptyList() }
            League(x.optString("id"), fixTxt(x.optString("name")), fixTxt(x.optString("about")), x.optStr("cat"), x.optString("discord"), x.optString("web"), x.optString("schedule"), fixTxt(x.optString("cars")), x.optString("lang"), x.optBoolean("mine"), x.optString("by"),
                cats = strs("cats"), days = ints("days"), time = x.optString("time"), tz = x.optString("tz"), open = x.optBoolean("open", true), views = if (x.has("views")) x.optInt("views") else -1, clicks = if (x.has("clicks")) x.optInt("clicks") else -1,
                created = x.optLong("created"), updated = x.optLong("updated"))
        }
    }
    fun saveLeague(id: String?, l: League) {
        call("POST", "/community/leagues" + (id?.let { "/" + URLEncoder.encode(it, "UTF-8") } ?: ""), JSONObject().put("name", l.name).put("about", l.about).put("cats", JSONArray(l.cats))
            .put("days", JSONArray(l.days)).put("time", l.time).put("tz", l.tz).put("open", l.open)
            .put("discord", l.discord).put("web", l.web).put("schedule", l.schedule).put("cars", l.cars).put("lang", l.lang))
    }
    fun deleteLeague(id: String) { call("POST", "/community/leagues/" + URLEncoder.encode(id, "UTF-8"), JSONObject().put("delete", true)) }
    /** A post opened (view) or one of its links pressed (discord, web): the server counts it once per driver and day. */
    fun leagueHit(id: String, kind: String) { call("POST", "/community/leagues/" + URLEncoder.encode(id, "UTF-8") + "/hit", JSONObject().put("kind", kind)) }
    /** The creator's last 14 days of views and clicks of a post. */
    fun leagueDays(id: String): List<LeagueDay> {
        val a = JSONObject(call("GET", "/community/leagues/" + URLEncoder.encode(id, "UTF-8"))).optJSONArray("days") ?: JSONArray()
        return (0 until a.length()).mapNotNull { a.optJSONObject(it) }.map { LeagueDay(it.optString("day"), it.optInt("views"), it.optInt("clicks")) }
    }

    /** A supporter hides (or shows again) their own badge. */
    fun setBadgeHidden(hidden: Boolean) { call("POST", "/community/profile/badge", JSONObject().put("hidden", hidden)) }

    /** The owner of Pitlane HQ gives or takes away the supporter badge. */
    fun adminSupporter(id: String, on: Boolean) { call("POST", "/community/admin/supporter", JSONObject().put("id", id).put("on", on)) }
    /** "In Pitlane HQ since" by hand (null: the day the account was created). */
    fun adminSince(id: String, since: Long?) { call("POST", "/community/admin/since", JSONObject().put("id", id).put("since", since ?: JSONObject.NULL)) }
    /** The admin tools: "models" (rebuild the coach models) or "unlock" (unblock the sign-ins). */
    fun adminTool(tool: String) { call("POST", "/community/admin/$tool", if (tool == "unlock") JSONObject().put("all", true) else JSONObject()) }
    /** Help with an account: "verify", "2fa-off", "signout", "unlink-driver" or "rename" (with the new public name). */
    fun adminAccount(id: String, act: String, name: String? = null) { call("POST", "/community/admin/users/" + idPath(id) + "/" + act, JSONObject().apply { if (name != null) put("name", name) }) }
    /** Unblock one entry ("k") or one account's sign-in ("account"). */
    fun adminUnlock(key: String, value: String) { call("POST", "/community/admin/unlock", JSONObject().put(key, value)) }

    /** Your profile's recent races: a summary of your own result in each (the race history itself stays encrypted). */
    fun publishProfileRaces() {
        if (demo) return
        val a = saved("races")?.let { JSONArray(it) } ?: return
        val cats = mapOf("oval" to "oval", "dirtoval" to "dirt_oval", "dirtroad" to "dirt_road", "formulacar" to "formula_car", "sportscar" to "sports_car")
        val out = JSONArray()
        (0 until a.length()).mapNotNull { a.optJSONObject(it) }.filter { it.optInt("finish") > 0 && it.optLong("when") > 0 && !it.optBoolean("partial") && (it.optJSONArray("drinks")?.length() ?: 0) == 0 && !isAIRace(it) }
            .sortedByDescending { it.optLong("when") }.take(20).forEach { r ->
                val res = r.optJSONArray("results")
                val me = res?.let { x -> (0 until x.length()).mapNotNull { x.optJSONObject(it) }.firstOrNull { it.optBoolean("me") } }
                out.put(JSONObject().put("id", r.optString("id").replace(Regex("[^A-Za-z0-9_.:-]"), "").take(80).ifEmpty { "r" + r.optLong("when") })
                    .put("when", r.optLong("when")).put("game", r.optString("game", "iracing").ifEmpty { "iracing" }).put("track", r.optString("track")).put("car", r.optString("car"))
                    .put("cat", cats[r.optString("cat").lowercase().replace(Regex("[^a-z]"), "")] ?: JSONObject.NULL).put("lic", me?.optStr("lic") ?: JSONObject.NULL)
                    .put("official", r.optBoolean("official")).put("start", r.optInt("start")).put("finish", r.optInt("finish")).put("field", r.optInt("field"))
                    .put("inc", r.optInt("inc")).put("best", r.optDouble("best").pos() ?: JSONObject.NULL).put("laps", r.optJSONArray("laps")?.length() ?: 0)
                    .put("ir", r.optInt("ir")).put("irChange", r.optInt("irChange")).put("sof", r.optInt("sof")).put("dnf", r.optBoolean("dnf")))
            }
        val key = out.toString().hashCode()
        if (prefs.getInt("profRaces", 0) == key) return
        call("POST", "/community/profile/races", JSONObject().put("races", out))
        prefs.edit().putInt("profRaces", key).apply()
    }

    // the admin profile: accounts, and shared items with who really uploaded them
    fun adminList(kind: String): List<JSONObject> {
        if (kind == "status") return listOf(adminStatus())
        val j = JSONObject(call("GET", "/community/admin/$kind"))
        val a = j.optJSONArray(when (kind) { "users" -> "users"; "sessions" -> "sessions"; "blocked" -> "blocked"; else -> "items" }) ?: return emptyList()
        return (0 until a.length()).map { a.getJSONObject(it) }
    }
    fun adminDelete(kind: String, id: String) { call("DELETE", "/community/admin/$kind/" + idPath(id)) }
    fun adminDeleteUser(id: String) { call("DELETE", "/community/admin/users/" + idPath(id)) }
    fun adminStatus(): JSONObject = JSONObject(call("GET", "/community/admin/status"))
    // a DRINKS driver name: taken by someone else on the platform? (your own names never clash)
    fun nameFree(name: String): Boolean = runCatching { JSONObject(call("POST", "/community/name-check", JSONObject().put("name", name))).optBoolean("free", true) }.getOrDefault(true)

    fun communityTrace(id: String): Trace? {
        if (demo) return Demo.trace(id)
        return parseTrace(JSONObject(cachedGet("/community/laps/" + idPath(id)).data).optJSONObject("trace"))
    }

    fun reports(): Got<List<SharedReport>> {
        if (demo) return Got(Demo.reports())
        val g = cachedGet("/community/reports?game=iracing")
        val a = JSONObject(g.data).optJSONArray("reports") ?: JSONArray()
        return Got((0 until a.length()).map { i ->
            a.getJSONObject(i).let { SharedReport(it.optString("id"), it.optString("alias"), it.optString("track"), it.optString("car"), it.optLong("created"), it.optInt("finish"), it.optInt("field"), it.optDouble("best").pos(), it.optBoolean("mine")) }
        }, g.stale)
    }

    fun setups(): Got<List<SharedSetup>> {
        if (demo) return Got(Demo.setups())
        val g = cachedGet("/community/setups?game=iracing")
        val a = JSONObject(g.data).optJSONArray("setups") ?: JSONArray()
        return Got((0 until a.length()).map { i ->
            a.getJSONObject(i).let {
                SharedSetup(it.optString("id"), it.optString("alias"), it.optString("name"), it.optString("car"), it.optString("track").takeUnless { t -> t == "null" } ?: "",
                    it.optString("notes").takeUnless { t -> t == "null" } ?: "", it.optInt("downloads"), it.optLong("created"))
            }
        }, g.stale)
    }
}

/** A race against iRacing's AI: the PC says so, or an offline race (no subsession, its id "t-…") */
fun isAIRace(r: JSONObject): Boolean = r.optBoolean("ai") || (r.optString("game", "iracing").ifEmpty { "iracing" } == "iracing" && r.optInt("subsession") == 0 && r.optString("id").startsWith("t-"))
