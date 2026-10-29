package com.pitlanehq.android.model

import java.security.MessageDigest

/** One driver of the live session, from the session YAML the PC sends (DriverInfo → Drivers). */
data class LiveDriver(
    val idx: Int, val name: String, val number: String, val cls: String, val ir: Int, val lic: String,
    val pace: Boolean, val spectator: Boolean, val ai: Boolean, val key: String, val cc: String = ""
)

/** What the session YAML says that the Telemetry screens need: who is who, the track, the session kinds. */
data class LiveSession(
    val me: Int = -1, val estLap: Double = 0.0, val track: String = "", val trackId: Long = 0, val trackLen: Double = 0.0,
    val drivers: Map<Int, LiveDriver> = emptyMap(), val kinds: Map<Int, String> = emptyMap(), val laps: Map<Int, Int> = emptyMap()
)

/** A car in the standings or the relative: its place, its gap (s) and how many laps up (+) or down (−) on you. */
data class LiveRow(
    val idx: Int, val pos: Int, val d: LiveDriver?, val gap: Double?, val last: Double?, val best: Double?,
    val lapDiff: Double, val pit: Boolean, val me: Boolean, val pen: Boolean = false
)

/** the flag of a country by its ISO 3166 alpha-2 code ("ES" → 🇪🇸; "GB-ENG", "GB-SCT", "GB-WLS" their own), "" when unknown */
fun countryFlag(code: String): String {
    val c = code.trim().uppercase()
    SUBDIVISION_FLAGS[c]?.let { return it }
    if (c.length != 2 || !c.all { it in 'A'..'Z' }) return ""
    return c.map { String(Character.toChars(0x1F1E6 + (it - 'A'))) }.joinToString("")
}

private fun tagFlag(sub: String): String =
    String(Character.toChars(0x1F3F4)) + sub.lowercase().map { String(Character.toChars(0xE0000 + it.code)) }.joinToString("") + String(Character.toChars(0xE007F))

private val SUBDIVISION_FLAGS = mapOf("GB-ENG" to tagFlag("gbeng"), "GB-SCT" to tagFlag("gbsct"), "GB-WLS" to tagFlag("gbwls"))

private val COUNTRY_ALIASES = mapOf(
    "usa" to "US", "united states of america" to "US", "uk" to "GB", "great britain" to "GB", "northern ireland" to "GB",
    "england" to "GB-ENG", "scotland" to "GB-SCT", "wales" to "GB-WLS", "korea" to "KR", "south korea" to "KR",
    "korea, republic of" to "KR", "republic of korea" to "KR", "russia" to "RU", "russian federation" to "RU", "czech republic" to "CZ",
    "czechia" to "CZ", "the netherlands" to "NL", "holland" to "NL", "turkey" to "TR", "türkiye" to "TR", "turkiye" to "TR",
    "vietnam" to "VN", "viet nam" to "VN", "iran" to "IR", "taiwan" to "TW", "hong kong" to "HK", "macau" to "MO", "macao" to "MO",
    "ivory coast" to "CI", "cote d'ivoire" to "CI", "côte d’ivoire" to "CI", "bosnia" to "BA", "bosnia and herzegovina" to "BA",
    "slovak republic" to "SK", "uae" to "AE", "moldova" to "MD", "venezuela" to "VE", "bolivia" to "BO", "syria" to "SY", "laos" to "LA",
    "north macedonia" to "MK", "macedonia" to "MK", "brunei" to "BN", "palestine" to "PS", "vatican" to "VA", "tanzania" to "TZ"
)

private val COUNTRY_NAMES: Map<String, String> by lazy {
    java.util.Locale.getISOCountries().associateBy { java.util.Locale("", it).getDisplayCountry(java.util.Locale.ENGLISH).lowercase() }
}

/** a driver's country as iRacing's flair names it ("Spain", "United States"), or already a code, to its ISO code ("" unknown) */
fun countryCode(nameOrCode: String): String {
    val v = nameOrCode.trim()
    if (v.isEmpty()) return ""
    if (v.length == 2 && v.all { it.isLetter() }) return v.uppercase()
    if (SUBDIVISION_FLAGS.containsKey(v.uppercase())) return v.uppercase()
    val k = v.lowercase()
    return COUNTRY_ALIASES[k] ?: COUNTRY_NAMES[k] ?: ""
}

/** iRacing's CarIdxSessionFlags: the black flag (a penalty to serve) and the furled black (a slowdown) */
private const val FLAG_BLACK = 0x00010000
private const val FLAG_FURLED = 0x00080000

