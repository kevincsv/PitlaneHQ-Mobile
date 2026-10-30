package com.pitlanehq.android.data

import org.json.JSONArray
import org.json.JSONObject
import java.text.Normalizer

/** One week of a series: its track and layout, the length (laps or minutes), when its races start and the rain chance.
 *  The start times follow iRacing's race_time_descriptors: every [every] minutes from [first] ("HH:MM" UTC) on [days]
 *  (offsets from [base], all days when empty), or the set [times]. */
data class SWeek(
    val k: Int, val start: Long, val end: Long, val trackId: Long, val track: String, val cfg: String, val cat: String,
    val laps: Int, val mins: Int, val rain: Int, val carIds: List<Long>,
    var rep: Boolean, var first: String, var every: Int, var days: List<Int>, var base: Long, var times: List<Long>
)

/** One series of the season, as the web's planner keeps it (normSeries). [sid] is the series id the stars and the plan use. */
data class SSeries(
    val id: Long, val sid: Long, val name: String, val lic: Int, val fixed: Boolean, val multi: Boolean, val desc: String,
    val inc: Int, val drops: Int, val carIds: List<Long>, val weeks: List<SWeek>
)

/** The season from the server (GET /community/season) and what the account has raced (GET /api/sessions-owned). */
class SeasonData(val series: List<SSeries>, val tracks: Map<Long, Pair<String, String>>, val cars: Map<Long, String>,
                 val racedTracks: Set<Long>, val racedCars: Set<Long>)

/** One race in the plan: the series and its start (epoch ms). */
data class PlannedRace(val sid: Long, val t: Long, val name: String, val track: String)

/** The web planner's maths, the same answers on every device: the race starts of a week, this week, the next race, and
 *  which tracks and cars the account owns, known only from what it raced (no iRacing account): a track counts with all
 *  its layouts, and the sim's names are matched to the season's by the words they share. */
object Season {
    const val DAY = 86_400_000L
    private const val MIN = 60_000L

    private fun day(s: String): Long = runCatching { java.time.LocalDate.parse(s.take(10)).toEpochDay() * DAY }.getOrDefault(0L)
    private fun time(s: String): Long = runCatching { java.time.Instant.parse(s).toEpochMilli() }.getOrDefault(0L)
    private fun ids(a: JSONArray?) = (0 until (a?.length() ?: 0)).map { a!!.optLong(it) }

