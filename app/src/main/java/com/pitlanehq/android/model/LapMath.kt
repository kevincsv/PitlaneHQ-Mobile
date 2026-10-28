package com.pitlanehq.android.model

// The lap analysis and the coach the phone shows are the web's own, web/dist/pitwall-analysis.js run in a JavaScript engine
// (data/AnalysisJs.kt, JsAnalysis.kt): its corners, tips, plan and sectors. The analysis here is the fallback, used only
// when the engine cannot run (a phone whose WebView has no JavaScriptSandbox), and for the charts' own grid.

import kotlin.math.max
import kotlin.math.roundToInt
import kotlin.math.min

/** Two lap traces on the same distance grid (every [step] metres), ready to draw and compare. */
class Compared(
    val step: Double, val speedA: List<Double>, val speedB: List<Double>?, val thrA: List<Double>, val brkA: List<Double>,
    val delta: List<Double>?, val tA: List<Double>, val tB: List<Double>?,
    val thrB: List<Double>? = null, val brkB: List<Double>? = null,
    val gearA: List<Double>? = null, val gearB: List<Double>? = null,
    // the racing line: how far A was to one side of B at each point (m, NaN where unknown), and B's path, on the same grid
    val lat: List<Double>? = null, val bx: List<Double>? = null, val by: List<Double>? = null
)

/**
 * The racing line, as the PC and the web read it: both laps carry the path their car drove (every 5 m, the game's
 * heading for both, so the same orientation); at the same lap distance A's point along B's normal is how far A was
 * to one side of B; the slow drift of that dead reckoning goes with a ±400 m moving average. Null when either lap has
 * no path or the two paths are not the same track.
 */
/** B's path in A's frame: both from the game's position (B moved to A's origin) or both by dead reckoning; null when one is
 *  each, because they never line up. */
fun sameFrame(a: Trace, b: Trace): Pair<List<Double>, List<Double>>? {
    val bx = b.x ?: return null; val by = b.y ?: return null
    val ga = a.g; val gb = b.g
    if ((ga == null) != (gb == null)) return null
    if (ga == null || gb == null || (ga[0] == gb[0] && ga[1] == gb[1])) return bx to by
    val dx = (gb[1] - ga[1]) * 111320 * kotlin.math.cos(ga[0] * Math.PI / 180); val dy = (gb[0] - ga[0]) * 110540
    return bx.map { it + dx } to by.map { it + dy }
}

fun lineOffsets(ax: List<Double>, ay: List<Double>, bx: List<Double>, by: List<Double>): DoubleArray? {
    val n = minOf(ax.size, ay.size, bx.size, by.size)
    if (n < 60) return null
    val lat = DoubleArray(n); val lon = DoubleArray(n)
    for (i in 0 until n) {
        val i0 = max(0, i - 2); val i1 = min(n - 1, i + 2)
        var tx = bx[i1] - bx[i0]; var ty = by[i1] - by[i0]
        val tm = kotlin.math.hypot(tx, ty).takeIf { it > 0 } ?: 1.0
        tx /= tm; ty /= tm
        val dx = ax[i] - bx[i]; val dy = ay[i] - by[i]
        lat[i] = -ty * dx + tx * dy; lon[i] = tx * dx + ty * dy
    }
    fun smooth(v: DoubleArray): DoubleArray {
        val pre = DoubleArray(n + 1)
        for (i in 0 until n) pre[i + 1] = pre[i] + v[i]
        return DoubleArray(n) { i -> val lo = max(0, i - 80); val hi = min(n - 1, i + 80); v[i] - (pre[hi + 1] - pre[lo]) / (hi - lo + 1) }
    }
    val lc = smooth(lat); val oc = smooth(lon)
    if (oc.map { kotlin.math.abs(it) }.sorted()[n / 2] > 6) return null
    for (i in 0 until n) if (kotlin.math.abs(oc[i]) > 20 || kotlin.math.abs(lc[i]) > 25) lc[i] = Double.NaN
    return lc
}

/** One place on the lap where time goes, with what is different there. */
data class Loss(val fromM: Int, val lost: Double, val brakeDiffM: Int?, val minA: Double, val minB: Double, val throttleDiffM: Int?)

