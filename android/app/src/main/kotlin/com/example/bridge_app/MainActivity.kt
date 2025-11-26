package com.example.bridge_app

import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Explicitly allow screenshots (this is the default, but being explicit helps)
        try {
            window?.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
        } catch (e: Exception) {
            // Ignore if window is not available yet
        }
    }
}
