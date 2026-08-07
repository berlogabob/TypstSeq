package org.tylog.tylog

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import java.io.File
import java.io.FileNotFoundException

/**
 * A file-backed DocumentsProvider that de-duplicates on rename, the way AOSP's
 * FileSystemProvider does.
 *
 * This is the entire point of the fixture. `DocumentsContract.renameDocument`
 * does not fail when the target name is taken — `buildUniqueFile` splits
 * `vault.lock` into `vault` + `lock` and inserts ` (1)`. On a real device that
 * produced `.tylog/vault (1).lock`: a lock nothing could find again, because
 * lookups match display names exactly.
 *
 * The Dart suite cannot reproduce this at all. Its "SAF" fake is an empty
 * subclass of LocalVaultStorage, so it inherits POSIX `rename(2)`, which
 * overwrites silently. That is precisely the assumption that broke.
 */
class DedupingDocumentsProvider : DocumentsProvider() {
    companion object {
        const val AUTHORITY = "org.tylog.tylog.test.documents"
        const val ROOT_ID = "root"

        /** Set by the test; every document id is a path relative to this. */
        @Volatile
        var rootDirectory: File? = null

        /** Counts renames that were de-duplicated, so a test can assert on it. */
        @Volatile
        var deduplications = 0
    }

    private val root: File
        get() = rootDirectory ?: error("rootDirectory not set by the test")

    private fun fileFor(documentId: String): File =
        if (documentId == ROOT_ID) root else File(root, documentId)

    private fun idFor(file: File): String =
        if (file == root) ROOT_ID else file.relativeTo(root).path

    override fun onCreate(): Boolean = true

    /**
     * Required for tree URIs: the framework asks the provider to confirm the
     * parent/child relationship before honouring a `buildDocumentUriUsingTree`,
     * and the default implementation refuses everything.
     */
    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean =
        parentDocumentId == ROOT_ID || documentId.startsWith("$parentDocumentId/")

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID)).apply {
            newRow().add(Root.COLUMN_ROOT_ID, ROOT_ID)
                .add(Root.COLUMN_DOCUMENT_ID, ROOT_ID)
        }

    private fun MatrixCursor.addFile(file: File) {
        newRow()
            .add(Document.COLUMN_DOCUMENT_ID, idFor(file))
            .add(Document.COLUMN_DISPLAY_NAME, file.name)
            .add(
                Document.COLUMN_MIME_TYPE,
                if (file.isDirectory) Document.MIME_TYPE_DIR else "application/octet-stream",
            )
            .add(Document.COLUMN_SIZE, file.length())
            .add(Document.COLUMN_LAST_MODIFIED, file.lastModified())
            .add(
                Document.COLUMN_FLAGS,
                Document.FLAG_SUPPORTS_WRITE or
                    Document.FLAG_SUPPORTS_DELETE or
                    Document.FLAG_SUPPORTS_RENAME or
                    if (file.isDirectory) Document.FLAG_DIR_SUPPORTS_CREATE else 0,
            )
    }

    private fun columns() = arrayOf(
        Document.COLUMN_DOCUMENT_ID,
        Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_MIME_TYPE,
        Document.COLUMN_SIZE,
        Document.COLUMN_LAST_MODIFIED,
        Document.COLUMN_FLAGS,
    )

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val file = fileFor(documentId)
        if (!file.exists()) throw FileNotFoundException(documentId)
        return MatrixCursor(columns()).apply { addFile(file) }
    }

    override fun queryChildDocuments(
        parentDocumentId: String,
        projection: Array<out String>?,
        sortOrder: String?,
    ): Cursor = MatrixCursor(columns()).apply {
        fileFor(parentDocumentId).listFiles()?.sortedBy { it.name }?.forEach { addFile(it) }
    }

    override fun openDocument(
        documentId: String,
        mode: String,
        signal: CancellationSignal?,
    ): ParcelFileDescriptor = ParcelFileDescriptor.open(
        fileFor(documentId),
        ParcelFileDescriptor.parseMode(mode),
    )

    override fun createDocument(
        parentDocumentId: String,
        mimeType: String,
        displayName: String,
    ): String {
        val parent = fileFor(parentDocumentId)
        // AOSP de-duplicates here too, which is why SafBridge only ever creates
        // temp files and directories through this call, never a real name.
        val target = unique(parent, displayName)
        if (mimeType == Document.MIME_TYPE_DIR) target.mkdirs() else target.createNewFile()
        return idFor(target)
    }

    override fun renameDocument(documentId: String, displayName: String): String? {
        val file = fileFor(documentId)
        val target = unique(file.parentFile!!, displayName)
        if (target.name != displayName) deduplications++
        check(file.renameTo(target)) { "rename failed" }
        return idFor(target)
    }

    override fun deleteDocument(documentId: String) {
        fileFor(documentId).deleteRecursively()
    }

    /** AOSP `buildUniqueFile`: `name.ext` -> `name (1).ext` -> `name (2).ext`. */
    private fun unique(parent: File, displayName: String): File {
        var candidate = File(parent, displayName)
        if (!candidate.exists()) return candidate
        val dot = displayName.lastIndexOf('.')
        val stem = if (dot > 0) displayName.substring(0, dot) else displayName
        val extension = if (dot > 0) displayName.substring(dot) else ""
        var n = 1
        while (candidate.exists()) {
            candidate = File(parent, "$stem ($n)$extension")
            n++
        }
        return candidate
    }
}