/** this car has a penalty or a slowdown to serve: iRacing's black or furled flag on it, or the game's penalty count (LMU) */
private fun LiveState.penalty(i: Int): Boolean {
    val f = arr("CarIdxSessionFlags").at(i)?.toLong() ?: 0L
    if (f and (FLAG_BLACK or FLAG_FURLED).toLong() != 0L) return true
    return (arr("CarIdxNumPenalties").at(i) ?: 0.0) > 0
}

private fun yField(block: String, key: String): String =
    Regex("(?m)^\\s*" + Regex.escape(key) + ":\\s*(.*)$").find(block)?.groupValues?.get(1)?.trim()?.trim('"') ?: ""

/** a top-level section of the YAML ("DriverInfo:" and what follows until the next top-level key) */
private fun ySection(y: String, name: String): String {
    val at = if (y.startsWith("$name:")) 0 else y.indexOf("\n$name:").let { if (it < 0) return "" else it + 1 }
    val lines = y.substring(at).split('\n')
    val sb = StringBuilder(lines[0]).append('\n')
    for (k in 1 until lines.size) {
        val l = lines[k]
        if (l.isNotEmpty() && !l[0].isWhitespace()) break
        sb.append(l).append('\n')
    }
    return sb.toString()
}

/** the items of a YAML list whose entries start with "- key:" */
private fun yItems(section: String, key: String): List<String> {
    val out = mutableListOf<String>()
    var cur: StringBuilder? = null
    for (l in section.split('\n')) {
        if (l.trimStart().startsWith("- $key:")) {
            cur?.let { out.add(it.toString()) }
            cur = StringBuilder(l.replaceFirst("- ", "  ")).append('\n')
        } else cur?.append(l)?.append('\n')
    }
    cur?.let { out.add(it.toString()) }
    return out
}

/** The community's opaque key of a driver (the PC's driverKey): what your driver notes find them by. */
fun driverKey(userId: String): String {
    val u = userId.trim()
    if (u.isEmpty() || u == "-1" || u == "0") return ""
    val h = MessageDigest.getInstance("SHA-256").digest(("pitlanehq-other|$u").toByteArray())
    return h.take(16).joinToString("") { "%02x".format(it) }
}

fun parseLiveSession(y: String): LiveSession {
    val di = ySection(y, "DriverInfo")
    val wi = ySection(y, "WeekendInfo")
    val si = ySection(y, "SessionInfo")
    val drivers = yItems(di, "CarIdx").mapNotNull { b ->
        val i = yField(b, "CarIdx").toIntOrNull() ?: return@mapNotNull null
        i to LiveDriver(
            i, yField(b, "UserName"), yField(b, "CarNumber"), yField(b, "CarClassShortName"), yField(b, "IRating").toIntOrNull() ?: 0,
            yField(b, "LicString"), yField(b, "CarIsPaceCar") == "1", yField(b, "IsSpectator") == "1", yField(b, "CarIsAI") == "1",
            driverKey(yField(b, "UserID")), countryCode(yField(b, "FlairName"))
        )
    }.toMap()
    val ses = yItems(si, "SessionNum")
    return LiveSession(
        me = yField(di, "DriverCarIdx").toIntOrNull() ?: -1,
        estLap = yField(di, "DriverCarEstLapTime").toDoubleOrNull() ?: 0.0,
        track = yField(wi, "TrackDisplayName") + yField(wi, "TrackConfigName").let { if (it.isNotBlank()) " · $it" else "" },
        trackId = yField(wi, "TrackID").toLongOrNull() ?: 0,
        trackLen = (Regex("[0-9.]+").find(yField(wi, "TrackLength"))?.value?.toDoubleOrNull() ?: 0.0) * 1000,
        drivers = drivers,
        kinds = ses.mapNotNull { b -> yField(b, "SessionNum").toIntOrNull()?.let { it to yField(b, "SessionType") } }.toMap(),
        laps = ses.mapNotNull { b -> yField(b, "SessionNum").toIntOrNull()?.let { n -> yField(b, "SessionLaps").toIntOrNull()?.let { n to it } } }.toMap()
    )
}

private fun LiveState.arr(n: String): List<Double> = arrays[n] ?: emptyList()
private fun List<Double>.at(i: Int): Double? = if (i in indices) this[i] else null

/** your car (the stream's PlayerCarIdx, else the session's DriverCarIdx) */
fun LiveState.meIdx(): Int = num("PlayerCarIdx")?.toInt() ?: session?.me ?: -1

