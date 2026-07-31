import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var statusItem: NSStatusItem?

  // Closing the window keeps the process alive so the worker isolate and the
  // 25 s sync poll keep running; the status item is the way back in.
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    if #available(macOS 11.0, *) {
      item.button?.image = NSImage(
        systemSymbolName: "text.book.closed", accessibilityDescription: "TyLog")
    } else {
      item.button?.title = "Ty"
    }

    let menu = NSMenu()
    menu.addItem(
      NSMenuItem(title: "Open TyLog", action: #selector(openMainWindow), keyEquivalent: "o"))
    menu.addItem(NSMenuItem.separator())
    menu.addItem(
      NSMenuItem(title: "Quit TyLog", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    item.menu = menu
    statusItem = item
    super.applicationDidFinishLaunching(notification)
  }

  // Reopen via the Dock icon too, matching the status item.
  override func applicationShouldHandleReopen(
    _ sender: NSApplication, hasVisibleWindows flag: Bool
  ) -> Bool {
    if !flag { openMainWindow() }
    return true
  }

  @objc private func openMainWindow() {
    NSApp.activate(ignoringOtherApps: true)
    for window in NSApp.windows where window is MainFlutterWindow {
      window.makeKeyAndOrderFront(nil)
      return
    }
    NSApp.windows.first?.makeKeyAndOrderFront(nil)
  }
}