private fun at(tr: Trace, d: Double, k: Int): Double {
    if (tr.rows.isEmpty() || tr.bin <= 0) return 0.0
    val x = d / tr.bin
    val i = x.toInt().coerceIn(0, tr.rows.size - 1)
    val j = min(i + 1, tr.rows.size - 1)
    val f = (x - i).coerceIn(0.0, 1.0)
    val v = tr.rows[i].getOrElse(k) { 0.0 } * (1 - f) + tr.rows[j].getOrElse(k) { 0.0 } * f
    return if (v.isFinite()) v else 0.0
}

fun compare(a: Trace, b: Trace?, step0: Double = 10.0): Compared {
    val len = (a.rows.size - 1) * a.bin
    val lenB = b?.let { (it.rows.size - 1) * it.bin } ?: len
    // at most 400 points per line: enough for a phone screen, light to draw and to touch
    val step = max(step0, min(len, lenB) / 400.0)
    val n = max(2, (min(len, lenB) / step).toInt())
    val d = (0 until n).map { it * step }
    val tA = d.map { at(a, it, 5) }
    val tB = b?.let { tr -> d.map { at(tr, it, 5) } }
    val bxy = if (a.hasShape && b != null && b.hasShape && kotlin.math.abs(a.bin - b.bin) < 1e-6) sameFrame(a, b) else null
    val line = bxy?.let { lineOffsets(a.x!!, a.y!!, it.first, it.second) }
    return Compared(
        step,
        d.map { at(a, it, 0) * 3.6 },
        b?.let { tr -> d.map { at(tr, it, 0) * 3.6 } },
        d.map { at(a, it, 1) },
        d.map { at(a, it, 2) },
        tB?.let { tb -> tA.indices.map { tA[it] - tb[it] } },
        tA, tB,
        b?.let { tr -> d.map { at(tr, it, 1) } },
        b?.let { tr -> d.map { at(tr, it, 2) } },
        d.map { a.rows[(it / a.bin).roundToInt().coerceIn(0, a.rows.size - 1)].getOrElse(3) { 0.0 } },
        b?.let { tr -> d.map { tr.rows[(it / tr.bin).roundToInt().coerceIn(0, tr.rows.size - 1)].getOrElse(3) { 0.0 } } },
        line?.let { l -> d.map { l.getOrElse((it / a.bin).roundToInt()) { Double.NaN } } },
        if (line != null && bxy != null) d.map { bxy.first[(it / b!!.bin).roundToInt().coerceIn(0, bxy.first.size - 1)] } else null,
        if (line != null && bxy != null) d.map { bxy.second[(it / b!!.bin).roundToInt().coerceIn(0, bxy.second.size - 1)] } else null
    )
}

/**
 * One corner in four phases, as driver coaches read data: braking (brake point, how hard), entry
 * (releasing the brake into the turn, trail braking, coasting), apex (minimum speed) and exit (when
 * the throttle comes back). [tip] is an I18n key with [args], about the phase that loses the most.
 * The same analysis as the web's braking coach; [text] is the tip as pitwall-analysis.js wrote it (the line's included),
 * in the app's language, when the corner comes from there.
 */
data class Corner(
    val n: Int, val atM: Int, val lost: Double, val phases: Map<String, Double>, val phase: String?,
    val coastA: Double, val coastB: Double, val tip: String?, val args: List<Any>,
    val lineTip: String? = null, val lineArgs: List<Any> = emptyList(),  // what the line says, besides the tip
    val apexM: Int = atM,       // the reference's slowest point, metres from the line: the same corner on the server (coachtips.js)
    val cls: String = "",       // the corner's speed there: slow (under 80 km/h), medium (under 150), fast
    val text: String? = null    // the tip written by pitwall-analysis.js; null for the fallback's, whose tip is an I18n key
)

/** The corner card the model learnt (`corners` in /community/model): where the fastest drivers of this car and track
 *  brake (b0..b1, metres from the line) and how fast they pass the slowest point (v0..v1, m/s) of one corner of the
 *  record lap, from n drivers' best laps. A hint beside a tip, never a lap to compare with. */
data class CornerCard(val d: Double, val apex: Double, val b0: Double, val b1: Double, val v0: Double, val v1: Double, val n: Int,
                      val spread: Double = 0.0) {  // how far apart the drivers' times are there: how hard the corner is (the plan weighs by it)
    /** the card of a corner whose slowest point is at [apexM] metres (within 60 m), or null */
    companion object { fun of(cards: List<CornerCard>, apexM: Int): CornerCard? = cards.filter { kotlin.math.abs(it.apex - apexM) <= 60 }.minByOrNull { kotlin.math.abs(it.apex - apexM) } }
}

