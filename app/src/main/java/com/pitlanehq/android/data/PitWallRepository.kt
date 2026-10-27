package com.pitlanehq.android.data

import com.pitlanehq.android.model.Drinks
import com.pitlanehq.android.model.LIVE_VARS
import com.pitlanehq.android.model.LiveMode
import com.pitlanehq.android.model.LinkState
import com.pitlanehq.android.model.LiveState
import com.pitlanehq.android.model.LiveLaps
import com.pitlanehq.android.model.parseLiveSession
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import okhttp3.WebSocket
import okhttp3.WebSocketListener
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.TimeUnit

/**
 * Live telemetry from your PC through your Pitlane HQ account's live room (/live), the same
 * link the web app uses: works on any network, no PC address needed. Everything is sealed
 * with the account's data key (AES-256-GCM): the server only passes it along. The PC only
 * streams while a screen of yours is watching.
 */
class PitWallRepository(private val account: AccountRepository) {
    private val client = OkHttpClient.Builder().readTimeout(0, TimeUnit.MILLISECONDS).build()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var socket: WebSocket? = null
    private var loop: Job? = null
    private var fields: List<String> = emptyList()
    private val laps = LiveLaps() // the laps seen here, for DRINKS mode
    private val rec = com.pitlanehq.android.model.LiveRec() // every lap seen here, for Full and Compare laps
    private val _state = MutableStateFlow(LiveState())
    val state = _state.asStateFlow()
    // the server says another device uploaded the account (its version): the app reads it again at once
    private val _syncNudges = MutableSharedFlow<Long>(extraBufferCapacity = 8)
    val syncNudges = _syncNudges.asSharedFlow()
    // the sim your PC is reading right now ("iracing", "lmu"; null when it is not live): Home, Analysis and Community
    // mark it in their game selector. It stays while the link moves between presence and Telemetry, and goes when
    // the PC says it left the sim or went offline
    private val _pcGame = MutableStateFlow<String?>(null)
    val pcGame = _pcGame.asStateFlow()
    // what is watched: kept for your own PC (Connect stays on), never for someone's code
    private var mode = if (account.liveOwn) LiveMode.OWN else LiveMode.IDLE
    private var code = ""
    private var codeKey: ByteArray? = null
    // presence only (every screen but Telemetry): the link stays open so the server's "sync" nudge reaches
    // the phone; nothing is sent and your PC is not asked. What was watched comes back with start().
    private var presence = false
    private var savedMode = LiveMode.IDLE
    private var savedCode = ""

    /** Connect to your PC (OWN), watch a code (CODE), or Disconnect (IDLE): the link opens again the new way. */
    fun watch(m: LiveMode, c: String = "") {
        mode = m
        code = if (m == LiveMode.CODE) c else ""
        codeKey = null
        account.liveOwn = m == LiveMode.OWN
        val running = loop?.isActive == true
        stop()
        _state.value = LiveState(mode = m, code = code)
        if (running) start()
    }

    /** Your share code, made or stopped by your PC: on, new (a new code stops the old one). */
    fun share(on: Boolean, new: Boolean): Boolean {
        val ws = socket ?: return false
        if (mode != LiveMode.OWN) return false
        val key = runCatching { account.dataKey() }.getOrNull() ?: return false
        val msg = JSONArray().put("share").put(JSONObject().put("on", on).put("new", new))
        return ws.send("e:" + Crypto.seal(key, Crypto.gzip(msg.toString().toByteArray()), Crypto.LIVE_AAD))
    }

    /** Telemetry on screen: watch your PC or a code as chosen (Connect stays on). */
    fun start() {
        if (presence) { // back from presence to what was watched
            stop()
            presence = false
            mode = savedMode
            code = savedCode
            codeKey = null
            _state.value = LiveState(mode = mode, code = code)
        }
        launch()
    }

    private fun launch() {
        if (loop?.isActive == true) return
        if (account.demo) {
            // Settings → Demo data: an invented lap, nothing from the server
            loop = scope.launch {
                var tick = 0
                while (true) {
                    val s = LiveState(LinkState.OPEN, pcOnline = true, simConnected = true, values = Demo.live(tick++))
                    rec.add(s)
                    _state.value = s.copy(rec = rec, recVer = rec.ver)
                    delay(100)
                }
            }
            return
        }
        loop = scope.launch {
            var wait = 2_000L
            while (true) {
                val closed = kotlinx.coroutines.CompletableDeferred<Unit>()
                val ok = runCatching { open(closed) }.onFailure { e ->
                    _state.update { it.copy(link = LinkState.OFF, pcOnline = false, message = e.message) }
                }.isSuccess
                if (ok) {
                    // keepalive: answered by the server without waking the room
                    val ping = launch { while (true) { delay(30_000); socket?.send("ping") } }
                    // hello again every 20 s while you watch your PC, so it knows you still do
                    val hi = launch { while (true) { delay(20_000); val ws = socket; if (ws != null && mode == LiveMode.OWN) runCatching { hello(ws, account.dataKey(), false) } } }
                    closed.await()
                    ping.cancel()
                    hi.cancel()
                    if (_state.value.message == null) wait = 2_000L
                }
                if (_state.value.message == "signed_out") break
                delay(wait)
                wait = (wait * 2).coerceAtMost(30_000L)
            }
        }
    }

