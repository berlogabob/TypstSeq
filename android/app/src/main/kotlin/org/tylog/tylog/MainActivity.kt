package org.tylog.tylog

import android.content.Intent
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    private lateinit var safBridge: SafBridge
    private lateinit var shareChannel: MethodChannel
    private val pendingShares = java.util.ArrayDeque<Map<String, String>>()

    private fun receiveShare(intent: Intent?) {
        if (intent?.action != Intent.ACTION_SEND || intent.type != "text/plain") return
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString() ?: return
        val payload = mutableMapOf("text" to text)
        intent.getStringExtra(Intent.EXTRA_SUBJECT)?.let { payload["title"] = it }
        pendingShares.add(payload)
        intent.action = null
        if (::shareChannel.isInitialized) shareChannel.invokeMethod("shareAvailable", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        safBridge = SafBridge(this, flutterEngine.dartExecutor.binaryMessenger, activity = this)
        shareChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "org.tylog.tylog/share")
        shareChannel.setMethodCallHandler { call, result ->
            if (call.method == "getPendingShare") result.success(pendingShares.poll())
            else result.notImplemented()
        }
        receiveShare(intent)
        BackgroundSync.schedulePeriodic(this)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (::safBridge.isInitialized && safBridge.onActivityResult(requestCode, resultCode, data)) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        if (::safBridge.isInitialized) safBridge.dispose()
        super.onDestroy()
    }
}
