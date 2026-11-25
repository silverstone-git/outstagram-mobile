package com.cyto.outstagram

import androidx.media3.common.util.UnstableApi
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    @UnstableApi
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        VideoCompressor(applicationContext, flutterEngine.dartExecutor.binaryMessenger)
    }
}