    fun stop() {
        loop?.cancel()
        loop = null
        socket?.close(1000, "bye")
        socket = null
        _state.value = LiveState(mode = mode, code = code)
    }

    /** Presence only, on every screen but Telemetry: the server's sync nudge reaches the phone, nothing is sent. */
    fun startPresence() {
        if (account.demo) return
        if (presence) { launch(); return }
        stop()
        presence = true
        savedMode = mode
        savedCode = code
        mode = LiveMode.IDLE
        code = ""
        codeKey = null
        _state.value = LiveState(mode = mode, code = code)
        launch()
    }

    private fun open(closed: kotlinx.coroutines.CompletableDeferred<Unit>) {
        val m = mode
        val key = if (m == LiveMode.CODE) (codeKey ?: Crypto.codeKey(code).also { codeKey = it }) else account.dataKey()
        val q = (if (m == LiveMode.IDLE) "idle" else "view") + if (m == LiveMode.CODE) "&share=" + Crypto.codeRoom(code) else ""
        val b = Request.Builder().url(SERVER.replaceFirst("http", "ws") + "/live?role=" + q).header("X-Pitlane-Client", CLIENT)
        runCatching { account.token() }.getOrNull()?.let { b.header("Authorization", "Bearer $it") }
        val req = b.build()
        _state.update { it.copy(link = LinkState.CONNECTING, message = null) }
        fields = emptyList()
        socket = null
        socket = client.newWebSocket(req, object : WebSocketListener() {
            override fun onOpen(webSocket: WebSocket, response: Response) {
                _state.update { it.copy(link = LinkState.OPEN, message = null) }
                if (m == LiveMode.OWN) hello(webSocket, key, true) else want(webSocket, key)
                // the PC sends the list of variables once: if it got lost, ask again
                scope.launch {
                    delay(3_000)
                    if (socket === webSocket && _state.value.pcOnline && fields.isEmpty()) want(webSocket, key)
                }
            }

            override fun onMessage(webSocket: WebSocket, text: String) {
                runCatching { handle(webSocket, key, text) }
            }

            override fun onClosing(webSocket: WebSocket, code: Int, reason: String) {
                webSocket.close(1000, null)
            }

            override fun onClosed(webSocket: WebSocket, code: Int, reason: String) {
                if (socket === webSocket) _state.update { it.copy(link = LinkState.OFF, pcOnline = false) }
                closed.complete(Unit)
            }

            override fun onFailure(webSocket: WebSocket, t: Throwable, response: Response?) {
                val msg = when (response?.code) {
                    401 -> "signed_out"
                    429 -> "too_many"
                    else -> "conn_lost"
                }
                if (socket === webSocket) _state.update { it.copy(link = LinkState.OFF, pcOnline = false, message = msg) }
                closed.complete(Unit)
            }
        })
    }

    /** DRINKS mode on the PC: sealed like everything else, the PC checks the account is an admin. */
    fun setDrinks(on: Boolean, guest: String, guestAuto: Boolean): Boolean =
        sendDrinks(JSONObject().put("on", on).put("guest", guest).put("guestAuto", guestAuto))

    /** A DRINKS driver gets another name (their shared laps take it too); the PC does it on the server. */
    fun renameDrinksGuest(from: String, to: String): Boolean = sendDrinks(JSONObject().put("rename", JSONObject().put("from", from).put("to", to)))

    /** A DRINKS driver off the list (what they shared stays). */
    fun forgetDrinksGuest(name: String): Boolean = sendDrinks(JSONObject().put("forget", name))

    private fun sendDrinks(body: JSONObject): Boolean {
        val ws = socket ?: return false
        val key = runCatching { account.dataKey() }.getOrNull() ?: return false
        val msg = JSONArray().put("drinks").put(body)
        return ws.send("e:" + Crypto.seal(key, Crypto.gzip(msg.toString().toByteArray()), Crypto.LIVE_AAD))
    }

    /** Connect asks your PC: it shows Accept / Decline there and sends nothing before you accept. */
    private fun hello(ws: WebSocket, key: ByteArray, fresh: Boolean) {
        if (mode != LiveMode.OWN) return
        if (fresh) _state.update { it.copy(ask = "wait", askAt = System.currentTimeMillis()) }
        val name = listOf(android.os.Build.MANUFACTURER.replaceFirstChar { it.uppercase() }, android.os.Build.MODEL).distinct().joinToString(" ").trim()
        // fresh: Connect pressed by hand, so the PC asks again even if it was declined a moment ago
        val msg = JSONArray().put("hello").put(JSONObject().put("id", account.devId).put("name", "Android · " + name.take(40)).put("again", fresh))
        ws.send("e:" + Crypto.seal(key, Crypto.gzip(msg.toString().toByteArray()), Crypto.LIVE_AAD))
    }

