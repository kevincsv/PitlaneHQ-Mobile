package com.pitlanehq.android.model

import org.json.JSONArray
import org.json.JSONObject

/** One step of the coach's plan as the web writes it: what to work on (t), what it is worth (gain, s), why and how. */
data class PlanItem(val k: String, val gain: Double, val t: String, val why: String, val how: String)

/**
 * What the web's lap analysis and coach (pitwall-analysis.js, run by data/AnalysisJs) say about lap A against lap B:
 * the analyzer's corners, the coach's corners (the same, a corner taken differently every lap hearing about
 * consistency), the coach's plan and both laps' sectors (A, B). The screens show these instead of LapMath's.
 */
data class JsResult(val corners: List<Corner>, val coach: List<Corner>, val plan: List<PlanItem>, val secs: List<Pair<Double, Double>>)

/** What the coach learnt that the analysis weighs by: everyone's (/community/coach/weights) and the driver's own (/community/coach/me). */
data class CoachWeights(val w: Map<String, Double> = emptyMap(), val ask: Map<String, Double> = emptyMap(), val off: Set<String> = emptySet(),
                        val me: Map<String, Double> = emptyMap(), val habits: List<Triple<String, Int, Int>> = emptyList())

/** A lap's path as the web's analysis takes it (xy): x east and y north in metres, g its origin [lat, lon] when it comes from
 *  the game's position. Its length may differ from the lap's points (the model's fastest line, lineXY). */
data class LapPath(val x: List<Double>, val y: List<Double>, val g: List<Double>?)

object JsAnalysis {
    /** The shape of the module's answer this app reads; another one (a newer pitwall-analysis.js) is not run and LapMath is used. */
    const val VERSION = 1

    /** The module counts a point every 5 m: a trace of other points (the demo data's 10 m) goes to LapMath instead. */
    fun runs(tr: Trace) = kotlin.math.abs(tr.bin - 5.0) < 1e-6

    /** A trace's own path, when it has one. */
    fun pathOf(tr: Trace): LapPath? { val x = tr.x; val y = tr.y; return if (x != null && y != null) LapPath(x, y, tr.g?.takeIf { it.size == 2 }) else null }

    /** A lap in the web's shape: one point every 5 m, [speed m/s, lap time s, throttle, brake, gear, steering], and its path
     *  (the trace's own unless another is given: a model reference takes the web's, lineXY with its origin). */
    fun lap(tr: Trace, time: Double, sectors: List<Double>, path: LapPath? = pathOf(tr)): JSONObject {
        val bins = JSONArray()
        for (r in tr.rows) bins.put(JSONArray().put(num(r[0])).put(num(r.getOrElse(5) { 0.0 })).put(num(r.getOrElse(1) { 0.0 })).put(num(r.getOrElse(2) { 0.0 }))
            .put(num(r.getOrElse(3) { 0.0 })).put(num(r.getOrElse(4) { 0.0 })).put(JSONObject.NULL))
        val o = JSONObject().put("bins", bins).put("maxBin", tr.rows.size - 1).put("time", time)
        if (sectors.isNotEmpty()) o.put("sectors", JSONArray().apply { sectors.forEach { put(num(it)) } })
        val x = path?.x; val y = path?.y
        if (x != null && y != null && x.size == y.size && x.size > 10) {
            val p = JSONObject().put("x", JSONArray().apply { x.forEach { put(num(it)) } }).put("y", JSONArray().apply { y.forEach { put(num(it)) } })
            p.put("g", path.g?.takeIf { it.size == 2 }?.let { g -> JSONArray().put(g[0]).put(g[1]) } ?: JSONObject.NULL)
            o.put("xy", p)
        }
        return o
    }

    /** One lap of the session for the coach's plan (ctx.laps, how steady each corner is): only what it reads, the speed
     *  and the lap time at every point, and whether the lap is valid. */
    fun sessionLap(tr: Trace, valid: Boolean): JSONObject {
        val bins = JSONArray()
        for (r in tr.rows) bins.put(JSONArray().put(num(r[0])).put(num(r.getOrElse(5) { 0.0 })))
        return JSONObject().put("bins", bins).put("maxBin", tr.rows.size - 1).put("valid", valid)
    }