/** an estimate of the lap time, for the gaps of the relative */
fun LiveState.estLap(): Double = session?.estLap?.takeIf { it > 0 } ?: num("LapBestLapTime")?.takeIf { it > 0 } ?: num("LapLastLapTime")?.takeIf { it > 0 } ?: 100.0

private fun LiveState.lapDiff(i: Int, me: Int): Double {
    val lap = arr("CarIdxLap"); val pct = arr("CarIdxLapDistPct")
    val a = (lap.at(i) ?: 0.0) + (pct.at(i) ?: 0.0); val b = (lap.at(me) ?: 0.0) + (pct.at(me) ?: 0.0)
    return a - b
}

/** The standings: every car with a place, in order, with its gap to the leader, last and best lap. */
fun LiveState.standings(): List<LiveRow> {
    val pos = arr("CarIdxPosition"); val me = meIdx(); val f2 = arr("CarIdxF2Time")
    val last = arr("CarIdxLastLapTime"); val best = arr("CarIdxBestLapTime"); val pit = arr("CarIdxOnPitRoad")
    return pos.indices.filter { (pos[it]) > 0 }.mapNotNull { i ->
        val d = session?.drivers?.get(i)
        if (d != null && (d.pace || d.spectator)) return@mapNotNull null
        LiveRow(i, pos[i].toInt(), d, f2.at(i)?.takeIf { it > 0 }, last.at(i)?.takeIf { it > 0 }, best.at(i)?.takeIf { it > 0 },
            if (me >= 0) lapDiff(i, me) else 0.0, (pit.at(i) ?: 0.0) != 0.0, i == me, penalty(i))
    }.sortedBy { it.pos }
}

/** The relative: the cars just ahead (gap < 0) and behind (gap > 0) on track, by the time to reach them. */
fun LiveState.relative(each: Int = 3): List<LiveRow> {
    val me = meIdx(); val pct = arr("CarIdxLapDistPct"); val est = arr("CarIdxEstTime"); val pos = arr("CarIdxPosition")
    val last = arr("CarIdxLastLapTime"); val best = arr("CarIdxBestLapTime"); val pit = arr("CarIdxOnPitRoad")
    if (me < 0 || pct.isEmpty()) return emptyList()
    val l = estLap()
    val rows = pct.indices.filter { (pct[it]) >= 0 }.mapNotNull { i ->
        val d = session?.drivers?.get(i)
        if (d != null && (d.pace || d.spectator)) return@mapNotNull null
        var g = (est.at(i) ?: 0.0) - (est.at(me) ?: 0.0)
        if (g > l / 2) g -= l
        if (g < -l / 2) g += l
        LiveRow(i, pos.at(i)?.toInt() ?: 0, d, g, last.at(i)?.takeIf { it > 0 }, best.at(i)?.takeIf { it > 0 }, lapDiff(i, me), (pit.at(i) ?: 0.0) != 0.0, i == me, penalty(i))
    }
    val ahead = rows.filter { !it.me && (it.gap ?: 0.0) < 0 }.sortedByDescending { it.gap }.take(each).reversed()
    val behind = rows.filter { !it.me && (it.gap ?: 0.0) >= 0 }.sortedBy { it.gap }.take(each)
    return ahead + rows.filter { it.me } + behind
}

/** The gaps to the cars just ahead of and behind you in the standings (s, null when none). */
fun LiveState.aheadBehind(): Pair<Double?, Double?> {
    val st = standings(); val m = st.firstOrNull { it.me } ?: return null to null
    val a = st.firstOrNull { it.pos == m.pos - 1 }; val b = st.firstOrNull { it.pos == m.pos + 1 }
    val mg = m.gap
    val g = { x: LiveRow? -> val xg = x?.gap; if (xg != null && mg != null) kotlin.math.abs(mg - xg) else null }
    return g(a) to g(b)
}

/**
 * The laps this phone sees, every 5 m, so that in DRINKS mode whoever is driving is measured against their own best
 * lap (the game's best is the car's, whoever drove it): the same as the PC's overlays and app.
 */
class LiveLaps {
    private class Lap(val n: Int, val drv: String) { val t = ArrayList<Double>(); var pit = false; var time = 0.0 }
    private var cur: Lap? = null
    private val done = ArrayList<Lap>()

    fun add(s: LiveState, driver: String) {
        val lc = s.num("LapCompleted")?.toInt() ?: return
        val d = s.num("LapDist") ?: return
        val t = s.num("LapCurrentLapTime") ?: return
        val c = cur
        if (c == null || c.n != lc) {
            if (c != null && lc == c.n + 1 && c.t.size > 40) { c.time = s.num("LapLastLapTime")?.takeIf { it > 0 } ?: c.t.last(); done.add(c); if (done.size > 40) done.removeAt(0) }
            cur = Lap(lc, driver)
            return
        }
        if ((s.num("OnPitRoad") ?: 0.0) != 0.0) c.pit = true
        if (d < 0 || (d < 60 && t > 8)) return
        val b = (d / 5).toInt()
        while (c.t.size <= b) c.t.add(if (c.t.isEmpty()) t else c.t.last())
        c.t[b] = t
    }