    /** Your PC did not answer: ask it again. */
    fun askAgain() {
        val ws = socket ?: return
        runCatching { hello(ws, account.dataKey(), true) }
    }

    private fun want(ws: WebSocket, key: ByteArray) {
        if (mode == LiveMode.OWN && _state.value.ask != "ok") return
        val msg = JSONArray().put("want").put(JSONObject().put("vars", JSONArray(LIVE_VARS)).put("all", false))
        ws.send("e:" + Crypto.seal(key, Crypto.gzip(msg.toString().toByteArray()), Crypto.LIVE_AAD))
    }

    private fun handle(ws: WebSocket, key: ByteArray, text: String) {
        if (text == "pong") return
        if (text.startsWith("{")) {
            val o = JSONObject(text)
            if (o.optString("ctl") == "sync") { _syncNudges.tryEmit(o.optLong("version")); return }
            if (o.optString("ctl") == "pc") {
                val on = o.optBoolean("on")
                if (!on) _pcGame.value = null
                if (mode == LiveMode.IDLE) { _state.update { it.copy(pcOnline = on) }; return }
                _state.update { if (on) it.copy(pcOnline = true) else it.copy(pcOnline = false, simConnected = false, values = emptyMap(), ask = "") }
                if (on) { if (mode == LiveMode.OWN) hello(ws, key, true) else want(ws, key) } // a PC that just started is asked again
            }
            return
        }
        if (!text.startsWith("e:")) return
        val a = JSONArray(String(Crypto.gunzip(Crypto.open(key, text.substring(2), Crypto.LIVE_AAD))))
        val ev = a.getString(0)
        // your PC's answer, to this phone (your devices share the room)
        if (ev == "ok" || ev == "no") {
            if (mode != LiveMode.OWN || a.optJSONObject(1)?.optString("id") != account.devId) return
            if (ev == "no") {
                watch(LiveMode.IDLE)
                _state.update { it.copy(declinedAt = System.currentTimeMillis()) }
            } else if (_state.value.ask != "ok") {
                _state.update { it.copy(ask = "ok") }
                fields = emptyList()
                want(ws, key)
            }
            return
        }
        if (mode == LiveMode.OWN && _state.value.ask != "ok") return // what your PC sends another device you accepted
        when (ev) {
            "share" -> _state.update { it.copy(myCode = a.optJSONObject(1)?.optString("code").orEmpty()) }
            "status" -> {
                val s = a.getJSONObject(1)
                val src = s.optString("source").takeIf { it in com.pitlanehq.android.model.GAMES } ?: ""
                _pcGame.value = if (s.optBoolean("connected") && !s.optBoolean("demo") && src.isNotEmpty()) src else null
                _state.update { it.copy(pcOnline = true, simConnected = s.optBoolean("connected"), source = src) }
            }
            "drinks" -> {
                val d = a.getJSONObject(1)
                val g = d.optJSONArray("guests") ?: JSONArray()
                _state.update {
                    it.copy(pcOnline = true, drinks = Drinks(
                        d.optBoolean("admin"), d.optBoolean("on"), d.optString("guest"), d.optBoolean("guestAuto"),
                        (0 until g.length()).map { i -> g.optString(i) }, d.optString("driver")
                    ))
                }
            }
            "fields" -> {
                val f = a.getJSONArray(1)
                fields = (0 until f.length()).map { f.getString(it) }
            }
            // the session YAML: who is who (the standings, the relative), the track (its map)
            "session" -> {
                val y = a.optString(1)
                if (y.isNotBlank()) _state.update { it.copy(session = runCatching { parseLiveSession(y) }.getOrNull() ?: it.session) }
            }
            "t" -> {
                val v = a.getJSONObject(1).getJSONArray("v")
                val names = fields
                val m = HashMap<String, Any?>(names.size)
                val arrs = HashMap<String, List<Double>>()
                for (i in names.indices) if (i < v.length()) {
                    val x = v.opt(i)
                    if (x is JSONArray) arrs[names[i]] = (0 until x.length()).map { k -> when (val e = x.opt(k)) { is Number -> e.toDouble(); is Boolean -> if (e) 1.0 else 0.0; else -> -1.0 } }
                    else m[names[i]] = x.takeUnless { it == JSONObject.NULL }
                }
                _state.update {
                    val s = it.copy(pcOnline = true, values = m, arrays = arrs)
                    // DRINKS mode: whoever drives against their own laps
                    val dk = s.drinks
                    val drv = if (dk != null && dk.on) dk.driver else ""
                    laps.add(s, drv)
                    rec.add(s)
                    s.copy(ownDelta = laps.delta(s, drv), ownBest = laps.bestTime(drv), rec = rec, recVer = rec.ver)
                }
            }
        }
    }
}