/** How far A was to the inside of B (m, + inside) at B's turn-in, apex and exit; null on a straight or without a line. */
fun cornerLine(c: Compared, brake: Int, apex: Int, exit: Int, span: Int): Triple<Double, Double, Double>? {
    val lat = c.lat ?: return null; val bx = c.bx ?: return null; val by = c.by ?: return null
    val n = minOf(lat.size, bx.size, by.size)
    if (apex <= 0 || apex >= n - 1) return null
    fun tan(i: Int): Pair<Double, Double> { val i0 = max(0, i - 1); val i1 = min(n - 1, i + 1); val tx = bx[i1] - bx[i0]; val ty = by[i1] - by[i0]; val m = kotlin.math.hypot(tx, ty).takeIf { it > 0 } ?: 1.0; return tx / m to ty / m }
    val t1 = tan(max(0, apex - span)); val t2 = tan(min(n - 1, apex + span))
    val cr = t1.first * t2.second - t1.second * t2.first
    if (kotlin.math.abs(cr) < .05) return null
    val sg = if (cr < 0) -1.0 else 1.0
    fun at(i: Int): Double { val v = (max(0, i - 1)..min(n - 1, i + 1)).map { lat[it] }.filter { !it.isNaN() }; return if (v.isEmpty()) Double.NaN else v.average() * sg }
    val r = Triple(at(brake), at(apex), at(min(n - 1, exit)))
    return if (r.first.isNaN() || r.second.isNaN() || r.third.isNaN()) null else r
}

/** The advice of the line in one corner: an I18n key and its argument (metres), or null. */
fun lineTip(l: Triple<Double, Double, Double>?, sameBrake: Boolean): Pair<String, String>? {
    l ?: return null
    val c = ArrayList<Triple<Double, String, String>>()
    fun m(v: Double) = "%.1f".format(kotlin.math.abs(v))
    if (l.first >= 1.5) c.add(Triple(l.first, if (sameBrake) "tip_line_same_brake" else "tip_line_turnin", m(l.first)))
    if (l.second <= -1.5) c.add(Triple(-l.second, "tip_line_apex", m(l.second)))
    if (l.third >= 1.5) c.add(Triple(l.third, "tip_line_exit", m(l.third)))
    return c.maxByOrNull { it.first }?.let { it.second to it.third }
}

val PHASE_KEYS = listOf("brake", "entry", "apex", "exit")

/** The official number of the turn nearest to a point of the lap (turns: fractions of the lap, T1 … Tn in order). */
fun turnNo(turns: List<Double>, at: Double, lapLen: Double, fallback: Int): Int {
    if (turns.isEmpty() || lapLen <= 0) return fallback
    val f = ((at / lapLen) % 1.0 + 1.0) % 1.0
    var bi = 0
    var bd = 2.0
    turns.forEachIndexed { i, x -> val d = kotlin.math.abs(x - f).let { minOf(it, 1 - it) }; if (d < bd) { bd = d; bi = i } }
    return bi + 1
}

