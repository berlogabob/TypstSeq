package org.tylog.tylog

import android.net.Uri
import android.provider.DocumentsContract
import androidx.test.InstrumentationRegistry
import androidx.test.runner.AndroidJUnit4
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.nio.ByteBuffer
import java.util.concurrent.CyclicBarrier
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Covers `SafBridge.writeAtomic` against a provider that de-duplicates on
 * rename, which is what AOSP's FileSystemProvider does and what no Dart test
 * can reproduce.
 *
 * The defect these pin: two Flutter engines share this process (the UI one and
 * the WorkManager one), the lock and uri cache used to be per-instance, and
 * `.tylog/vault.lock` is the one path both write by design. Both resolved it to
 * absent, both renamed a temp file onto it, and the loser silently became
 * `vault (1).lock` — invisible to every later lookup, so the lock arbitrated
 * nothing for the length of a sync.
 *
 * The worse case is the replace branch: a de-duplicated commit there leaves the
 * original already renamed aside and then deleted, so a real note's only good
 * copy goes while the new content sits under a name nothing looks up.
 */
@RunWith(AndroidJUnit4::class)
class SafBridgeWriteTest {
    private lateinit var root: File
    private lateinit var tree: Uri
    private val bridges = mutableListOf<SafBridge>()

    /** The channel is never used here; writeAtomic is called directly. */
    private class SilentMessenger : BinaryMessenger {
        override fun send(channel: String, message: ByteBuffer?) {}
        override fun send(
            channel: String,
            message: ByteBuffer?,
            callback: BinaryMessenger.BinaryReply?,
        ) { callback?.reply(null) }
        override fun setMessageHandler(
            channel: String,
            handler: BinaryMessenger.BinaryMessageHandler?,
        ) {}
    }

    private fun newBridge(): SafBridge {
        val context = InstrumentationRegistry.getTargetContext()
        return SafBridge(context, SilentMessenger()).also { bridges.add(it) }
    }

    /**
     * Writes through the real `write` channel call, which is the only path
     * production uses — and the one that takes `storageLock`. Calling
     * `writeAtomic` directly would bypass the lock and test something that
     * never happens.
     */
    private fun SafBridge.call(method: String, path: String = "", values: Map<String, Any?> = emptyMap()): Any? {
        val done = java.util.concurrent.CountDownLatch(1)
        var value: Any? = null
        var failure: String? = null
        onMethodCall(
            MethodCall(method, mapOf("uri" to tree.toString(), "path" to path) + values),
            object : MethodChannel.Result {
                override fun success(result: Any?) {
                    value = result
                    done.countDown()
                }
                override fun error(code: String, message: String?, details: Any?) {
                    failure = "$code: $message"
                    done.countDown()
                }
                override fun notImplemented() {
                    failure = "Not implemented: $method"
                    done.countDown()
                }
            },
        )
        check(done.await(30, TimeUnit.SECONDS)) { "$method timed out: $path" }
        failure?.let { throw IllegalStateException(it) }
        return value
    }

    @Test
    fun syncLeaseSerializesEnginesAndReleasesOnDispose() {
        val first = newBridge()
        val second = newBridge()
        val executor = Executors.newSingleThreadExecutor()
        try {
            first.call("acquireSync")
            val waiting = executor.submit { second.call("acquireSync") }
            Thread.sleep(100)
            assertTrue("second engine entered an active sync", !waiting.isDone)
            first.dispose()
            waiting.get(5, TimeUnit.SECONDS)
            second.call("releaseSync")
            first.call("releaseSync") // An old owner cannot release its successor.
            val third = newBridge()
            third.call("acquireSync")
            third.call("releaseSync")
        } finally {
            executor.shutdownNow()
        }
    }

    private fun SafBridge.write(path: String, content: String) {
        call("write", path, mapOf("bytes" to content.toByteArray()))
    }

    @Suppress("UNCHECKED_CAST")
    private fun SafBridge.listing(): List<Map<String, Any?>> =
        call("list", values = mapOf("recursive" to true)) as List<Map<String, Any?>>

    private fun SafBridge.assertPatchedMatchesFull() {
        val patched = listing()
        SafBridge.clearUriCache()
        val full = listing()
        assertEquals(full.toSet(), patched.toSet())
        // Dart preserves native order, so also pin provider-order depth first.
        assertEquals(full, patched)
    }

    @Suppress("UNCHECKED_CAST")
    private fun listingCache(): MutableMap<String, SafBridge.Companion.CachedListing> =
        SafBridge::class.java.getDeclaredField("listingCache").apply { isAccessible = true }
            .get(null) as MutableMap<String, SafBridge.Companion.CachedListing>

