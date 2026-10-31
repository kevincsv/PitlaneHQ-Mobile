package com.pitlanehq.android.ui

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import com.pitlanehq.android.R

/** The Track First look's three fonts (res/font, the same files as iOS's Resources/Fonts): IBM Plex Sans for every
 *  text, JetBrains Mono for the numbers (times, places, iRating) and Barlow Condensed for the titles, the same as the
 *  design's and the web's. */
internal val UiFont = FontFamily(
    Font(R.font.plex_sans_regular, FontWeight.Normal),
    Font(R.font.plex_sans_medium, FontWeight.Medium),
    Font(R.font.plex_sans_semibold, FontWeight.SemiBold),
    // its heaviest face here is Bold, so black reads Bold
    Font(R.font.plex_sans_bold, FontWeight.Bold),
    Font(R.font.plex_sans_bold, FontWeight.ExtraBold),
    Font(R.font.plex_sans_bold, FontWeight.Black)
)

/** numbers: JetBrains Mono */
internal val MonoFont = FontFamily(
    Font(R.font.jetbrains_mono_regular, FontWeight.Normal),
    Font(R.font.jetbrains_mono_medium, FontWeight.Medium),
    Font(R.font.jetbrains_mono_semibold, FontWeight.SemiBold),
    Font(R.font.jetbrains_mono_bold, FontWeight.Bold),
    Font(R.font.jetbrains_mono_bold, FontWeight.ExtraBold),
    Font(R.font.jetbrains_mono_bold, FontWeight.Black)
)

/** titles and section labels: Barlow Condensed, written in capitals by the caller */
internal val DisplayFont = FontFamily(
    Font(R.font.barlow_condensed_semibold, FontWeight.Normal),
    Font(R.font.barlow_condensed_semibold, FontWeight.Medium),
    Font(R.font.barlow_condensed_semibold, FontWeight.SemiBold),
    Font(R.font.barlow_condensed_bold, FontWeight.Bold),
    Font(R.font.barlow_condensed_extrabold, FontWeight.ExtraBold),
    Font(R.font.barlow_condensed_extrabold, FontWeight.Black)
)

/** Material's text styles, all in IBM Plex Sans: every text that names no font. */
internal val PitlaneType: Typography = Typography().let { d ->
    fun TextStyle.ui() = copy(fontFamily = UiFont)
    Typography(
        displayLarge = d.displayLarge.ui(), displayMedium = d.displayMedium.ui(), displaySmall = d.displaySmall.ui(),
        headlineLarge = d.headlineLarge.ui(), headlineMedium = d.headlineMedium.ui(), headlineSmall = d.headlineSmall.ui(),
        titleLarge = d.titleLarge.ui(), titleMedium = d.titleMedium.ui(), titleSmall = d.titleSmall.ui(),
        bodyLarge = d.bodyLarge.ui(), bodyMedium = d.bodyMedium.ui(), bodySmall = d.bodySmall.ui(),
        labelLarge = d.labelLarge.ui(), labelMedium = d.labelMedium.ui(), labelSmall = d.labelSmall.ui()
    )
}
