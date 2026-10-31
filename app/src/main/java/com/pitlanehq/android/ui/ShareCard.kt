package com.pitlanehq.android.ui

import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import androidx.core.content.FileProvider
import com.pitlanehq.android.model.lapTime
import java.io.File

/**
 * "Share my lap": the same 1200×630 picture as the web's (lapCardCanvas in index.html), the dark card with the amber
 * edge, Pitlane HQ and the game, the track, the car, the time, "P3 of 42 on the leaderboard" and pitlanehq.app, handed
 * to the phone's share sheet.
 */
object ShareCard {
    fun bitmap(track: String, car: String, time: Double, pos: Int, of: Int, game: String): Bitmap {
        val w = 1200; val h = 630
        val bm = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(bm)
        val p = Paint(Paint.ANTI_ALIAS_FLAG)
        c.drawColor(0xFF0D1116.toInt())
        p.color = 0xFF161C24.toInt(); c.drawRoundRect(RectF(40f, 40f, w - 40f, h - 40f), 24f, 24f, p)
        p.style = Paint.Style.STROKE; p.strokeWidth = 2f; p.color = 0xFF263140.toInt(); c.drawRoundRect(RectF(40f, 40f, w - 40f, h - 40f), 24f, 24f, p)
        p.style = Paint.Style.FILL; p.color = 0xFFFFB02E.toInt(); c.drawRect(40f, 92f, 48f, h - 92f, p)
        val bold = Typeface.create(Typeface.SANS_SERIF, Typeface.BOLD)
        fun text(s: String, x: Float, y: Float, size: Float, color: Int, tf: Typeface = bold, right: Boolean = false, max: Float = 0f) {
            p.typeface = tf; p.color = color; p.textSize = size; p.textAlign = if (right) Paint.Align.RIGHT else Paint.Align.LEFT
            if (max > 0) while (p.measureText(s) > max && p.textSize > 20f) p.textSize -= 2f
            c.drawText(s, x, y, p)
        }
        text("PITLANE HQ", 88f, 100f, 30f, 0xFFFFB02E.toInt())
        text(if (game == "lmu") "Le Mans Ultimate" else "iRacing", w - 88f, 100f, 26f, 0xFF8A96A8.toInt(), right = true)
        text(track.uppercase(), 88f, 200f, 76f, 0xFFE7EBF1.toInt(), max = w - 176f)
        text(car, 88f, 256f, 40f, 0xFFAAB4C3.toInt(), max = w - 176f)
        text(lapTime(time), 82f, 440f, 170f, 0xFFFFB02E.toInt(), Typeface.create(Typeface.MONOSPACE, Typeface.BOLD))
        val pl = "P$pos"
        text(pl, 88f, 524f, 54f, 0xFFE7EBF1.toInt())
        val pw = p.measureText(pl)
        text(t("share_card_of", of), 88f + pw + 18f, 522f, 34f, 0xFF8A96A8.toInt())
        text("pitlanehq.app", w - 88f, 524f, 28f, 0xFF6C7789.toInt(), right = true)
        return bm
    }

    fun share(ctx: Context, track: String, car: String, time: Double, pos: Int, of: Int, game: String) {
        val dir = File(ctx.cacheDir, "share").apply { mkdirs() }
        val f = File(dir, "pitlanehq-" + track.lowercase().replace(Regex("[^a-z0-9]+"), "-").trim('-').ifBlank { "lap" } + ".png")
        f.outputStream().use { bitmap(track, car, time, pos, of, game).compress(Bitmap.CompressFormat.PNG, 100, it) }
        val uri = FileProvider.getUriForFile(ctx, "com.pitlanehq.android.share", f)
        val send = Intent(Intent.ACTION_SEND).setType("image/png").putExtra(Intent.EXTRA_STREAM, uri)
            .putExtra(Intent.EXTRA_TEXT, "$track · $car · ${lapTime(time)} · P$pos · pitlanehq.app").addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        ctx.startActivity(Intent.createChooser(send, t("share_my_lap")).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}