    fun parse(text: String, owned: String?): SeasonData {
        val root = JSONObject(text)
        val j = root.optJSONObject("season") ?: JSONObject()
        val tracks = HashMap<Long, Pair<String, String>>()
        j.optJSONArray("tracks")?.let { a -> for (i in 0 until a.length()) a.optJSONObject(i)?.let { tracks[it.optLong("track_id")] = it.optString("track_name") to it.optString("config_name").let { c -> if (c == "null") "" else c } } }
        val cars = HashMap<Long, String>()
        j.optJSONArray("cars")?.let { a -> for (i in 0 until a.length()) a.optJSONObject(i)?.let { cars[it.optLong("car_id")] = it.optString("car_name") } }
        val classes = HashMap<Long, List<Long>>()
        j.optJSONArray("classes")?.let { a -> for (i in 0 until a.length()) a.optJSONObject(i)?.let { c ->
            val inC = c.optJSONArray("cars_in_class"); classes[c.optLong("car_class_id")] = (0 until (inC?.length() ?: 0)).map { inC!!.optJSONObject(it)?.optLong("car_id") ?: 0L } } }
        val out = ArrayList<SSeries>()
        val sa = j.optJSONArray("seasons") ?: JSONArray()
        for (i in 0 until sa.length()) {
            val s = sa.optJSONObject(i) ?: continue
            if (s.has("active") && !s.optBoolean("active", true) || s.optBoolean("complete")) continue
            val sch = s.optJSONArray("schedules") ?: JSONArray()
            val weeks = (0 until sch.length()).mapNotNull { k ->
                val w = sch.optJSONObject(k) ?: return@mapNotNull null
                val r = w.optJSONArray("race_time_descriptors")?.optJSONObject(0) ?: JSONObject()
                val wx = w.optJSONObject("weather")?.optJSONObject("weather_summary")
                val tr = w.optJSONObject("track") ?: JSONObject()
                val st = day(w.optString("start_date"))
                val en = w.optString("week_end_time").takeIf { it.isNotBlank() && it != "null" }?.let { time(it) }?.takeIf { it > 0 } ?: (st + 7 * DAY)
                val tid = tr.optLong("track_id")
                SWeek(
                    k = w.optInt("race_week_num", k), start = st, end = en, trackId = tid,
                    track = tracks[tid]?.first ?: tr.optString("track_name"), cfg = tracks[tid]?.second ?: tr.optString("config_name").let { if (it == "null") "" else it },
                    cat = w.optString("category"), laps = w.optInt("race_lap_limit"), mins = w.optInt("race_time_limit"),
                    rain = wx?.optInt("precip_chance") ?: 0,
                    carIds = (0 until (w.optJSONArray("race_week_cars")?.length() ?: 0)).map { w.optJSONArray("race_week_cars")!!.optJSONObject(it)?.optLong("car_id") ?: 0L },
                    rep = r.optBoolean("repeating"), first = r.optString("first_session_time").let { if (it == "null") "" else it },
                    every = r.optInt("repeat_minutes"), days = ids(r.optJSONArray("day_offset")).map { it.toInt() },
                    base = r.optString("start_date").takeIf { it.isNotBlank() && it != "null" }?.let { day(it) } ?: st,
                    times = r.optJSONArray("session_times").let { ts -> (0 until (ts?.length() ?: 0)).map { time(ts!!.optString(it)) }.filter { it > 0 } }
                )
            }
            if (weeks.isEmpty()) continue
            val name = sch.optJSONObject(0)?.optString("series_name")?.takeIf { it.isNotBlank() } ?: s.optString("season_name")
            out += SSeries(
                id = s.optLong("season_id"), sid = s.optLong("series_id"), name = name, lic = s.optInt("license_group", 1),
                fixed = s.optBoolean("fixed_setup"), multi = s.optBoolean("multiclass"), desc = s.optString("schedule_description").let { if (it == "null") "" else it },
                inc = s.optInt("incident_limit"), drops = s.optInt("drops"),
                carIds = ids(s.optJSONArray("car_class_ids")).flatMap { classes[it] ?: emptyList() }.distinct(), weeks = weeks
            )
        }
        val d = SeasonData(out, tracks, cars, HashSet(), HashSet())
        root.optJSONObject("seen")?.let { applySeen(d, it) }
        owned?.let { raced(d, JSONObject(it)) }
        return d
    }