fun corners(c: Compared, turns: List<Double> = emptyList(), off: Set<String> = emptySet()): List<Corner> {
    val tB = c.tB ?: return emptyList()
    val sB = c.speedB ?: return emptyList()
    val bB = c.brkB ?: return emptyList()
    val hB = c.thrB ?: return emptyList()
    val n = minOf(c.tA.size, tB.size, sB.size, bB.size, hB.size)
    if (n < 10) return emptyList()
    fun bins(m: Double) = max(1, (m / c.step).toInt())
    fun seg(x: Int, y: Int) = if (x < y) (c.tA[y] - c.tA[x]) - (tB[y] - tB[x]) else 0.0
    // braking zones on the reference: from the brake to the slowest point before the throttle is back
    val zones = ArrayList<Pair<Int, Int>>()
    var i = 1
    while (i < n) {
        if (bB[i] > .12 && bB[i - 1] <= .12) {
            var k = i
            var imin = i
            while (k < n && k < i + bins(600.0) && !(hB[k] > .6 && bB[k] < .05)) {
                if (sB[k] < sB[imin]) imin = k
                k++
            }
            if (sB[i] - sB[imin] > 15) zones.add(i to imin)
            i = max(k, i + 1)
        } else i++
    }
    // the corners by the track's turns (the official ones, or the ones the layout's geometry gives): two brake applications in
    // one corner are one corner, and a turn taken without braking (a lift) is a corner of its own, like the web's cornerZones
    class Z(var zi: Int, var zmin: Int, val turn: Int, val lift: Boolean)
    val zs: List<Z> = if (turns.isEmpty()) zones.map { Z(it.first, it.second, -1, false) } else {
        val ap = turns.map { (it * n).toInt() }.filter { it in 1 until n - 1 }
        fun near(i: Int): Int { var b = -1; var bd = Int.MAX_VALUE; ap.forEachIndexed { k, a -> val d = kotlin.math.abs(a - i); if (d < bd) { bd = d; b = k } }; return if (bd <= bins(150.0)) b else -1 }
        val by = LinkedHashMap<String, Z>()
        for ((zi, zmin) in zones) {
            val k = near(zmin)
            if (k < 0) { by["z$zi"] = Z(zi, zmin, -1, false); continue }
            val o = by["t$k"]
            if (o == null) by["t$k"] = Z(zi, zmin, k, false) else { if (sB[zmin] < sB[o.zmin]) o.zmin = zmin; o.zi = min(o.zi, zi) }
        }
        ap.forEachIndexed { k, a ->
            if (by.containsKey("t$k")) return@forEachIndexed
            var i0 = max(0, a - bins(100.0))
            for (i in a downTo max(1, a - bins(200.0))) if (hB[i] > .9) { i0 = i; break }
            var imin = a
            for (i in i0 until min(n, a + bins(50.0))) if (sB[i] < sB[imin]) imin = i
            if (sB[i0] - sB[imin] > 7) by["t$k"] = Z(i0, imin, k, true)  // it really slows (7 km/h, like the web's 2 m/s)
        }
        by.values.sortedBy { it.zi }
    }
    return zs.mapIndexed { idx, z ->
        val zi = z.zi; val zmin = z.zmin
        val i0 = max(0, zi - bins(50.0))
        val i1 = min(n - 1, zmin + bins(150.0))
        val lost = seg(i0, i1)
        val vb = sB[zmin]  // km/h at the reference's slowest point
        val cls = if (vb < 80) "slow" else if (vb < 150) "medium" else "fast"
        // the same corner on this lap: its brake point within 100 m
        val w = bins(100.0)
        val ja = (max(1, zi - w)..min(n - 1, zi + w)).filter { c.brkA[it] > .12 && c.brkA[it - 1] <= .12 }.minByOrNull { kotlin.math.abs(it - zi) }
        val aMin = ja?.let { j -> (j..i1).minByOrNull { c.speedA[it] } }
        var ipb = zi
        for (k in zi..zmin) if (bB[k] > bB[ipb]) ipb = k
        val rel = (ipb..zmin).firstOrNull { bB[it] < .05 } ?: zmin
        val a0 = max(rel, zmin - bins(20.0))
        val a1 = min(i1, zmin + bins(20.0))
        val ph = mapOf("brake" to seg(i0, rel), "entry" to seg(rel, a0), "apex" to seg(a0, a1), "exit" to seg(a1, i1))
        fun coast(sp: List<Double>, br: List<Double>) = (i0..i1).count { sp[it] < .05 && br[it] < .05 } * c.step
        val coastA = coast(c.thrA, c.brkA)
        val coastB = coast(hB, bB)
        var tip: String? = null
        var args: List<Any> = emptyList()
        var phase: String? = null
        if (lost > .03) {
            phase = ph.maxBy { it.value }.key
            if (z.lift && phase == "brake") phase = "entry"  // a corner taken without braking has no braking phase to speak of
            val dd = ja?.let { ((it - zi) * c.step).toInt() }
            var ipa = ja ?: 0
            if (ja != null && aMin != null) for (k in ja..aMin) if (c.brkA[k] > c.brkA[ipa]) ipa = k
            val pa = if (ja != null) c.brkA[ipa] else 0.0
            val relA = if (ja != null && aMin != null) (ipa..aMin).firstOrNull { c.brkA[it] < .05 } ?: aMin else null
            val trailA = relA?.let { ((it - ipa) * c.step).toInt() }
            val trailB = ((rel - ipb) * c.step).toInt()
            val dmin = aMin?.let { c.speedA[it] - sB[zmin] }
            val puA = aMin?.let { m -> (m..i1).firstOrNull { c.thrA[it] > .5 } }
            val puB = (zmin..i1).firstOrNull { hB[it] > .5 }
            val late = if (puA != null && puB != null) ((puA - puB) * c.step).toInt() else null
            // the gear through the corner and the lifts after the apex: what a generic tip gives way to
            val gA = aMin?.let { c.gearA?.getOrNull(it)?.toInt() } ?: 0
            val gB = c.gearB?.getOrNull(zmin)?.toInt() ?: 0
            fun lifts(th: List<Double>, from: Int, to: Int): Int { var n = 0; var prev = -1.0; for (k in from..min(to, th.size - 1)) { val t = th[k]; if (prev >= 0 && prev > .8 && t < .5) n++; prev = t }; return n }
            val lA = aMin?.let { lifts(c.thrA, it, i1) } ?: 0
            val lB = lifts(hB, zmin, i1)
            // how the throttle is opened after the apex: metres from picking it up (5 %) to full (95 %)
            fun ramp(th: List<Double>, from: Int, to: Int): Int? { var a = -1; for (k in from..min(to, th.size - 1)) { if (a < 0 && th[k] > .05) a = k; if (a >= 0 && th[k] > .95) return ((k - a) * c.step).toInt() }; return null }
            val rampA = aMin?.let { ramp(c.thrA, it, i1) }
            val rampB = ramp(hB, zmin, i1)
            // braking later than the reference and arriving slower at the apex is one mistake, whatever phase pays for it
            if (dd != null && dd > 6 && dmin != null && dmin < -2) { tip = "tip_brake_late_apex"; args = listOf(dd, (-dmin).toInt()) }
            else when (phase) {
                "brake" -> when {
                    dd != null && dd < -6 -> { tip = "tip_brake_later"; args = listOf(-dd) }
                    ja != null && pa < bB[ipb] - .05 -> { tip = "tip_brake_harder"; args = listOf((pa * 100).toInt(), (bB[ipb] * 100).toInt()) }
                    dd != null && dd > 6 -> { tip = "tip_brake_earlier"; args = listOf(dd) }
                    trailA != null && trailB - trailA >= 15 -> { tip = "tip_trail"; args = listOf(trailA, trailB) }
                    dd != null -> tip = "tip_brake_same"
                    else -> tip = "tip_brake_generic"
                }
                "entry" -> when {
                    trailA != null && trailB - trailA >= 15 -> { tip = "tip_trail"; args = listOf(trailA, trailB) }
                    coastA - coastB >= 10 -> { tip = "tip_coast"; args = listOf(coastA.toInt(), coastB.toInt()) }
                    dmin != null && dmin >= 0 -> tip = "tip_entry_before"
                    else -> tip = "tip_entry_speed"
                }
                "apex" -> if (dmin != null && dmin < -2) { tip = "tip_apex_speed"; args = listOf((-dmin).toInt()) } else if (dmin != null && dmin >= 0) tip = "tip_apex_longer" else tip = "tip_apex_line"
                else -> when {
                    late != null && late >= 8 -> { tip = "tip_throttle"; args = listOf(late) }
                    rampA != null && rampB != null && rampB - rampA >= 15 && lA > lB -> { tip = "tip_throttle_rough"; args = listOf(rampA, rampB) }
                    rampA != null && rampB != null && rampA - rampB >= 15 -> { tip = "tip_throttle_slow"; args = listOf(rampA, rampB) }
                    coastA - coastB >= 10 -> tip = "tip_no_wait"
                    late != null && late <= -8 && dmin != null && dmin < -1 -> { tip = "tip_exit_speed"; args = listOf(-late, (-dmin).toInt()) }
                    else -> tip = "tip_full_throttle"
                }
            }
            if (tip in GENERIC_TIPS) {
                when {
                    gA >= 1 && gB >= 1 && gB > gA -> { tip = "tip_gear_up"; args = listOf(gB, gA) }
                    gA >= 1 && gB >= 1 && gB < gA -> { tip = "tip_gear_down"; args = listOf(gB, gA) }
                    phase == "exit" && lA >= 2 && lA > lB + 1 -> { tip = "tip_lifts"; args = listOf(lA, lB) }
                }
            }
            // a tip an admin turned off for corners of this speed gives way to the phase's plain tip (like the web)
            if (tip != null && (tip!!.removePrefix("tip_") + "|" + cls) in off) {
                tip = when (phase) { "entry" -> "tip_entry_speed"; "apex" -> "tip_apex_line"; "exit" -> "tip_full_throttle"; else -> "tip_brake_generic" }
                args = emptyList()
            }
        }
        // the line: where the car was across the track; braking at the reference's point but on the wrong part of the
        // track is said first, a generic tip gives way to it, otherwise it goes under the tip
        var lineKey: String? = null
        var lineArgs: List<Any> = emptyList()
        if (lost > .03) {
            val dd = ja?.let { ((it - zi) * c.step).toInt() }
            val lt = lineTip(cornerLine(c, zi, zmin, zmin + bins(80.0), bins(40.0)), dd != null && kotlin.math.abs(dd) <= 6)
            if (lt != null) {
                if (tip in GENERIC_TIPS || (phase == "brake" && dd != null && kotlin.math.abs(dd) <= 6)) { tip = lt.first; args = listOf(lt.second) }
                else { lineKey = lt.first; lineArgs = listOf(lt.second) }
            }
        }
        Corner(if (z.turn >= 0) z.turn + 1 else turnNo(turns, zmin * c.step, n * c.step, idx + 1), (zi * c.step).toInt(), lost, ph, phase, coastA, coastB, tip, args, lineKey, lineArgs,
            apexM = (zmin * c.step).toInt(), cls = cls)
    }
}

