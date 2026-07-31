package org.tylog.tylog

import android.content.Context
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout

/// Closed-app sync: hosts a headless FlutterEngine running `vaultServiceMain`.
///
/// A Worker rather than the foreground service on purpose — Android 12+
/// forbids starting a foreground service from the background, so a periodic
/// FGS start would throw on modern devices. WorkManager is the sanctioned
/// path and needs no notification for runs this short. The Dart side signals
/// completion through SafBridge's `backgroundDone`; the timeout is the
/// backstop for a wedged engine.
class VaultSyncWorker(
    appContext: Context,
    params: WorkerParameters,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result = withContext(Dispatchers.Main) {
        val loader = FlutterInjector.instance().flutterLoader()
        if (!loader.initialized()) loader.startInitialization(applicationContext)
        loader.ensureInitializationComplete(applicationContext, null)

        val done = CompletableDeferred<Unit>()
        val engine = FlutterEngine(applicationContext)
        val bridge = SafBridge(
            applicationContext,
            engine.dartExecutor.binaryMessenger,
            onBackgroundDone = { done.complete(Unit) },
        )
        try {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    loader.findAppBundlePath(),
                    "package:tylog/vault_service.dart",
                    "vaultServiceMain",
                ),
            )
            withTimeout(TIMEOUT_MILLIS) { done.await() }
            Result.success()
        } catch (_: TimeoutCancellationException) {
            Result.retry()
        } catch (_: Throwable) {
            Result.retry()
        } finally {
            bridge.dispose()
            engine.destroy()
        }
    }

    companion object {
        // Below WorkManager's own ~10 minute execution guarantee, so a long
        // first sync retries from its checkpoint instead of being shot.
        private const val TIMEOUT_MILLIS = 9 * 60 * 1000L
    }
}

object BackgroundSync {
    private const val PERIODIC = "vault-sync-periodic"
    private const val SOON = "vault-sync-soon"

    private val network =
        Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build()

    /// Idempotent (KEEP): called on every app start.
    fun schedulePeriodic(context: Context) {
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC,
            ExistingPeriodicWorkPolicy.KEEP,
            PeriodicWorkRequestBuilder<VaultSyncWorker>(15, TimeUnit.MINUTES)
                .setConstraints(network)
                .build(),
        )
    }

    /// One catch-up run shortly after the app is backgrounded; the delay lets
    /// a brief app switch come back without ever spinning an engine up.
    fun runSoon(context: Context) {
        WorkManager.getInstance(context).enqueueUniqueWork(
            SOON,
            ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<VaultSyncWorker>()
                .setInitialDelay(1, TimeUnit.MINUTES)
                .setConstraints(network)
                .build(),
        )
    }

    fun cancelSoon(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(SOON)
    }
}
