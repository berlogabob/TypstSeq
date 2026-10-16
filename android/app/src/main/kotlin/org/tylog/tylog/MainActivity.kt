package org.tylog.tylog

import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Log
import android.webkit.MimeTypeMap
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    companion object {
        /// Read by [VaultSyncWorker]; same process, so a volatile flag is enough.
        @Volatile
        var foreground = false

        /// True from engine setup until destroy: a cold launch is "the app"
        /// before its first onResume, which a starting worker would miss.
        @Volatile
        var alive = false
    }

    private lateinit var safBridge: SafBridge
    private lateinit var shareChannel: MethodChannel
    private val pendingShares = java.util.ArrayDeque<Map<String, String>>()
    private val shareWorker = Executors.newSingleThreadExecutor()

    @Suppress("DEPRECATION")
    private fun receiveShare(intent: Intent?) {
        if (intent == null || (intent.action != Intent.ACTION_SEND &&
                intent.action != Intent.ACTION_SEND_MULTIPLE)) return
        val streams = if (intent.action == Intent.ACTION_SEND_MULTIPLE) {
            intent.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM).orEmpty()
        } else {
            listOfNotNull(intent.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))
        }
        val text = intent.getCharSequenceExtra(Intent.EXTRA_TEXT)?.toString()
        val title = intent.getStringExtra(Intent.EXTRA_SUBJECT)
        val intentMime = intent.type
        intent.action = null
        shareWorker.execute {
            val root = File(cacheDir, "shared")
            val cutoff = System.currentTimeMillis() - 24 * 60 * 60 * 1000L
            root.listFiles()?.filter { it.lastModified() < cutoff }?.forEach {
                it.deleteRecursively()
            }
            for (uri in streams) {
                val directory = File(root, UUID.randomUUID().toString())
                try {
                    val mime = contentResolver.getType(uri) ?: intentMime ?: "application/octet-stream"
                    val extension = MimeTypeMap.getSingleton().getExtensionFromMimeType(mime)
                    val fallback = "shared" + (extension?.let { ".$it" } ?: "")
                    val displayName = contentResolver.query(
                        uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null
                    )?.use { cursor ->
                        if (cursor.moveToFirst()) cursor.getString(0) else null
                    }
                    val name = displayName?.replace(Regex("[\\\\/\\p{Cntrl}]"), "_")
                        ?.trim()?.takeIf { it.isNotEmpty() && it != "." && it != ".." }
                        ?: fallback
                    check(directory.mkdirs()) { "Could not create shared file directory" }
                    val file = File(directory, name)
                    contentResolver.openInputStream(uri).use { input ->
                        checkNotNull(input) { "Could not open shared file" }
                        file.outputStream().use { output -> input.copyTo(output) }
                    }
                    val payload = mutableMapOf("path" to file.path, "name" to name, "mime" to mime)
                    text?.let { payload["text"] = it }
                    runOnUiThread { enqueueShare(payload) }
                } catch (error: Exception) {
                    directory.deleteRecursively()
                    Log.w("TyLog", "Could not copy shared file", error)
                }
            }
        }
        if (streams.isEmpty() && intentMime == "text/plain" && text != null) {
            val payload = mutableMapOf("text" to text)
            title?.let { payload["title"] = it }
            enqueueShare(payload)
        }
    }

    private fun enqueueShare(payload: Map<String, String>) {
        pendingShares.add(payload)
        if (::shareChannel.isInitialized) shareChannel.invokeMethod("shareAvailable", null)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        receiveShare(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        alive = true
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

    override fun onResume() {
        super.onResume()
        foreground = true
        SafBridge.forgetListings()
    }

    override fun onPause() {
        foreground = false
        super.onPause()
    }

    override fun onDestroy() {
        alive = false
        shareWorker.shutdown()
        if (::safBridge.isInitialized) safBridge.dispose()
        super.onDestroy()
    }
}
