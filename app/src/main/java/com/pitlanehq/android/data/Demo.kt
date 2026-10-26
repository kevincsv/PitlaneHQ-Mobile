package com.pitlanehq.android.data

import com.pitlanehq.android.model.*
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.random.Random

/**
 * Invented data to test the app (Settings → Demo data). It only lives on this phone: nothing is
 * uploaded, and every screen shows a DEMO banner while it is on.
 */
object Demo {
    private data class Combo0(val track: String, val cfg: String, val trackId: Long, val car: String, val carId: Long, val len: Double, val lap: Double)

    private val combos = listOf(
        Combo0("Spa-Francorchamps", "Grand Prix Pits", 163, "Porsche 911 GT3 R (992)", 169, 7004.0, 137.8),
        Combo0("Watkins Glen International", "Boot", 434, "Mazda MX-5 Cup", 67, 5435.0, 126.4),
        Combo0("Okayama International Circuit", "Full Course", 166, "Toyota GR86", 160, 3703.0, 92.1),
        Combo0("Road Atlanta", "Full Course", 127, "BMW M4 GT3", 132, 4088.0, 85.6),
        Combo0("Laguna Seca", "Full Course", 47, "Mazda MX-5 Cup", 67, 3602.0, 95.3),
    )
    private val names = listOf("Demo Driver A", "Demo Driver B", "Demo Driver C", "Demo Driver D", "Demo Driver E", "Demo Driver F", "Demo Driver G", "Demo Driver H", "Demo Driver I", "Demo Driver J")
    private const val DAY = 86_400_000L
    private val now = System.currentTimeMillis()

    // one lap trace: a speed profile with braking zones, so the charts and the time-loss list have something to show
    private fun trace(c: Combo0, lapTime: Double, seed: Int): Trace {
        val r = Random(seed)
        val bin = 10.0
        val n = (c.len / bin).toInt()
        // the corners of a track are always in the same place: every lap of a combination shares them
        val rc = Random(c.track.hashCode())
        val corners = (0 until 9).map { (it + 0.5 + rc.nextDouble(-0.2, 0.2)) / 9.0 }
        val raw = DoubleArray(n) { i ->
            val x = i.toDouble() / n
            var v = 72.0
            for (k in corners) {
                val d = x - k
                v -= 38 * kotlin.math.exp(-(d * d) / 0.0009)
            }
            max(18.0, v + sin(x * 2 * PI * 3) * 3 + r.nextDouble(-0.6, 0.6))
        }
        // scale the speeds so the trace adds up to the lap time
        val sumT = raw.sumOf { bin / it }
        val f = sumT / lapTime
        var t = 0.0
        val rows = (0 until n).map { i ->
            val v = raw[i] * f
            t += bin / v
            val next = raw[min(n - 1, i + 3)] * f
            val braking = next < v - 1.5
            val thr = if (braking) 0.0 else min(1.0, 0.55 + (v / 80.0))
            val brk = if (braking) min(1.0, (v - next) / 8.0) else 0.0
            doubleArrayOf(v, thr, brk, (1 + v / 14).toInt().coerceAtMost(6).toDouble(), cos(i * 0.05) * 0.1, t)
        }
        // the shape of the track, like the position Pitlane HQ records: a loop that turns at every corner
        val turns = corners.indices.map { k -> (if (k % 3 == 2) -0.6 else 1.0) * rc.nextDouble(0.6, 1.3) }
        val tot = turns.sum()
        val xs = ArrayList<Double>(n); val ys = ArrayList<Double>(n)
        var h = 0.0; var px = 0.0; var py = 0.0
        for (i in 0 until n) {
            val q = i.toDouble() / n
            var dh = 0.0
            corners.forEachIndexed { j, k -> val dd = q - k; dh += turns[j] * 2 * PI / tot * kotlin.math.exp(-(dd * dd) / 0.0006) / (kotlin.math.sqrt(PI * 0.0006) * n) }
            h += dh; px += bin * cos(h); py += bin * sin(h); xs.add(px); ys.add(py)
        }
        val ex = xs[n - 1] - xs[0]; val ey = ys[n - 1] - ys[0]
        for (i in 0 until n) { val f = i.toDouble() / (n - 1); xs[i] = xs[i] - ex * f; ys[i] = ys[i] - ey * f }
        return Trace(bin, rows, xs, ys)
    }

    private fun sectors(lap: Double, r: Random): List<Double> {
        val a = listOf(0.31, 0.37, 0.32).map { it * lap + r.nextDouble(-0.15, 0.15) }
        val s = a.sum()
        return a.map { it * lap / s }
    }

    fun sessions(): List<CloudSession> = combos.flatMapIndexed { i, c ->
        listOf(
            CloudSession("demo:$i:p", now - (i * 2 + 1) * DAY, c.track, c.cfg, c.car, "Practice", 9, c.lap + 0.4 + i * 0.05),
            CloudSession("demo:$i:r", now - (i * 2) * DAY - 3_600_000, c.track, c.cfg, c.car, "Race", 14, c.lap + 0.2)
        )
    }.sortedByDescending { it.started }

    private fun comboOf(sessionId: String) = combos[sessionId.split(":")[1].toInt()]

    fun laps(sessionId: String): List<CloudLap> {
        val c = comboOf(sessionId)
        val r = Random(sessionId.hashCode())
        val s = sessions().first { it.id == sessionId }
        return (1..s.laps).map { n ->
            val time = if (n == 3) s.best!! else s.best!! + r.nextDouble(0.1, 1.6) + if (n == 1) 4.0 else 0.0
            CloudLap("$sessionId:$n", n, time, n != 6, sectors(time, r))
        }
    }

