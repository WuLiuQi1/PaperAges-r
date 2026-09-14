package com.example.paperages.paper_ages_reader

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var sourceWebViewBridge: SourceWebViewBridge? = null
    private var sourceInteractiveBrowserBridge: SourceInteractiveBrowserBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        sourceWebViewBridge = SourceWebViewBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
        sourceInteractiveBrowserBridge = SourceInteractiveBrowserBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    @Deprecated("Deprecated in Java")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (sourceInteractiveBrowserBridge?.onActivityResult(requestCode, resultCode, data) == true) {
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        sourceWebViewBridge?.dispose()
        sourceWebViewBridge = null
        sourceInteractiveBrowserBridge?.dispose()
        sourceInteractiveBrowserBridge = null
        super.onDestroy()
    }
}
