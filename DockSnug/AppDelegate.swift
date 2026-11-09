import AppKit
import ApplicationServices
import SwiftUI

/// Runs in the background with no menu bar icon. Opening the app again shows its settings.
@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let engine = DockSnugEngine()
    private let status = AppStatus()
    private var settingsWindow: NSWindow?
    private var permissionTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            begin()
            return
        }
        showSettings()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.begin()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return false
    }

    private func begin() {
        status.hasPermission = true
        engine.start()
    }

    private func showSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "DockSnug"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(status: status))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
