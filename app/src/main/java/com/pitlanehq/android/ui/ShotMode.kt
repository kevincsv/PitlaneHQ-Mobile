package com.pitlanehq.android.ui

import android.content.Context

/**
 * Debug builds only: the screenshot job in CI (.github/workflows/screenshots.yml) starts the app on one screen
 * ("route" or "route:tab") with the demo data, signed in as a sample admin, so the pictures are the app as it is.
 */
object ShotMode {
    var route: String? = null
    var tab: Int? = null

    fun prepare(c: Context, shot: String, lang: String) {
        c.getSharedPreferences("pitlane-account", Context.MODE_PRIVATE).edit()
            .putString("token", "screenshot").putString("display", "Piloto").putString("email", "piloto@example.com")
            .putBoolean("admin", true).putBoolean("verified", true).putBoolean("twoFactor", true).apply()
        c.getSharedPreferences("pitlane-app", Context.MODE_PRIVATE).edit().putBoolean("demo", true).putString("lang", lang).apply()
        val p = shot.split(":")
        route = p[0]
        tab = p.getOrNull(1)?.toIntOrNull()
    }
}
