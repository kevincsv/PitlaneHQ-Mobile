package com.pitlanehq.android.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The phone hands the web's analysis (pitwall-analysis.js) its laps in the web's own shape (lapShape in index.html): one
 *  point every 5 m as [speed m/s, lap time s, throttle, brake, gear, steering, null], the last point's index, the time,
 *  the sectors and the path. The module's answers are checked by tools/check-analysis.mjs; this checks what goes in. */
class JsAnalysisTest {
    private fun trace(n: Int = 30) = Trace(5.0, List(n) { i -> doubleArrayOf(50.0 + i, 0.8, 0.1, 4.0, -0.05, i * 0.1) },
        x = List(n) { it * 5.0 }, y = List(n) { 0.0 }, g = listOf(50.4, 5.97))

    @Test fun lapIsTheWebsShape() {
        val o = JsAnalysis.lap(trace(), 137.456, listOf(40.1, 50.2, 47.156))
        val bins = o.getJSONArray("bins")
        assertEquals(30, bins.length())
        assertEquals(29, o.getInt("maxBin"))
        assertEquals(137.456, o.getDouble("time"), 1e-9)
        val b = bins.getJSONArray(3)
        assertEquals(7, b.length())
        assertEquals(53.0, b.getDouble(0), 1e-9)   // speed
        assertEquals(0.3, b.getDouble(1), 1e-9)    // lap time at that point
        assertEquals(0.8, b.getDouble(2), 1e-9)    // throttle
        assertEquals(0.1, b.getDouble(3), 1e-9)    // brake
        assertEquals(4.0, b.getDouble(4), 1e-9)    // gear
        assertEquals(-0.05, b.getDouble(5), 1e-9)  // steering
        assertTrue(b.isNull(6))
        assertEquals(3, o.getJSONArray("sectors").length())
        val xy = o.getJSONObject("xy")
        assertEquals(30, xy.getJSONArray("x").length())
        assertEquals(50.4, xy.getJSONArray("g").getDouble(0), 1e-9)
    }

    @Test fun aShortPathIsLeftOut() {
        val t = trace(8)
        assertFalse(JsAnalysis.lap(t, 60.0, emptyList()).has("xy"))
        assertFalse(JsAnalysis.lap(t, 60.0, emptyList()).has("sectors"))
    }

    @Test fun notANumberGoesAsNull() {
        val t = Trace(5.0, listOf(doubleArrayOf(Double.NaN, 1.0, 0.0, 3.0, 0.0, 0.0)))
        assertTrue(JsAnalysis.lap(t, 60.0, emptyList()).getJSONArray("bins").getJSONArray(0).isNull(0))
    }

    @Test fun onlyFiveMetreTracesRun() {
        assertTrue(JsAnalysis.runs(trace()))
        assertFalse(JsAnalysis.runs(Trace(10.0, emptyList())))
    }

    @Test fun sessionLapCarriesSpeedTimeAndValidity() {
        val o = JsAnalysis.sessionLap(trace(), false)
        assertEquals(2, o.getJSONArray("bins").getJSONArray(0).length())
        assertFalse(o.getBoolean("valid"))
    }
}
