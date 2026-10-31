package com.pitlanehq.android.data

import android.content.Context
import com.google.android.gms.tasks.Tasks
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread

/** Instant notifications (Firebase Cloud Messaging), only with Account → Notifications on: the phone gives the server
 *  its token (POST /community/alerts/on with `push`), and a new alert wakes it at once with a message that only says
 *  "alerts"; the phone reads them as its background check does (Notify.check), in its own language. A build without
 *  the Firebase file (app/google-services.json) has no Firebase: the background check alone, as before. */
object Push {
    /** Firebase is in this build. */
    fun available(ctx: Context): Boolean = runCatching { FirebaseApp.getApps(ctx).isNotEmpty() || FirebaseApp.initializeApp(ctx) != null }.getOrDefault(false)

    /** This phone's token (blocking, off the main thread), or null without Firebase or a network. */
    fun token(ctx: Context): String? {
        if (!available(ctx)) return null
        return runCatching { Tasks.await(FirebaseMessaging.getInstance().token, 20, TimeUnit.SECONDS) }.getOrNull()?.ifBlank { null }
    }

    /** Notifications off: the token goes (a new one comes when they are turned on again). */
    fun forget(ctx: Context) {
        if (!available(ctx)) return
        runCatching { Tasks.await(FirebaseMessaging.getInstance().deleteToken(), 20, TimeUnit.SECONDS) }
    }
}

/** Firebase's messages: a new alert on the server (Notify.check reads it), and a new token for this phone. */
class PushService : FirebaseMessagingService() {
    override fun onMessageReceived(m: RemoteMessage) {
        if (m.data["kind"] == "alerts") Notify.check(applicationContext)
    }

    override fun onNewToken(token: String) {
        val ctx = applicationContext
        if (!Notify.on(ctx)) return
        thread { runCatching { AccountRepository(ctx).setAlertsOn(true, token) } }
    }
}