    // ---------- the race starts (the web's sessions) ----------
    fun starts(w: SWeek, from0: Long, to0: Long): List<Long> {
        val from = maxOf(from0, w.start); val to = minOf(to0, w.end); val out = ArrayList<Long>()
        if (to <= from) return out
        if (w.rep && w.every > 0) {
            val p = (w.first.ifBlank { "00:00" }).split(":"); val first = ((p.getOrNull(0)?.toIntOrNull() ?: 0) * 60 + (p.getOrNull(1)?.toIntOrNull() ?: 0)) * MIN
            val days = w.days.ifEmpty { (0..6).toList() }
            for (k in 0 until 8) {
                val dayStart = w.base + k * 7 * DAY; if (dayStart > to) break
                for (dd in days) {
                    val ds = dayStart + dd * DAY; if (ds + DAY < from || ds > to) continue
                    var t = ds + first
                    while (t < ds + DAY) { if (t >= from && t < to) out += t; t += w.every * MIN }
                }
            }
        } else w.times.forEach { if (it in from until to) out += it }
        return out.sorted()
    }
    fun curWeek(s: SSeries, now: Long): SWeek? = s.weeks.firstOrNull { now >= it.start && now < it.end }
    fun weekAt(s: SSeries, t: Long): SWeek = s.weeks.firstOrNull { t >= it.start && t < it.end } ?: s.weeks[0]
    fun nextRace(s: SSeries, now: Long): Pair<Long, SWeek>? {
        for (w in s.weeks) { if (w.end < now) continue; starts(w, now, now + 14 * DAY).firstOrNull()?.let { return it to w } }
        return null
    }
    /** The discipline of the series: this week's, else its first week's. */
    fun cat(s: SSeries, now: Long): String = (curWeek(s, now) ?: s.weeks[0]).cat.ifBlank { "sports_car" }
    /** The cars of a week (its own list, else the series' classes). */
    fun carsOf(d: SeasonData, s: SSeries, w: SWeek?): List<Long> = (w?.carIds?.takeIf { it.isNotEmpty() } ?: s.carIds).distinct()
    fun ownTrack(d: SeasonData, w: SWeek): Boolean = w.trackId in d.racedTracks
    fun ownCar(d: SeasonData, s: SSeries, w: SWeek?): Boolean = carsOf(d, s, w).any { it in d.racedCars }

    // ---------- names: "Tsukuba Circuit 2k Full" is "Tsukuba Circuit · 2000 Full" (the web's ownToks/ownBest) ----------
    fun toks(x: String): List<String> = Normalizer.normalize(x, Normalizer.Form.NFD).replace(Regex("\\p{M}+"), "").lowercase()
        .replace(Regex("\\b(\\d+)k\\b")) { (it.groupValues[1].toInt() * 1000).toString() }
        .split(Regex("[^a-z0-9]+")).filter { it.isNotEmpty() && (it.length > 1 || it.any(Char::isDigit)) }
    private fun score(a: List<String>, b: List<String>): Double {
        if (a.isEmpty() || b.isEmpty()) return 0.0
        fun eq(x: String, y: String) = x == y || (minOf(x.length, y.length) >= 3 && (x.contains(y) || y.contains(x)))
        return 2.0 * a.count { x -> b.any { y -> eq(x, y) } } / (a.size + b.size)
    }
    private fun best(forms: List<List<String>>, cands: List<Pair<Long, List<List<String>>>>): List<Long> {
        var bestS = 0.0; var out = ArrayList<Long>()
        for ((id, cf) in cands) {
            val sc = forms.maxOf { f -> cf.maxOf { g -> score(f, g) } }
            if (sc > bestS + 1e-9) { bestS = sc; out = arrayListOf(id) } else if (Math.abs(sc - bestS) < 1e-9) out += id
        }
        return if (bestS >= 0.6) out else emptyList()
    }
    private fun trackCands(d: SeasonData) = d.tracks.map { (id, x) -> id to listOf(toks(x.first), toks(x.first + " " + x.second)) }
    private fun carCands(d: SeasonData) = d.cars.map { (id, x) -> id to listOf(toks(x)) }

    private fun raced(d: SeasonData, r: JSONObject) {
        val tc = trackCands(d); val cc = carCands(d)
        val t = d.racedTracks as HashSet; val c = d.racedCars as HashSet
        r.optJSONArray("tracks")?.let { a -> for (i in 0 until a.length()) { val x = a.optJSONArray(i) ?: continue
            val n = x.optString(0); val cfg = x.optString(1)
            best(listOf(toks(n), toks("$n $cfg")), tc).forEach { id -> val nm = d.tracks[id]?.first; d.tracks.forEach { (j, y) -> if (y.first == nm) t += j } } } }
        r.optJSONArray("cars")?.let { a -> for (i in 0 until a.length()) best(listOf(toks(a.optString(i))), cc).forEach { c += it } }
    }