    /** the best lap of this driver ("" the owner), never one through the pits */
    private fun best(driver: String) = done.filter { it.drv == driver && !it.pit && it.time > 0 }.minByOrNull { it.time }

    fun bestTime(driver: String): Double? = best(driver)?.time

    /** the current lap against the driver's own best at the same point of the lap */
    fun delta(s: LiveState, driver: String): Double? {
        val b = best(driver) ?: return null
        val d = s.num("LapDist") ?: return null
        val t = s.num("LapCurrentLapTime") ?: return null
        val i = (d / 5).toInt()
        if (d < 20 || i !in b.t.indices) return null
        return t - b.t[i]
    }
}

/** One lap this phone saw, every 5 m: speed (m/s), the lap's time there (s), throttle and brake (0–1) and gear. */
class RecLap(val n: Int) {
    val sp = ArrayList<Float>(); val t = ArrayList<Float>(); val thr = ArrayList<Float>(); val brk = ArrayList<Float>(); val gear = ArrayList<Int>()
    var time = 0.0; var pit = false
    val size get() = t.size
    fun timeAt(i: Int): Double? = if (i in t.indices) t[i].toDouble() else null
}

/**
 * The laps of the session this phone watches, for Telemetry's Full mode (the traces of the lap) and Compare laps (the
 * lap now against your best, your last lap or another one, live), and your place at the end of every lap (Standings).
 */
class LiveRec {
    val laps = ArrayList<RecLap>()
    var cur: RecLap? = null
        private set
    val posHist = ArrayList<Pair<Int, Int>>() // lap, your place after it
    var ver = 0
        private set
    private var waitLast: RecLap? = null
    private var lastSeen = -1.0

    fun clear() { laps.clear(); cur = null; posHist.clear(); waitLast = null; lastSeen = -1.0; ver++ }

    fun add(s: LiveState) {
        val lc = s.num("LapCompleted")?.toInt() ?: return
        val d = s.num("LapDist") ?: return
        val t = s.num("LapCurrentLapTime") ?: return
        val last = s.num("LapLastLapTime") ?: -1.0
        // the game says the lap's time a moment after the line: it is this lap's once it changes
        waitLast?.let { w -> if (last > 0 && last != lastSeen) { w.time = last; waitLast = null; lastSeen = last; ver++ } }
        val c = cur
        if (c == null || c.n != lc) {
            if (c != null && lc == c.n + 1 && c.size > 40) {
                c.time = c.t.last().toDouble(); waitLast = c; laps.add(c); if (laps.size > 30) laps.removeAt(0)
                s.num("PlayerCarPosition")?.toInt()?.takeIf { it > 0 }?.let { posHist.add(lc to it); if (posHist.size > 200) posHist.removeAt(0) }
            } else if (c != null && lc < c.n) clear() // a new session
            if (lastSeen < 0) lastSeen = last
            cur = RecLap(lc); ver++
            return
        }
        if ((s.num("OnPitRoad") ?: 0.0) != 0.0) c.pit = true
        if (d < 0 || (d < 60 && t > 8)) return
        val b = (d / 5).toInt()
        if (b > 4000) return
        val sp = (s.num("Speed") ?: 0.0).toFloat(); val th = (s.num("Throttle") ?: 0.0).toFloat(); val br = (s.num("Brake") ?: 0.0).toFloat(); val g = s.num("Gear")?.toInt() ?: 0
        while (c.size <= b) {
            val e = c.size == 0
            c.t.add(if (e) t.toFloat() else c.t.last()); c.sp.add(if (e) sp else c.sp.last()); c.thr.add(if (e) th else c.thr.last())
            c.brk.add(if (e) br else c.brk.last()); c.gear.add(if (e) g else c.gear.last())
        }
        c.t[b] = t.toFloat(); c.sp[b] = sp; c.thr[b] = th; c.brk[b] = br; c.gear[b] = g
        ver++
    }

    /** your best lap seen here (never one through the pits) and the last one finished */
    fun best(): RecLap? = laps.filter { !it.pit && it.time > 0 }.minByOrNull { it.time }
    fun last(): RecLap? = laps.lastOrNull { it.time > 0 }
}
