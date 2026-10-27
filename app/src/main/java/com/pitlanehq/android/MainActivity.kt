package com.pitlanehq.android

import android.content.Intent
import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.pitlanehq.android.data.AuthReturns
import com.pitlanehq.android.ui.PitlaneApp
import com.pitlanehq.android.ui.ShotMode

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        // the app is always dark: light status and navigation bar icons, whatever the phone's theme
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(Color.TRANSPARENT),
            navigationBarStyle = SystemBarStyle.dark(Color.TRANSPARENT)
        )
        super.onCreate(savedInstanceState)
        if (BuildConfig.DEBUG) intent?.getStringExtra("shot")?.let { ShotMode.prepare(this, it, intent.getStringExtra("lang") ?: "es") }
        // opened by pitlanehq://steam or pitlanehq://discord: back from a sign-in or a link in the browser
        if (savedInstanceState == null) AuthReturns.deliver(intent?.data)
        setContent { PitlaneApp() }
    }

    // the app was already open (singleTask): the browser brings it back with the answer
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        AuthReturns.deliver(intent.data)
    }
}
