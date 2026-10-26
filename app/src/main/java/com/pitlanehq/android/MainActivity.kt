package com.pitlanehq.android

import android.graphics.Color
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
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
        setContent { PitlaneApp() }
    }
}