    private fun ageVerification() {
        val cache = listingCache()
        cache[tree.toString()] = cache.getValue(tree.toString()).copy(verifiedAt = -60_000L)
    }

    private fun listingFixture(): SafBridge {
        File(root, "notes/sub").mkdirs()
        File(root, "notes/a.typ").writeText("old")
        File(root, "notes/a.typ").setLastModified(1_000L)
        File(root, "notes/sub/child.typ").writeText("child")
        File(root, "other").mkdirs()
        File(root, "other/z.typ").writeText("untouched")
        // A fixed old baseline avoids same-tick directory mtimes on fast tests.
        listOf("", "notes", "notes/sub", "other").forEach {
            assertTrue(File(root, it).setLastModified(1_000L))
        }
        return newBridge().also { it.listing() }
    }

    private fun childNames(relative: String): List<String> =
        File(root, relative).listFiles()?.map { it.name }?.sorted() ?: emptyList()

    @Before
    fun setUp() {
        root = File.createTempFile("safroot", "").let {
            it.delete(); it.mkdirs(); it
        }
        DedupingDocumentsProvider.rootDirectory = root
        DedupingDocumentsProvider.deduplications = 0
        DedupingDocumentsProvider.childQueries.clear()
        DedupingDocumentsProvider.failNextChildQuery = false
        // The uri cache is process-wide, and every case reuses the same tree
        // authority over a fresh directory — without this, entries from the
        // previous case resolve to documents that no longer exist.
        SafBridge.clearUriCache()
        tree = DocumentsContract.buildTreeDocumentUri(
            DedupingDocumentsProvider.authority(
                InstrumentationRegistry.getTargetContext().packageName,
            ),
            DedupingDocumentsProvider.ROOT_ID,
        )
    }

    @After
    fun tearDown() {
        bridges.forEach { it.dispose() }
        bridges.clear()
        DedupingDocumentsProvider.rootDirectory = null
        root.deleteRecursively()
    }

    /** The fixture must actually de-duplicate, or every assertion is vacuous. */
    @Test
    fun providerDeduplicatesLikeAosp() {
        File(root, "notes").mkdirs()
        File(root, "notes/a.typ").writeText("first")
        val parent = DocumentsContract.buildDocumentUriUsingTree(
            tree,
            "notes",
        )
        val context = InstrumentationRegistry.getTargetContext()
        val temp = DocumentsContract.createDocument(
            context.contentResolver, parent, "application/octet-stream", "tmp.bin",
        )!!
        DocumentsContract.renameDocument(context.contentResolver, temp, "a.typ")

        assertTrue("a (1).typ" in childNames("notes"))
        assertEquals(1, DedupingDocumentsProvider.deduplications)
    }

    /** Replacing an existing note must leave exactly one file, with new bytes. */
    @Test
    fun replacingANoteLeavesOneFileAndKeepsItsName() {
        File(root, "notes").mkdirs()
        File(root, "notes/a.typ").writeText("old")

        newBridge().write("notes/a.typ", "new")

        assertEquals(listOf("a.typ"), childNames("notes"))
        assertEquals("new", File(root, "notes/a.typ").readText())
    }

    /** Repeated writes must not accumulate `a (1).typ`, `a (2).typ`, … */
    @Test
    fun repeatedWritesDoNotAccumulateDuplicates() {
        File(root, "notes").mkdirs()
        val bridge = newBridge()
        repeat(5) { i ->
            try {
                bridge.write("notes/a.typ", "v$i")
            } catch (error: Throwable) {
                throw AssertionError(
                    "write $i failed: ${error.message}; dir=${childNames("notes")}",
                )
            }
        }

        assertEquals(listOf("a.typ"), childNames("notes"))
        assertEquals("v4", File(root, "notes/a.typ").readText())
    }

