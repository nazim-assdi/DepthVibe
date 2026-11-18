package com.ntech.depthvibe

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import com.ntech.depthvibe.ui.DepthVibeApp
import com.ntech.depthvibe.ui.DepthVibeTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            DepthVibeTheme {
                DepthVibeApp()
            }
        }
    }
}
