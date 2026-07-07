package org.tylog.tylog

import android.app.Activity
import android.content.Intent
import android.database.Cursor
import android.net.Uri
import android.provider.DocumentsContract
import android.webkit.MimeTypeMap
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest

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
    private var pendingPick: MethodChannel.Result? = null

    init {
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
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

        try {
            val tree = Uri.parse(call.argument<String>("uri") ?: error("Missing tree URI"))
            when (call.method) {
                "exists" -> result.success(resolve(tree, path(call)) != null)
                "createDirectory" -> {
                    ensureDirectory(tree, path(call))
                    result.success(null)
                }
                "list" -> result.success(
                    list(
                        tree,
                        path(call),
                        call.argument<Boolean>("recursive") == true,
                    ),
                )
                "stat" -> result.success(resolve(tree, path(call))?.let(::metadata))
                "read" -> result.success(read(resolveRequired(tree, path(call))))
                "write" -> {
                    writeAtomic(
                        tree,
                        path(call),
                        call.argument<ByteArray>("bytes") ?: ByteArray(0),
                    )
                    result.success(null)
                }
                "delete" -> {
                    resolve(tree, path(call))?.let { DocumentsContract.deleteDocument(resolver, it) }
                    result.success(null)
                }
                "hash" -> result.success(hash(resolveRequired(tree, path(call))))
                "import" -> {
                    val source = File(call.argument<String>("source") ?: error("Missing source"))
                    writeAtomic(tree, path(call), source)
                    result.success(null)
                }
                "materialize" -> result.success(materialize(resolveRequired(tree, path(call))).path)
                "open" -> {
                    val document = resolveRequired(tree, path(call))
                    val extension = path(call).substringAfterLast('.', "")
                    val mime = MimeTypeMap.getSingleton().getMimeTypeFromExtension(extension)
                        ?: "application/octet-stream"
                    activity.startActivity(
                        Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(document, mime)
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        },
                    )
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: Throwable) {
            result.error("saf_error", error.message ?: error.javaClass.simpleName, null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != PICK_TREE) return false
        val result = pendingPick ?: return true
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data?.data == null) {
            result.success(null)
            return true
        }
        val uri = data.data!!
        try {
            val flags = data.flags and
                (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            resolver.takePersistableUriPermission(uri, flags)
            validate(uri)
            result.success(mapOf("uri" to uri.toString(), "name" to displayName(root(uri))))
        } catch (error: Throwable) {
            runCatching { resolver.releasePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION) }
            result.error("invalid_folder", "This folder cannot provide safe persistent writes: ${error.message}", null)
        }
        return true
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

    private fun resolve(tree: Uri, path: String): Uri? {
        var current = root(tree)
        if (path.isEmpty()) return current
        for (part in safePath(path).split('/')) {
            current = child(tree, current, part) ?: return null
        }
        return current
    }

    private fun ensureDirectory(tree: Uri, path: String): Uri {
        var current = root(tree)
        if (path.isEmpty()) return current
        for (part in safePath(path).split('/')) {
            val existing = child(tree, current, part)
            current = if (existing == null) {
                DocumentsContract.createDocument(resolver, current, DIRECTORY_MIME, part)
                    ?: error("Could not create folder $part")
            } else {
                require(isDirectory(existing)) { "$part is not a folder" }
                existing
            }
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
        val parent = resolveRequired(tree, path)
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
        val target = child(tree, parent, name)
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
                require(DocumentsContract.renameDocument(resolver, temporary, name) != null) {
                    "Storage provider cannot rename documents safely"
                }
                return
            }
            val backupName = ".$name.tylog-${System.nanoTime()}.backup"
            val backup = DocumentsContract.renameDocument(resolver, target, backupName)
                ?: error("Storage provider cannot replace documents safely")
            try {
                require(DocumentsContract.renameDocument(resolver, temporary, name) != null) {
                    "Storage provider could not commit document"
                }
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

    private fun validate(tree: Uri) {
        val name = ".tylog-access-${System.nanoTime()}.tmp"
        writeAtomic(tree, name, "first".toByteArray())
        writeAtomic(tree, name, "replacement".toByteArray())
        val document = resolveRequired(tree, name)
        require(String(read(document)) == "replacement") { "Storage provider cannot replace documents safely" }
        require(DocumentsContract.deleteDocument(resolver, document)) { "Storage provider cannot delete documents" }
    }
}
