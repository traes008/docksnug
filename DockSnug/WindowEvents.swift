import AppKit
import ApplicationServices

/// Reports windows that moved, resized or came back on screen.
final class WindowEvents {
    private static let notifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowCreatedNotification,
        kAXWindowDeminiaturizedNotification,
        kAXApplicationShownNotification,
    ]

    private let onWindows: ([AXUIElement]) -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []

    init(onWindows: @escaping ([AXUIElement]) -> Void) {
        self.onWindows = onWindows
    }

    func start() {
        NSWorkspace.shared.runningApplications.forEach(watch)

        let center = NSWorkspace.shared.notificationCenter
        workspaceTokens = [
            center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                // A freshly launched app isn't ready for Accessibility yet
                for delay in [0.5, 2.0, 5.0] {
                    DispatchQueue.main.asyncAfter(deadline: .now() + delay) { self?.watch(app) }
                }
            },
            center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
                guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.unwatch(app.processIdentifier)
            },
            // Windows on other Spaces can't be reached when the Dock moves, so catch them as they appear
            center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
                self?.onWindows(WindowList.all())
            },
        ]
    }

    private func watch(_ app: NSRunningApplication) {
        let pid = app.processIdentifier
        guard app.activationPolicy == .regular, observers[pid] == nil else { return }

        var created: AXObserver?
        guard AXObserverCreate(pid, Self.callback, &created) == .success, let observer = created else { return }

        let element = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        var added = false
        for notification in Self.notifications {
            added = AXObserverAddNotification(observer, element, notification as CFString, refcon) == .success || added
        }
        guard added else { return } // not ready yet; the launch retries will try again

        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
        observers[pid] = observer
    }

    private func unwatch(_ pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .defaultMode)
    }

    private static let callback: AXObserverCallback = { _, element, notification, refcon in
        guard let refcon else { return }
        let events = Unmanaged<WindowEvents>.fromOpaque(refcon).takeUnretainedValue()
        // "Shown" is about the whole app, the others about one window
        let isApp = (notification as String) == kAXApplicationShownNotification
        events.onWindows(isApp ? element.windows : [element])
    }
}
