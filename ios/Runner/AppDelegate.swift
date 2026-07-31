import BackgroundTasks
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  static let vaultSyncTaskId = "org.tylog.tylog.vault-sync"
  private var backgroundEngine: FlutterEngine?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: Self.vaultSyncTaskId, using: nil
    ) { task in
      self.runVaultSync(task as! BGProcessingTask)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationDidEnterBackground(_ application: UIApplication) {
    scheduleVaultSync()
    super.applicationDidEnterBackground(application)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  private func scheduleVaultSync() {
    let request = BGProcessingTaskRequest(identifier: Self.vaultSyncTaskId)
    request.requiresNetworkConnectivity = true
    // Submitting again while one is pending just replaces it.
    try? BGTaskScheduler.shared.submit(request)
  }

  // Opportunistic catch-up, not a service: iOS runs this when it chooses
  // (typically charging + idle) and can expire it mid-run. The Dart side is a
  // single conservative pass (vaultServiceMain, shared with Android) whose
  // sync checkpoints make an expiration lose minutes of progress, not data.
  private func runVaultSync(_ task: BGProcessingTask) {
    scheduleVaultSync()  // keep a next run queued
    guard backgroundEngine == nil else {
      task.setTaskCompleted(success: false)
      return
    }
    let engine = FlutterEngine(name: "tylog-vault-sync", project: nil, allowHeadlessExecution: true)
    guard
      engine.run(
        withEntrypoint: "vaultServiceMain",
        libraryURI: "package:tylog/vault_service.dart"
      )
    else {
      task.setTaskCompleted(success: false)
      return
    }
    GeneratedPluginRegistrant.register(with: engine)
    backgroundEngine = engine

    var finished = false
    // expirationHandler arrives on a background queue; the engine must die on
    // the main thread, which also serializes the two finish paths.
    let finish: (Bool) -> Void = { success in
      DispatchQueue.main.async {
        guard !finished else { return }
        finished = true
        engine.destroyContext()
        self.backgroundEngine = nil
        task.setTaskCompleted(success: success)
      }
    }
    // Same completion signal the Android worker listens for, on the same
    // channel name the Dart entrypoint already invokes.
    let channel = FlutterMethodChannel(
      name: "org.tylog.tylog/saf", binaryMessenger: engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "backgroundDone" {
        result(nil)
        finish(true)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    task.expirationHandler = { finish(false) }
  }
}