    /**
     * The regression test for the observed defect: two SafBridge instances,
     * exactly as MainActivity and VaultSyncWorker create them, writing the vault
     * lock at the same moment. Before the process-wide lock this produced a
     * second file named `vault (1).lock`.
     */
    @Test
    fun twoEnginesWritingTheLockLeaveOneFile() {
        File(root, ".tylog").mkdirs()
        val ui = newBridge()
        val worker = newBridge()
        val barrier = CyclicBarrier(2)
        val pool = Executors.newFixedThreadPool(2)
        val failures = mutableListOf<Throwable>()

        listOf(ui to "ui", worker to "service").forEach { (bridge, owner) ->
            pool.execute {
                try {
                    barrier.await(10, TimeUnit.SECONDS)
                    bridge.write(".tylog/vault.lock", """{"owner":"$owner"}""")
                } catch (error: Throwable) {
                    synchronized(failures) { failures.add(error) }
                }
            }
        }
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))

        synchronized(failures) {
            assertTrue("writes failed: $failures", failures.isEmpty())
        }
        assertEquals(
            "a de-duplicated lock is invisible to every later lookup",
            listOf("vault.lock"),
            childNames(".tylog"),
        )
    }

    /** Concurrent writes to one note must never fork it either. */
    @Test
    fun twoEnginesWritingOneNoteLeaveOneFile() {
        File(root, "notes").mkdirs()
        File(root, "notes/a.typ").writeText("original")
        val a = newBridge()
        val b = newBridge()
        val barrier = CyclicBarrier(2)
        val pool = Executors.newFixedThreadPool(2)

        listOf(a to "A", b to "B").forEach { (bridge, tag) ->
            pool.execute {
                barrier.await(10, TimeUnit.SECONDS)
                runCatching { bridge.write("notes/a.typ", "from $tag") }
            }
        }
        pool.shutdown()
        assertTrue(pool.awaitTermination(30, TimeUnit.SECONDS))

        assertEquals(listOf("a.typ"), childNames("notes"))
        val text = File(root, "notes/a.typ").readText()
        assertTrue("one writer must win cleanly, got: $text", text.startsWith("from "))
    }
    @Test
    fun listingPatchesFileCreationInExistingDirectory() {
        val bridge = listingFixture()
        bridge.write("notes/b.typ", "new")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesFileCreationInNewNestedDirectories() {
        val bridge = listingFixture()
        bridge.write("new/deep/nested/b.typ", "new")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesOverwriteSizeAndModifiedTime() {
        val bridge = listingFixture()
        bridge.write("notes/a.typ", "a much longer replacement")
        val entry = bridge.listing().single { it["path"] == "notes/a.typ" }
        assertEquals(25L, entry["size"])
        assertTrue(entry["modified"] != 1_000L)
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesFileDeletion() {
        val bridge = listingFixture()
        bridge.call("delete", "notes/a.typ")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesDirectoryDeletionWithChildren() {
        val bridge = listingFixture()
        bridge.call("delete", "notes/sub")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesRenameAcrossDirectories() {
        val bridge = listingFixture()
        // VaultStorage has no native move operation: moves write the target
        // then delete the source, through the same two channel calls.
        bridge.write("other/moved.typ", File(root, "notes/a.typ").readText())
        bridge.call("delete", "notes/a.typ")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun listingPatchesDirectoryCreationAndRecreation() {
        val bridge = listingFixture()
        bridge.call("createDirectory", "new/deep")
        bridge.call("delete", "notes/sub")
        bridge.call("createDirectory", "notes/sub")
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun singleWriteQueriesOnlyItsDirectoryAndKeepsTimestamp() {
        val bridge = listingFixture()
        val cache = listingCache()
        val before = cache.getValue(tree.toString())
        bridge.write("notes/a.typ", "new")
        DedupingDocumentsProvider.childQueries.clear()
        bridge.listing()
        assertEquals(listOf("notes"), DedupingDocumentsProvider.childQueries.toList())
        assertEquals(before.walkedAt, cache.getValue(tree.toString()).walkedAt)
        assertEquals(before.verifiedAt, cache.getValue(tree.toString()).verifiedAt)
        bridge.listing()
        assertEquals(listOf("notes"), DedupingDocumentsProvider.childQueries.toList())
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun concurrentListsPatchOnceAcrossEnginesAndRetainLaterWrite() {
        val a = listingFixture()
        val b = newBridge()
        a.write("notes/a.typ", "first")
        DedupingDocumentsProvider.childQueries.clear()
        val barrier = CyclicBarrier(2)
        val pool = Executors.newFixedThreadPool(2)
        try {
            val lists = listOf(a, b).map { bridge ->
                pool.submit<List<Map<String, Any?>>> {
                    barrier.await(10, TimeUnit.SECONDS)
                    bridge.listing()
                }
            }
            assertEquals(lists[0].get(30, TimeUnit.SECONDS), lists[1].get(30, TimeUnit.SECONDS))
            assertEquals(listOf("notes"), DedupingDocumentsProvider.childQueries.toList())
            b.write("notes/a.typ", "second, longer")
            a.assertPatchedMatchesFull()
        } finally {
            pool.shutdownNow()
        }
    }

    @Test
    fun patchFailureFallsBackToFullWalk() {
        val bridge = listingFixture()
        bridge.write("notes/a.typ", "new")
        DedupingDocumentsProvider.childQueries.clear()
        DedupingDocumentsProvider.failNextChildQuery = true
        bridge.listing()
        assertTrue(DedupingDocumentsProvider.ROOT_ID in DedupingDocumentsProvider.childQueries)
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun missingDirtyDirectoryWalksUpToRoot() {
        val bridge = listingFixture()
        bridge.write("notes/sub/child.typ", "new")
        File(root, "notes").deleteRecursively()
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun moreThan64DirtyDirectoriesForcesFullWalk() {
        val bridge = listingFixture()
        repeat(65) { File(root, "dir$it").mkdirs() }
        SafBridge.clearUriCache()
        bridge.listing()
        repeat(65) { bridge.write("dir$it/a.typ", "new") }
        DedupingDocumentsProvider.childQueries.clear()
        bridge.listing()
        assertEquals(DedupingDocumentsProvider.ROOT_ID, DedupingDocumentsProvider.childQueries.first())
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationSeesExternalFileCreationInLeaf() {
        val bridge = listingFixture()
        File(root, "notes/sub/external.typ").writeText("external")
        ageVerification()
        assertTrue(bridge.listing().any { it["path"] == "notes/sub/external.typ" })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationSeesExternalFileDeletion() {
        val bridge = listingFixture()
        assertTrue(File(root, "notes/sub/child.typ").delete())
        ageVerification()
        assertTrue(bridge.listing().none { it["path"] == "notes/sub/child.typ" })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationSeesExternalNestedDirectoryCreation() {
        val bridge = listingFixture()
        File(root, "other/new/deep").mkdirs()
        File(root, "other/new/deep/external.typ").writeText("external")
        ageVerification()
        assertTrue(bridge.listing().any { it["path"] == "other/new/deep/external.typ" })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationSeesExternalDirectoryDeletionWithChildren() {
        val bridge = listingFixture()
        assertTrue(File(root, "notes/sub").deleteRecursively())
        ageVerification()
        assertTrue(bridge.listing().none { (it["path"] as String).startsWith("notes/sub") })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun unchangedVerificationQueriesOnlyParentsOfDirectories() {
        val bridge = listingFixture()
        val walkedAt = listingCache().getValue(tree.toString()).walkedAt
        ageVerification()
        DedupingDocumentsProvider.childQueries.clear()
        bridge.listing()
        assertEquals(listOf(DedupingDocumentsProvider.ROOT_ID, "notes"),
            DedupingDocumentsProvider.childQueries.toList())
        assertEquals(walkedAt, listingCache().getValue(tree.toString()).walkedAt)
        assertTrue(listingCache().getValue(tree.toString()).verifiedAt >= 0L)
        bridge.listing()
        assertEquals(2, DedupingDocumentsProvider.childQueries.size)
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun expiredFullWalkSeesExternalInPlaceRewrite() {
        val bridge = listingFixture()
        File(root, "other/z.typ").writeText("external replacement")
        val cache = listingCache()
        cache[tree.toString()] = cache.getValue(tree.toString()).copy(walkedAt = -1_800_000L)
        DedupingDocumentsProvider.childQueries.clear()
        bridge.listing()
        assertEquals(listOf(DedupingDocumentsProvider.ROOT_ID, "notes", "notes/sub", "other"),
            DedupingDocumentsProvider.childQueries.toList())
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationFailureFallsBackToFullWalk() {
        val bridge = listingFixture()
        File(root, "notes/sub/external.typ").writeText("external")
        ageVerification()
        DedupingDocumentsProvider.childQueries.clear()
        DedupingDocumentsProvider.failNextChildQuery = true
        bridge.listing()
        assertEquals(2, DedupingDocumentsProvider.childQueries.count { it == DedupingDocumentsProvider.ROOT_ID })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun verificationOfMoreThan64DirtyDirectoriesFallsBackToFullWalk() {
        val bridge = listingFixture()
        repeat(65) {
            File(root, "dir$it").mkdirs()
            assertTrue(File(root, "dir$it").setLastModified(1_000L))
        }
        SafBridge.clearUriCache()
        bridge.listing()
        repeat(65) { File(root, "dir$it/external.typ").writeText("external") }
        ageVerification()
        DedupingDocumentsProvider.childQueries.clear()
        bridge.listing()
        assertEquals(2, DedupingDocumentsProvider.childQueries.count { it == DedupingDocumentsProvider.ROOT_ID })
        bridge.assertPatchedMatchesFull()
    }

    @Test
    fun bookkeepingWritesRemainExempt() {
        val bridge = listingFixture()
        val cached = bridge.listing()
        bridge.write(".tylog/state.json", "state")
        bridge.write("_index/index.json", "index")
        DedupingDocumentsProvider.childQueries.clear()
        assertEquals(cached, bridge.listing())
        assertTrue(DedupingDocumentsProvider.childQueries.isEmpty())
    }

}
