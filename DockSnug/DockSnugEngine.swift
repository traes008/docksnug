import AppKit
import ApplicationServices

/// Runs a function once, after calls have stopped coming for `delay` seconds.
final class Debouncer {
    private let delay: TimeInterval
    private let action: () -> Void
    private var pending: DispatchWorkItem?

    init(delay: TimeInterval, action: @escaping () -> Void) {
        self.delay = delay
        self.action = action
    }

    func call() {
        pending?.cancel()
        let item = DispatchWorkItem(block: action)
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }
}

final class DockSnugEngine {
    private struct DockReturn {
        let screenID: String
        let deadline: TimeInterval
        var tries = 0
        var nextTry: TimeInterval = 0
    }

    private let settings = Settings()
    private let dockReader = DockReader()
    private let pusher = DockPusher()
    private var windowEvents: WindowEvents?

    private var screenObserver: NSObjectProtocol?
    private var pendingWindows: [AXUIElement] = []

    private var lastUsable: [String: CGRect] = [:]
    private var lastDock: CGRect?
    private var dockSide = DockSide.bottom
    private var dockReturn: DockReturn?
    private var staleSince: TimeInterval?
    private var lastRepair: TimeInterval = -.infinity
    private var edgeSince: TimeInterval?
    private var lastAssist: TimeInterval = -.infinity

    private lazy var windowDebouncer = Debouncer(delay: 0.12) { [weak self] in self?.fitPendingWindows() }
    private lazy var screenDebouncer = Debouncer(delay: 0.20) { [weak self] in self?.refitAllWindows() }
    private lazy var dockDebouncer = Debouncer(delay: settings.pollInterval + 0.1) { [weak self] in self?.refitAllWindows() }

    func start() {
        // A hung app must not be able to stall the whole app for long
        AXUIElementSetMessagingTimeout(AXUIElementCreateSystemWide(), 0.25)

        lastDock = dockReader.bounds()
        lastUsable = usableAreas(screens: Screens.current(), dock: lastDock)

        let events = WindowEvents { [weak self] windows in self?.queue(windows) }
        events.start()
        windowEvents = events

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.screenDebouncer.call() }

        startPolling()
    }

    // MARK: Windows

    private func queue(_ windows: [AXUIElement]) {
        for window in windows where !pendingWindows.contains(where: { CFEqual($0, window) }) {
            pendingWindows.append(window)
        }
        windowDebouncer.call()
    }

    private func fitPendingWindows() {
        let windows = pendingWindows
        pendingWindows = []
        let screens = Screens.current()
        let dock = dockReader.bounds()
        for window in windows where window.isFittableWindow {
            guard let frame = window.frame, let screen = DockGeometry.bestScreen(for: frame, in: screens) else { continue }
            let usable = DockGeometry.usableFrame(of: screen, dock: dock)
            if let fitted = DockGeometry.fitted(frame, usable: usable, full: screen.full, settings: settings) {
                window.setFrame(fitted)
            }
        }
    }

    private func usableAreas(screens: [ScreenInfo], dock: CGRect?) -> [String: CGRect] {
        Dictionary(uniqueKeysWithValues: screens.map { ($0.id, DockGeometry.usableFrame(of: $0, dock: dock)) })
    }

    private func refitAllWindows() {
        let screens = Screens.current()
        let newUsable = usableAreas(screens: screens, dock: dockReader.bounds())
        for window in WindowList.all() where window.isFittableWindow {
            guard let frame = window.frame,
                  let screen = DockGeometry.bestScreen(for: frame, in: screens),
                  let new = newUsable[screen.id] else { continue }
            if let old = lastUsable[screen.id],
               let followed = DockGeometry.followed(frame, old: old, new: new, settings: settings) {
                window.setFrame(followed)
            } else if let fitted = DockGeometry.fitted(frame, usable: new, full: screen.full, settings: settings) {
                window.setFrame(fitted)
            }
        }
        lastUsable = newUsable
    }

    // MARK: Polling

    /// Runs on one screen too: the Dock can misbehave there as well.
    private func startPolling() {
        let timer = Timer(timeInterval: settings.pollInterval, repeats: true) { [weak self] _ in self?.tick() }
        timer.tolerance = settings.pollInterval / 4 // lets macOS group wakeups, which saves battery
        RunLoop.main.add(timer, forMode: .common)
    }

    private func tick() {
        let dock = dockReader.bounds()
        let settled = dock == lastDock
        if !settled {
            lastDock = dock
            dockDebouncer.call()
        }

        let now = ProcessInfo.processInfo.systemUptime
        let screens = Screens.current()
        let here = DockGeometry.screen(withDock: dock, in: screens)
        if let dock, let here { dockSide = DockGeometry.side(ofDock: dock, on: here) }

        returnDockIfNeeded(here: here, settled: settled, screens: screens, now: now)
        assistEdgePush(here: here, screens: screens, now: now)
        repairStaleReservation(dock: dock, here: here, screens: screens, now: now)
    }

    /// A restarted Dock comes back on the main display: once it has settled, push it back to the
    /// monitor it was on (twice at most, so a failed push can't keep grabbing the pointer).
    private func returnDockIfNeeded(here: ScreenInfo?, settled: Bool, screens: [ScreenInfo], now: TimeInterval) {
        guard var back = dockReturn else { return }
        if now > back.deadline || back.tries >= 2 || here?.id == back.screenID {
            dockReturn = nil
            return
        }
        if here != nil && settled && now >= back.nextTry {
            if let target = screens.first(where: { $0.id == back.screenID }) {
                pusher.push(to: target, side: dockSide)
            }
            back.tries += 1
            back.nextTry = now + 1
            dockReturn = back
        }
    }

    /// You push the pointer against a monitor's Dock edge but the Dock doesn't come. macOS sometimes
    /// ignores real pushes while a synthetic one still works. It normally moves the Dock within
    /// ~0.3s, so only step in after edgeAssistDelay, and not while a button is held (dragging).
    private func assistEdgePush(here: ScreenInfo?, screens: [ScreenInfo], now: TimeInterval) {
        guard let point = CGEvent(source: nil)?.location,
              dockReturn == nil,
              NSEvent.pressedMouseButtons == 0,
              let under = DockGeometry.screen(at: point, in: screens),
              here?.id != under.id,
              DockGeometry.isAtDockEdge(point, of: under, side: dockSide) else {
            edgeSince = nil
            return
        }
        guard let since = edgeSince else {
            edgeSince = now
            return
        }
        if now - since >= settings.edgeAssistDelay && now - lastAssist >= settings.edgeAssistCooldown &&
           !Spaces.isFullscreen(displayID: under.id) {
            lastAssist = now
            pusher.push(to: under, side: dockSide)
        }
    }

    private func repairStaleReservation(dock: CGRect?, here: ScreenInfo?, screens: [ScreenInfo], now: TimeInterval) {
        let stale = DockGeometry.staleReservation(dock: dock, screens: screens, settings: settings) {
            Spaces.isFullscreen(displayID: $0.id)
        }
        guard stale != nil else {
            staleSince = nil
            return
        }
        guard let since = staleSince else {
            staleSince = now
            return
        }
        if now - since >= settings.repairDelay && now - lastRepair >= settings.repairCooldown {
            staleSince = nil
            lastRepair = now
            if let here { dockReturn = DockReturn(screenID: here.id, deadline: now + 10) }
            NSLog("DockSnug: macOS still reserves Dock space on the wrong monitor; restarting the Dock")
            _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/killall"), arguments: ["Dock"])
        }
    }
}