    // ---------- when official races really started, as the PCs saw it (the web's applySeen/seenFix) ----------
    private fun key(w: SWeek) = listOf(w.rep, w.first, w.every, w.days).toString()
    private fun applySeen(d: SeasonData, seen: JSONObject) {
        val ids = d.series.map { it.id.toString() }.toSet()
        for (s in d.series) {
            val arr = seen.optJSONArray(s.id.toString()) ?: seenByName(d, s, seen, ids)
            val obs = (0 until (arr?.length() ?: 0)).mapNotNull { arr!!.optJSONArray(it)?.optLong(0) }
            if (obs.isEmpty()) continue
            for (w in s.weeks) {
                val o = obs.filter { it >= w.start && it < w.end }; if (o.isEmpty()) continue
                val p = starts(w, w.start, w.end)
                if (p.isNotEmpty() && o.all { t -> p.any { Math.abs(it - t) <= 3 * MIN } }) continue
                val k = key(w); val fix = seenFix(w, o) ?: continue
                s.weeks.forEach { x -> if (x === w || (x.start > w.start && key(x) == k && obs.none { it >= x.start && it < x.end })) fix(x) }
            }
        }
    }
    private fun seenByName(d: SeasonData, s: SSeries, seen: JSONObject, ids: Set<String>): JSONArray? {
        val tc = trackCands(d); val cc = carCands(d)
        fun fits(e: JSONArray): Boolean {
            val t0 = e.optLong(0); val w = s.weeks.firstOrNull { t0 >= it.start && t0 < it.end } ?: return false
            val tn = e.optString(2); val car = e.optString(4); if (tn.isBlank() || car.isBlank()) return false
            val cfg = e.optString(3).let { if (":" in it) "" else it }
            if (w.trackId !in best(listOf(toks(tn), toks("$tn $cfg")), tc)) return false
            val cs = best(listOf(toks(car)), cc).toSet()
            return carsOf(d, s, w).any { it in cs }
        }
        val hit = seen.keys().asSequence().filter { it !in ids }.mapNotNull { k -> seen.optJSONArray(k)?.takeIf { a -> a.length() > 0 && (0 until a.length()).all { a.optJSONArray(it)?.let(::fits) == true } } }.toList()
        return hit.singleOrNull()
    }
    private fun seenFix(w: SWeek, o: List<Long>): ((SWeek) -> Unit)? {
        fun mod(a: Long, b: Long) = ((a % b) + b) % b
        val mins = o.map { Math.round(mod(it, DAY).toDouble() / MIN) }.distinct()
        fun hm(m: Long) = "%02d:%02d".format(m / 60, m % 60)
        if (w.rep && w.every > 0) {
            val p = w.first.ifBlank { "00:00" }.split(":"); val f = (p.getOrNull(0)?.toLongOrNull() ?: 0) * 60 + (p.getOrNull(1)?.toLongOrNull() ?: 0)
            val m = w.every.toLong(); val sh = mins.map { mod(it - f, m) }
            var bestB: Long? = null; var n = 0
            sh.forEach { b -> val c = sh.count { x -> minOf(mod(x - b, m), mod(b - x, m)) <= 3 }; if (c > n) { n = c; bestB = b } }
            if (bestB != null && n * 2 > sh.size) { var nf = f + bestB!!; if (nf >= 1440) nf -= m; val v = hm(maxOf(0, nf)); return { it.first = v } }
        } else if (w.times.isNotEmpty()) return null
        if (mins.size < 3) return null
        val st = o.map { Math.round(it.toDouble() / (5 * MIN)) * 5 }.distinct().sorted()
        fun gcd(a: Long, b: Long): Long = if (b == 0L) a else gcd(b, a % b)
        var g = 0L; for (i in 1 until st.size) g = gcd(g, st[i] - st[0])
        if (g < 15 || g > 1440) return null
        val first = hm(mod(mins.min(), g))
        return { it.rep = true; it.every = g.toInt(); it.first = first; it.days = emptyList(); it.times = emptyList() }
    }
}
