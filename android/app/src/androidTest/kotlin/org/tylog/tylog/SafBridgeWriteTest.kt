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
    private fun SafBridge.write(path: String, content: String) {
        val done = java.util.concurrent.CountDownLatch(1)
        val error = arrayOfNulls<String>(1)
        onMethodCall(
            MethodCall(
                "write",
                mapOf(
                    "uri" to tree.toString(),
                    "path" to path,
                    "bytes" to content.toByteArray(),
                ),
            ),
            object : MethodChannel.Result {
                override fun success(result: Any?) = done.countDown()
                override fun error(code: String, message: String?, details: Any?) {
                    error[0] = "$code: $message"
                    done.countDown()
                }
                override fun notImplemented() = done.countDown()
            },
        )
        check(done.await(30, TimeUnit.SECONDS)) { "write timed out: $path" }
        error[0]?.let { throw IllegalStateException(it) }
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
        // The uri cache is process-wide, and every case reuses the same tree
        // authority over a fresh directory — without this, entries from the
        // previous case resolve to documents that no longer exist.
        SafBridge.clearUriCache()
        tree = DocumentsContract.buildTreeDocumentUri(
            DedupingDocumentsProvider.AUTHORITY,
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
}