    fun trace(lapId: String): Trace {
        if (lapId.startsWith("comm:")) {
            val p = lapId.split(":")
            val c = combos[p[1].toInt()]
            return trace(c, board(c.trackId, c.carId).first { it.id == lapId }.time, lapId.hashCode())
        }
        val c = comboOf(lapId)
        val lap = laps(lapId.substringBeforeLast(":")).first { it.id == lapId }
        return trace(c, lap.time, lapId.hashCode())
    }

    fun bests(): List<PersonalBest> = combos.mapIndexed { i, c ->
        PersonalBest(c.track, c.cfg, c.car, c.lap + 0.2, 23, now - i * 2 * DAY, "demo:$i:r:3", "demo:$i:r")
    }

    fun combos(): List<Combo> = combos.map { c -> Combo(c.trackId, c.track, c.carId, c.car, 40 + c.carId.toInt() % 30, c.lap - 0.7, "sports_car") }

    private val demoLics = listOf("A", "B", "C", "B", "D", "R", "A", "C", "B", "P")

    fun profile(lapId: String?): DriverProfile {
        val k = lapId?.substringAfterLast(":")?.toIntOrNull() ?: 0
        return DriverProfile(if (lapId == null) "Demo Driver" else names[k % names.size], now - 200 * DAY, lapId == null, false, false, k % 3 == 0, false, mapOf("sports_car" to demoLics[k % demoLics.size], "oval" to "D"),
            races().take(6).map { r -> ProfileRace(r.whenMs, r.track, r.car, "sports_car", demoLics[k % demoLics.size], r.official, r.start, r.finish, r.field, r.inc, r.best, r.irChange, r.dnf) },
            combos.map { c -> ProfileLap(c.track, c.car, c.lap - 0.3, now - 3 * DAY, "sports_car", demoLics[k % demoLics.size], false) })
    }

    fun board(trackId: Long, carId: Long): List<CommunityLap> {
        val i = combos.indexOfFirst { it.trackId == trackId && it.carId == carId }
        val c = combos[i]
        val r = Random(i * 31 + 7)
        return names.mapIndexed { k, n ->
            val time = c.lap - 0.7 + k * r.nextDouble(0.08, 0.35)
            CommunityLap("comm:$i:$k", n, time, now - k * DAY, true, sectors(time, r), false, demoLics[k % demoLics.size], true, k % 3 == 0)
        }.sortedBy { it.time }
    }

    fun reports(): List<SharedReport> = combos.flatMapIndexed { i, c ->
        (0 until 2).map { k -> SharedReport("rep$i$k", names[(i + k) % names.size], c.track, c.car, now - (i + k) * DAY, 3 + k * 4, 18 + i, c.lap + 0.3 + k * 0.2) }
    }

    fun setups(): List<SharedSetup> = combos.mapIndexed { i, c ->
        SharedSetup("set$i", names[i], "${c.track.substringBefore(" ")} race", c.car, c.track, "Stable on entry, a click less rear wing for the long straight.", 12 + i * 9, now - i * 3 * DAY)
    }

    fun races(): List<Race> {
        var ir = 2150
        return (0 until 8).map { k ->
            val c = combos[k % combos.size]
            val r = Random(k * 101)
            val field = 16 + r.nextInt(8)
            val start = 1 + r.nextInt(field)
            val finish = max(1, min(field, start + r.nextInt(-5, 5)))
            val change = ((field / 2 - finish) * 6.5 + r.nextInt(-8, 8)).toInt()
            val inc = r.nextInt(0, 9)
            val best = c.lap + 0.3 + r.nextDouble(0.0, 0.8)
            val laps = (1..15).map { n -> RaceLap(n, best + r.nextDouble(0.0, 1.5) + if (n == 1) 5 else 0, max(1, start + (finish - start) * n / 15), if (n == 4) min(inc, 4) else 0, n == 9) }
            val results = (1..field).map { p ->
                if (p == finish) RaceResult(p, "You", ir, best, inc, 15)
                else RaceResult(p, names[(p + k) % names.size], 1500 + r.nextInt(1600), best + r.nextDouble(-0.8, 1.2), r.nextInt(0, 10), 15)
            }
            val rec = Race(
                "demo-race-$k", now - k * DAY - 7_200_000, c.track, c.car, true, start, finish, field, inc, best, best - 0.4,
                best + 0.7, 0.42, 1, 38.5, ir, change, 1800 + r.nextInt(900), false, laps, results
            )
            ir -= change
            rec
        }
    }

    // a lap around the track, for the live screen
    fun live(tick: Int): Map<String, Any?> {
        val c = combos[0]
        val tr = trace(c, c.lap, 1)
        val i = tick % tr.rows.size
        val row = tr.rows[i]
        return mapOf(
            "Speed" to row[0], "RPM" to 4000 + row[0] * 80, "Gear" to row[3], "FuelLevel" to 62.0 - tick * 0.002,
            "Lap" to 4 + tick / tr.rows.size, "LapLastLapTime" to c.lap + 0.31,
            "LapBestLapTime" to c.lap + 0.12, "LapDeltaToBestLap" to sin(tick / 40.0) * 0.4, "Throttle" to row[1],
            "Brake" to row[2], "PlayerCarPosition" to 6 - (tick / tr.rows.size) % 3,
            // the lap's distance and number, so Full and Compare laps have laps to draw (each a little different)
            "LapDist" to i * 10.0, "LapCompleted" to 3 + tick / tr.rows.size, "LapCurrentLapTime" to row[5] * (1 + 0.004 * sin(tick / tr.rows.size * 1.7))
        )
    }
}
