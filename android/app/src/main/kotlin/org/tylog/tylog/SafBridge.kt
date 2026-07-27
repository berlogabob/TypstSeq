package org.tylog.tylog

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileNotFoundException
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.withLock

class SafBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    companion object {
        private const val CHANNEL = "org.tylog.tylog/saf"
        private const val PICK_TREE = 4815
        private const val DIRECTORY_MIME = DocumentsContract.Document.MIME_TYPE_DIR
    }

    private val resolver = activity.contentResolver
    private val mainHandler = Handler(Looper.getMainLooper())
    // Reads fan out; mutations stay on one thread.
    private val readExecutor = Executors.newFixedThreadPool(4)
    private val writeExecutor = Executors.newSingleThreadExecutor()

    // ...but a mutation must still never be *observed* half-done, which is
    // what the old single executor guaranteed for free. writeAtomic renames
    // the target to `.backup` before renaming the temp into place, and in that
    // window the file does not exist under its own name. A concurrent `list`
    // there makes sync conclude the note was deleted locally and propagate
    // that as a remote delete; a concurrent `stat` returns null and means the
    // same thing. So: readers run in parallel with each other, and never with
    // a writer. Held for one operation, taken in exactly one place
    // (runStorage), so there is no lock ordering to get wrong.
    // Fair: a full-vault scan is a long burst of reads, and a non-fair lock
    // would let it starve the autosave write queued behind it.
    private val storageLock = ReentrantReadWriteLock(true)

    private val mutatingMethods = setOf(
        "createDirectory", "write", "delete", "deleteRoot", "releaseAccess", "import",
    )
    private val channel = MethodChannel(messenger, CHANNEL)

    // Resolving "articles/foo.typ" without this means a full child-directory
    // cursor scan per path segment — enumerating all ~1700 entries of
    // articles/ on every single read. The recursive listing that starts every
    // scan warms this for the whole tree for free (see listInto).
    //
    // ponytail: process-lifetime memo, no size bound — one entry per vault
    // file. Evicted on our own writes/deletes; an external app replacing a
    // file is caught by the retry in withResolved and the existence checks in
    // exists/stat. Add an LRU only if a vault ever gets big enough to care.
    private val uriCache = ConcurrentHashMap<Pair<String, String>, Uri>()

    private var pendingPick: MethodChannel.Result? = null
    @Volatile private var disposed = false

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method in setOf(
                "startSyncForeground",
                "updateSyncForeground",
                "stopSyncForeground",
            )
        ) {
            try {
                when (call.method) {
                    "startSyncForeground" -> SyncForegroundService.start(
                        activity,
                        call.argument<String>("detail"),
                    )
                    "updateSyncForeground" -> SyncForegroundService.update(
                        call.argument<String>("detail"),
                    )
                    "stopSyncForeground" -> SyncForegroundService.stop(activity)
                }
                result.success(null)
            } catch (error: Throwable) {
                result.error(
                    "foreground_sync_error",
                    error.message ?: error.javaClass.simpleName,
                    null,
                )
            }
            return
        }

        if (call.method == "pickTree") {
            if (pendingPick != null) {
                result.error("already_active", "Folder picker is already active", null)
                return
            }
            pendingPick = result
            activity.startActivityForResult(
                Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                    addFlags(
                        Intent.FLAG_GRANT_READ_URI_PERMISSION or
                            Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                            Intent.FLAG_GRANT_PREFIX_URI_PERMISSION,
                    )
                },
                PICK_TREE,
            )
            return
        }

        if (call.method == "hasAccess") {
            val tree = Uri.parse(call.argument<String>("uri") ?: error("Missing tree URI"))
            val granted = resolver.persistedUriPermissions.any {
                it.uri == tree && it.isReadPermission && it.isWritePermission
            }
            result.success(granted)
            return
        }

        if (call.method == "persistAccess") {
            val tree = Uri.parse(call.argument<String>("uri") ?: error("Missing tree URI"))
            try {
                resolver.takePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                )
                result.success(null)
            } catch (error: Throwable) {
                result.error(
                    "invalid_folder",
                    "This folder cannot provide persistent access: ${error.message}",
                    null,
                )
            }
            return
        }

        if (call.method !in setOf(
                "exists", "createDirectory", "list", "stat", "read", "write",
                "delete", "deleteRoot", "releaseAccess", "hash", "import",
                "materialize", "open",
            )
        ) {
            result.notImplemented()
            return
        }
        runStorage(result, call.method in mutatingMethods) {
            val tree = Uri.parse(call.argument<String>("uri") ?: error("Missing tree URI"))
            when (call.method) {
                // A cached uri can outlive its document, so existence is
                // answered by querying the document, not by having found a
                // cache entry for it.
                "exists" -> resolve(tree, path(call))?.let { document ->
                    documentExists(document) || run {
                        invalidate(tree, path(call))
                        resolve(tree, path(call)) != null
                    }
                } ?: false
                "createDirectory" -> ensureDirectory(tree, path(call)).let { null }
                "list" -> list(
                    tree,
                    path(call),
                    call.argument<Boolean>("recursive") == true,
                )
                // Absent still means null, but a *failure* must never be
                // reported as null: sync reads a null stat as "deleted
                // locally" and would propagate that as a remote delete. So
                // only a stale cache entry is retried; a second failure
                // propagates as an error.
                "stat" -> resolve(tree, path(call))?.let { document ->
                    runCatching { metadata(document) }.getOrElse {
                        invalidate(tree, path(call))
                        resolve(tree, path(call))?.let(::metadata)
                    }
                }
                "read" -> withResolved(tree, path(call), ::read)
                "write" -> writeAtomic(
                    tree,
                    path(call),
                    call.argument<ByteArray>("bytes") ?: ByteArray(0),
                ).let { null }
                "delete" -> resolve(tree, path(call))
                    ?.let { DocumentsContract.deleteDocument(resolver, it) }
                    .also { invalidate(tree, path(call)) }
                    .let { null }
                "deleteRoot" -> {
                    val document = root(tree)
                    if (documentExists(document)) {
                        require(DocumentsContract.deleteDocument(resolver, document)) {
                            "Storage provider could not delete the vault folder"
                        }
                    }
                    invalidate(tree, "")
                    null
                }
                "releaseAccess" -> resolver.releasePersistableUriPermission(
                    tree,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
                ).also { invalidate(tree, "") }.let { null }
                "hash" -> withResolved(tree, path(call), ::hash)
                "import" -> writeAtomic(
                    tree,
                    path(call),
                    File(call.argument<String>("source") ?: error("Missing source")),
                ).let { null }
                "materialize" -> withResolved(tree, path(call), ::materialize).path
                "open" -> {
                    val document = resolveRequired(tree, path(call))
                    val extension = path(call).substringAfterLast('.', "")
                    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                        ?: "application/octet-stream"
                    OpenRequest(document, mime)
                }
                else -> null
            }
        }
    }

    private fun runStorage(
        result: MethodChannel.Result,
        mutating: Boolean,
        work: () -> Any?,
    ) {
        val lock = if (mutating) storageLock.writeLock() else storageLock.readLock()
        (if (mutating) writeExecutor else readExecutor).execute {
            try {
                val value = lock.withLock { work() }
                postMain {
                    if (value is OpenRequest) {
                        activity.startActivity(
                            Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(value.uri, value.mime)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            },
                        )
                        result.success(null)
                    } else {
                        result.success(value)
                    }
                }
            } catch (error: Throwable) {
                postMain {
                    result.error("saf_error", error.message ?: error.javaClass.simpleName, null)
                }
            }
        }
    }

    private fun postMain(action: () -> Unit) {
        if (!disposed) mainHandler.post { if (!disposed) action() }
    }

    private data class OpenRequest(val uri: Uri, val mime: String)

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        val uri = data.data!!
        readExecutor.execute {
            try {
                val name = displayName(root(uri))
                postMain { result.success(mapOf("uri" to uri.toString(), "name" to name)) }
            } catch (error: Throwable) {
                postMain {
                    result.error(
                        "invalid_folder",
                        "This folder cannot be read: ${error.message}",
                        null,
                    )
                }
            }
        }
        return true
    }

    fun dispose() {
        disposed = true
        pendingPick = null
        channel.setMethodCallHandler(null)
        mainHandler.removeCallbacksAndMessages(null)
        readExecutor.shutdownNow()
        writeExecutor.shutdownNow()
        uriCache.clear()
    }

    private fun path(call: MethodCall): String = safePath(call.argument<String>("path") ?: "")

    private fun safePath(value: String): String {
        val normalized = value.replace('\\', '/').trim('/')
        require(normalized.split('/').none { it == "." || it == ".." }) { "Unsafe vault path" }
        return normalized
    }

    private fun root(tree: Uri): Uri = DocumentsContract.buildDocumentUriUsingTree(
        tree,
        DocumentsContract.getTreeDocumentId(tree),
    )

    private fun resolveRequired(tree: Uri, path: String): Uri =
        resolve(tree, path) ?: error("Vault item not found: $path")

    private fun cacheKey(tree: Uri, path: String) = tree.toString() to path

    /**
     * Drops [path] and everything beneath it — a deleted folder takes its
     * subtree's document ids with it. An empty path clears the whole vault.
     */
    private fun invalidate(tree: Uri, path: String) {
        val safe = safePath(path)
        val vault = tree.toString()
        uriCache.keys.removeAll { (owner, cached) ->
            owner == vault &&
                (safe.isEmpty() || cached == safe || cached.startsWith("$safe/"))
        }
    }

    private fun resolve(tree: Uri, path: String): Uri? {
        val safe = safePath(path)
        if (safe.isEmpty()) return root(tree)
        uriCache[cacheKey(tree, safe)]?.let { return it }
        var current = root(tree)
        var walked = ""
        for (part in safe.split('/')) {
            current = child(tree, current, part) ?: return null
            walked = if (walked.isEmpty()) part else "$walked/$part"
            uriCache[cacheKey(tree, walked)] = current
        }
        return current
    }

    /**
     * Runs [work] against [path]'s document, retrying once against a freshly
     * walked uri if the cached document id turned out to be dead — an external
     * app replacing a file is the case our own invalidation misses.
     */
    private fun <T> withResolved(tree: Uri, path: String, work: (Uri) -> T): T {
        val uri = resolveRequired(tree, path)
        return try {
            work(uri)
        } catch (error: FileNotFoundException) {
            invalidate(tree, path)
            work(resolveRequired(tree, path))
        }
    }

    private fun ensureDirectory(tree: Uri, path: String): Uri {
        var current = root(tree)
        if (path.isEmpty()) return current
        var walked = ""
        for (part in safePath(path).split('/')) {
            walked = if (walked.isEmpty()) part else "$walked/$part"
            val cached = uriCache[cacheKey(tree, walked)]
            if (cached != null) {
                current = cached
                continue
            }
            val existing = child(tree, current, part)
            current = if (existing == null) {
                DocumentsContract.createDocument(resolver, current, DIRECTORY_MIME, part)
                    ?: error("Could not create folder $part")
            } else {
                require(isDirectory(existing)) { "$part is not a folder" }
                existing
            }
            uriCache[cacheKey(tree, walked)] = current
        }
        return current
    }

    private fun child(tree: Uri, parent: Uri, name: String): Uri? {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getDocumentId(parent),
        )
        query(children).use { cursor ->
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            while (cursor.moveToNext()) {
                if (cursor.getString(nameColumn) == name) {
                    return DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(idColumn))
                }
            }
        }
        return null
    }

    private fun list(tree: Uri, path: String, recursive: Boolean): List<Map<String, Any?>> {
        val parent = resolve(tree, path) ?: return emptyList()
        require(isDirectory(parent)) { "$path is not a folder" }
        val out = mutableListOf<Map<String, Any?>>()
        listInto(tree, parent, path, recursive, out)
        return out
    }

    private fun listInto(
        tree: Uri,
        parent: Uri,
        prefix: String,
        recursive: Boolean,
        out: MutableList<Map<String, Any?>>,
    ) {
        val children = DocumentsContract.buildChildDocumentsUriUsingTree(
            tree,
            DocumentsContract.getDocumentId(parent),
        )
        query(children).use { cursor ->
            val idColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DOCUMENT_ID)
            val nameColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME)
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val sizeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            while (cursor.moveToNext()) {
                val uri = DocumentsContract.buildDocumentUriUsingTree(tree, cursor.getString(idColumn))
                val name = cursor.getString(nameColumn)
                val childPath = if (prefix.isEmpty()) name else "$prefix/$name"
                val directory = cursor.getString(mimeColumn) == DIRECTORY_MIME
                // Free cache warming: every scan starts with a recursive list,
                // so the reads that follow never re-enumerate a directory.
                uriCache[cacheKey(tree, childPath)] = uri
                out += mapOf(
                    "path" to childPath,
                    "isDirectory" to directory,
                    "size" to if (directory || cursor.isNull(sizeColumn)) null else cursor.getLong(sizeColumn),
                    "modified" to if (cursor.isNull(modifiedColumn)) null else cursor.getLong(modifiedColumn),
                )
                if (recursive && directory) listInto(tree, uri, childPath, true, out)
            }
        }
    }

    private fun metadata(uri: Uri): Map<String, Any?> {
        query(uri).use { cursor ->
            require(cursor.moveToFirst()) { "Document disappeared" }
            val mimeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)
            val directory = cursor.getString(mimeColumn) == DIRECTORY_MIME
            val sizeColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_SIZE)
            val modifiedColumn = cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_LAST_MODIFIED)
            return mapOf(
                "isDirectory" to directory,
                "size" to if (directory || cursor.isNull(sizeColumn)) null else cursor.getLong(sizeColumn),
                "modified" to if (cursor.isNull(modifiedColumn)) null else cursor.getLong(modifiedColumn),
            )
        }
    }

    private fun documentExists(uri: Uri): Boolean = try {
        query(uri).use { it.moveToFirst() }
    } catch (_: FileNotFoundException) {
        false
    }

    private fun query(uri: Uri): Cursor = resolver.query(
        uri,
        arrayOf(
            DocumentsContract.Document.COLUMN_DOCUMENT_ID,
            DocumentsContract.Document.COLUMN_DISPLAY_NAME,
            DocumentsContract.Document.COLUMN_MIME_TYPE,
            DocumentsContract.Document.COLUMN_SIZE,
            DocumentsContract.Document.COLUMN_LAST_MODIFIED,
        ),
        null,
        null,
        null,
    ) ?: error("Storage provider returned no result")

    private fun displayName(uri: Uri): String {
        query(uri).use { cursor ->
            require(cursor.moveToFirst()) { "Folder disappeared" }
            return cursor.getString(
                cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_DISPLAY_NAME),
            )
        }
    }

    private fun isDirectory(uri: Uri): Boolean {
        query(uri).use { cursor ->
            return cursor.moveToFirst() &&
                cursor.getString(cursor.getColumnIndexOrThrow(DocumentsContract.Document.COLUMN_MIME_TYPE)) == DIRECTORY_MIME
        }
    }

    private fun read(uri: Uri): ByteArray =
        resolver.openInputStream(uri)?.use { it.readBytes() } ?: error("Could not read document")

    private fun writeAtomic(tree: Uri, path: String, bytes: ByteArray) {
        val source = File.createTempFile("tylog-write-", ".tmp", activity.cacheDir)
        try {
            source.writeBytes(bytes)
            writeAtomic(tree, path, source)
        } finally {
            source.delete()
        }
    }

    private fun writeAtomic(tree: Uri, path: String, source: File) {
        val safe = safePath(path)
        require(safe.isNotEmpty()) { "Cannot write the vault root" }
        val name = safe.substringAfterLast('/')
        val parentPath = safe.substringBeforeLast('/', "")
        val parent = ensureDirectory(tree, parentPath)
        val target = resolve(tree, safe)
        // Every write mints a new document id, so the old one is dead from
        // here on. Dropped up front: any failure below then just re-walks.
        invalidate(tree, safe)
        val temporaryName = ".$name.tylog-${System.nanoTime()}.tmp"
        val temporary = DocumentsContract.createDocument(
            resolver,
            parent,
            "application/octet-stream",
            temporaryName,
        ) ?: error("Could not create temporary document")
        try {
            resolver.openFileDescriptor(temporary, "wt")?.use { descriptor ->
                FileInputStream(source).use { input ->
                    FileOutputStream(descriptor.fileDescriptor).use { output ->
                        input.copyTo(output)
                        output.flush()
                        descriptor.fileDescriptor.sync()
                    }
                }
            } ?: error("Could not write temporary document")
            if (target == null) {
                val created = DocumentsContract.renameDocument(resolver, temporary, name)
                requireNotNull(created) { "Storage provider cannot rename documents safely" }
                uriCache[cacheKey(tree, safe)] = created
                return
            }
            val backupName = ".$name.tylog-${System.nanoTime()}.backup"
            val backup = DocumentsContract.renameDocument(resolver, target, backupName)
                ?: error("Storage provider cannot replace documents safely")
            try {
                val committed = DocumentsContract.renameDocument(resolver, temporary, name)
                requireNotNull(committed) { "Storage provider could not commit document" }
                uriCache[cacheKey(tree, safe)] = committed
                DocumentsContract.deleteDocument(resolver, backup)
            } catch (error: Throwable) {
                runCatching { DocumentsContract.renameDocument(resolver, backup, name) }
                throw error
            }
        } catch (error: Throwable) {
            runCatching { DocumentsContract.deleteDocument(resolver, temporary) }
            throw error
        }
    }

    private fun hash(uri: Uri): String {
        val digest = MessageDigest.getInstance("SHA-256")
        resolver.openInputStream(uri)?.use { input ->
            val buffer = ByteArray(DEFAULT_BUFFER_SIZE)
            while (true) {
                val count = input.read(buffer)
                if (count < 0) break
                digest.update(buffer, 0, count)
            }
        } ?: error("Could not hash document")
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun materialize(uri: Uri): File {
        val file = File.createTempFile("tylog-materialized-", ".tmp", activity.cacheDir)
        resolver.openInputStream(uri)?.use { input ->
            FileOutputStream(file).use(input::copyTo)
        } ?: error("Could not materialize document")
        return file
    }

}