/** The tips that say nothing the data showed: what the data shows plainly (the gear, lifts, the line) replaces them. */
private val GENERIC_TIPS = setOf("tip_brake_generic", "tip_entry_speed", "tip_apex_line", "tip_full_throttle", "tip_brake_same", "tip_entry_before", "tip_apex_longer")

/** Where a lap starts braking (brake over 12 % after being below), in metres, from a series on the [step] grid. */
fun brakePoints(brk: List<Double>?, step: Double): List<Double> {
    if (brk == null || brk.size < 3) return emptyList()
    val out = ArrayList<Double>()
    var i = 1
    while (i < brk.size) {
        if (brk[i] > .12 && brk[i - 1] <= .12) {
            out.add(i * step)
            var k = i
            while (k < brk.size && k < i + 60 && brk[k] > .05) k++
            i = k + 1
        } else i++
    }
    return out
}

fun losses(c: Compared, segM: Double = 250.0): List<Loss> {
    val tB = c.tB ?: return emptyList()
    val per = max(1, (segM / c.step).toInt())
    val out = ArrayList<Loss>()
    var s = 0
    while (s < c.tA.size - 1) {
        val e = min(c.tA.size - 1, s + per)
        val lost = (c.tA[e] - c.tA[s]) - (tB[e] - tB[s])
        val speedB = c.speedB!!
        fun firstBrake(brk: List<Double>?): Int? = brk?.let { (s..e).firstOrNull { i -> it[i] > 0.3 } }
        val minA = (s..e).minOf { c.speedA[it] }
        val minB = (s..e).minOf { speedB[it] }
        // braking: the reference has no brake channel here, so use where its speed starts to drop
        val bA = firstBrake(c.brkA)
        val bB = (s until e).firstOrNull { i -> i + 2 <= e && speedB[i + 2] < speedB[i] - 3 }
        val brakeDiff = if (bA != null && bB != null) ((bA - bB) * c.step).toInt() else null
        val fullA = (s..e).firstOrNull { c.thrA[it] > 0.95 && c.speedA[it] > minA + 2 }
        val fullB = (s..e).firstOrNull { speedB[it] > minB + 2 && it > (s..e).minBy { k -> speedB[k] } }
        val thrDiff = if (fullA != null && fullB != null) ((fullA - fullB) * c.step).toInt() else null
        out.add(Loss((s * c.step).toInt(), lost, brakeDiff, minA, minB, thrDiff))
        s = e
    }
    return out.filter { it.lost > 0.02 }.sortedByDescending { it.lost }.take(3)
}
