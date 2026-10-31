package com.pitlanehq.android.data

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import com.pitlanehq.android.MainActivity
import com.pitlanehq.android.R
import com.pitlanehq.android.model.lapTime
import com.pitlanehq.android.ui.t
import kotlin.concurrent.thread

/** The phone's notifications, only with Account → Notifications on (never by email): a record of yours another driver
 *  beat and the summary of your week (the server's alerts.js, read in the background every 30 minutes by AlertJob), and
 *  a reminder 15 minutes before each race in the Planner's plan (an alarm per race, RaceReminder). */
object Notify {
    private const val CH_ALERTS = "alerts"
    private const val CH_RACES = "races"
    private const val JOB = 4101
    const val LEAD = 15 * 60_000L
    private fun prefs(ctx: Context) = ctx.getSharedPreferences("pitlane-notify", Context.MODE_PRIVATE)

    fun on(ctx: Context) = prefs(ctx).getBoolean("on", false)
    fun allowed(ctx: Context) = Build.VERSION.SDK_INT < 33 || ContextCompat.checkSelfPermission(ctx, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED

    /** On: the background check and the plan's reminders start; off: both stop. */
    fun setOn(ctx: Context, on: Boolean, plan: List<PlannedRace>) {
        val e = prefs(ctx).edit().putBoolean("on", on)
        if (on && !prefs(ctx).contains("since")) e.putLong("since", System.currentTimeMillis())
        e.apply()
        val js = ctx.getSystemService(JobScheduler::class.java)
        if (on) {
            channels(ctx)
            js.schedule(JobInfo.Builder(JOB, ComponentName(ctx, AlertJob::class.java)).setPeriodic(30 * 60_000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY).setPersisted(true).build())
        } else js.cancel(JOB)
        plan(ctx, if (on) plan else emptyList())
    }

    private fun channels(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(NotificationChannel(CH_ALERTS, t("notify_ch_alerts"), NotificationManager.IMPORTANCE_DEFAULT))
        nm.createNotificationChannel(NotificationChannel(CH_RACES, t("notify_ch_races"), NotificationManager.IMPORTANCE_HIGH))
    }

    /** The app's language when it is not running (the texts are written here, in the background). */
    private fun lang(ctx: Context) {
        com.pitlanehq.android.ui.I18n.choice = ctx.getSharedPreferences("pitlane-app", Context.MODE_PRIVATE).getString("lang", "system") ?: "system"
    }

    fun post(ctx: Context, id: Int, ch: String, title: String, text: String) {
        if (!on(ctx) || !allowed(ctx)) return
        channels(ctx)
        val open = PendingIntent.getActivity(ctx, 0, Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP), PendingIntent.FLAG_IMMUTABLE)
        val n = NotificationCompat.Builder(ctx, ch).setSmallIcon(R.drawable.ic_notify).setColor(0xFFFFB02E.toInt()).setContentTitle(title).setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text)).setContentIntent(open).setAutoCancel(true).build()
        try { NotificationManagerCompat.from(ctx).notify(id, n) } catch (e: SecurityException) {}
    }

    /** The server's alerts since the last check, as notifications. */
    fun check(ctx: Context) {
        if (!on(ctx)) return
        lang(ctx)
        val repo = AccountRepository(ctx.applicationContext)
        val since = prefs(ctx).getLong("since", System.currentTimeMillis())
        val r = runCatching { repo.alerts(since) }.getOrNull() ?: return
        val a = r.optJSONArray("alerts") ?: return
        for (i in a.length() - 1 downTo 0) {
            val x = a.getJSONObject(i)
            when (x.optString("kind")) {
                "record_beaten" -> {
                    val by = x.optString("by").ifBlank { t("notify_someone") }
                    post(ctx, x.optString("id").hashCode(), CH_ALERTS, t("notify_record_title", x.optString("track")),
                        t("notify_record_text", by, lapTime(x.optDouble("time")), x.optString("car"), String.format(java.util.Locale.ROOT, "%.3f", x.optDouble("was") - x.optDouble("time"))))
                }
                "week" -> post(ctx, x.optString("id").hashCode(), CH_ALERTS, x.optString("title"), x.optString("text"))
            }
        }
        prefs(ctx).edit().putLong("since", r.optLong("now", System.currentTimeMillis())).apply()
    }

    /** One alarm 15 minutes before each race of the plan still to come (the ones of before are cancelled). */
    fun plan(ctx: Context, plan: List<PlannedRace>) {
        val am = ctx.getSystemService(AlarmManager::class.java)
        val old = prefs(ctx).getStringSet("alarms", emptySet()) ?: emptySet()
        for (k in old) am.cancel(raceIntent(ctx, k.toInt(), null))
        val now = System.currentTimeMillis()
        val keep = mutableSetOf<String>()
        if (on(ctx)) for (r in plan) {
            val at = r.t - LEAD
            if (at <= now) continue
            val code = (r.sid.toString() + ":" + r.t).hashCode()
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, at, raceIntent(ctx, code, r))
            keep += code.toString()
        }
        prefs(ctx).edit().putStringSet("alarms", keep).apply()
    }

    private fun raceIntent(ctx: Context, code: Int, r: PlannedRace?): PendingIntent {
        val i = Intent(ctx, RaceReminder::class.java)
        if (r != null) i.putExtra("name", r.name).putExtra("track", r.track).putExtra("t", r.t)
        return PendingIntent.getBroadcast(ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
    }

    fun race(ctx: Context, name: String, track: String, at: Long) {
        lang(ctx)
        post(ctx, (name + at).hashCode(), CH_RACES, t("notify_race_title", name), track)
    }
}

/** Every 30 minutes with a network: the server's new alerts (Notify.check). */
class AlertJob : JobService() {
    override fun onStartJob(p: JobParameters): Boolean {
        thread { try { Notify.check(applicationContext) } finally { jobFinished(p, false) } }
        return true
    }
    override fun onStopJob(p: JobParameters) = true
}

/** A race of the plan starts in 15 minutes. */
class RaceReminder : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) = Notify.race(ctx, i.getStringExtra("name").orEmpty(), i.getStringExtra("track").orEmpty(), i.getLongExtra("t", 0))
}

/** After the phone starts again the plan's alarms are set again (the background check is persisted by itself). */
class BootReminders : BroadcastReceiver() {
    override fun onReceive(ctx: Context, i: Intent) {
        if (i.action == Intent.ACTION_BOOT_COMPLETED && Notify.on(ctx)) Notify.plan(ctx, AccountRepository(ctx.applicationContext).plannerPlan)
    }
}