    private fun num(v: Double): Any = if (v.isFinite()) v else JSONObject.NULL

    /** The context the analysis reads: the language, the official turns, what the coach learnt and the model's corner cards. */
    fun ctx(lang: String, turns: List<Double>, w: CoachWeights, cards: List<CornerCard>): JSONObject {
        fun map(m: Map<String, Double>) = JSONObject().apply { m.forEach { (k, v) -> put(k, v) } }
        return JSONObject().put("lang", lang).put("units", "metric")
            .put("turns", if (turns.isEmpty()) JSONObject.NULL else JSONArray().apply { turns.forEach { put(it) } })
            .put("weights", JSONObject().put("w", map(w.w)).put("b", JSONObject().apply { w.ask.forEach { (k, v) -> put(k, JSONObject().put("ask", v)) } })
                .put("off", JSONArray().apply { w.off.forEach { put(it) } }))
            .put("me", JSONObject().put("w", map(w.me)).put("habits", JSONArray().apply { w.habits.forEach { (k, t, s) -> put(JSONObject().put("kind", k).put("tracks", t).put("sessions", s)) } }))
            .put("cards", JSONArray().apply { cards.forEach { put(JSONObject().put("apex", it.apex).put("spread", it.spread)) } })
    }

    /** What the engine evaluates, in order, after the file itself: the session's laps one call each (a call is limited in
     *  size on older WebViews), then the analysis with them in ctx.laps, in English, Spanish and Portuguese (so a change of
     *  language in Settings needs no new run), as one JSON string. */
    fun calls(a: JSONObject, b: JSONObject, ctx: JSONObject, laps: List<JSONObject>): List<String> =
        listOf("var __PWL=[];true") + laps.map { "__PWL.push($it);true" } +
            "(function(A,B,c){var o={};c.laps=__PWL;['en','es','pt'].forEach(function(l){c.lang=l;o[l]=PW_ANALYSIS.analyse(A,B,c)});__PWL=[];return JSON.stringify(o)})($a,$b,$ctx)"

    private fun corner(o: JSONObject): Corner {
        val ph = o.optJSONObject("ph")
        val text = o.optString("text", "")
        val kind = o.optString("kind", "")
        return Corner(
            n = o.optInt("n"), atM = Math.round(o.optDouble("d", 0.0)).toInt(), lost = o.optDouble("lost", 0.0),
            phases = PHASE_KEYS.associateWith { ph?.optDouble(it, 0.0) ?: 0.0 }, phase = if (o.isNull("phase")) null else o.optString("phase"),
            coastA = o.optDouble("coastA", 0.0), coastB = o.optDouble("coastB", 0.0),
            tip = if (text.isNotEmpty() && kind.isNotEmpty()) "tip_$kind" else null, args = emptyList(),
            apexM = Math.round(o.optDouble("apex", 0.0)).toInt(), cls = o.optString("cls", ""), text = text.ifEmpty { null }
        )
    }

    /** The analysis' answer as the screens' own structures, by language; null when it is not one, or not the shape this
     *  app was built for (its v). */
    fun parse(s: String): Map<String, JsResult>? = runCatching {
        val root = JSONObject(s)
        listOf("en", "es", "pt").associateWith { l -> root.getJSONObject(l).also { require(it.optInt("v", 0) == VERSION) }.let(::one) }
    }.getOrNull()

    private fun one(j: JSONObject): JsResult {
        fun list(a: JSONArray?) = (0 until (a?.length() ?: 0)).mapNotNull { a!!.optJSONObject(it) }
        val coach = j.getJSONObject("coach")
        return JsResult(
            list(j.optJSONArray("corners")).map(::corner), list(coach.optJSONArray("cs")).map(::corner),
            list(coach.optJSONArray("plan")).map { PlanItem(it.optString("k"), it.optDouble("gain", 0.0), it.optString("t"), it.optString("why"), it.optString("how")) },
            list(coach.optJSONArray("secs")).map { it.optDouble("a") to it.optDouble("b") }
        )
    }
}
