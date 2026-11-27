import AppKit
import ApplicationServices

/// Keeps windows that share a border together while you drag that border.
///
/// It costs nothing until a window is resized with the mouse held down and another window sits
/// against it: window frames are remembered from work the app does anyway, so the check for a
/// neighbour is a look in memory.
final class WindowLinker {
    static let settingKey = "linkBorders"

    private struct Key: Hashable {
        let window: AXUIElement
        static func == (a: Key, b: Key) -> Bool { CFEqual(a.window, b.window) }
        func hash(into hasher: inout Hasher) { hasher.combine(CFHash(window)) }
    }

    private struct Follower {
        let window: AXUIElement
        let edge: WindowEdge
        let start: CGRect
        var current: CGRect
    }

    private struct Drag {
        let window: AXUIElement
        let start: CGRect
        var followers: [Follower]
        var last: TimeInterval
    }

    private var frames: [Key: CGRect] = [:]
    private var drag: Drag?
    private var lastApplied: TimeInterval = -.infinity
    private var trailing: DispatchWorkItem?

    /// A drag is over when no resize has come for this long.
    private let dragTimeout: TimeInterval = 0.5
    /// At most this often is the neighbour moved; faster only burns CPU in both apps.
    private let minInterval: TimeInterval = 1.0 / 90

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true
    }

    // MARK: Remembered frames

    func remember(_ window: AXUIElement, frame: CGRect) {
        if frames.count > 300 { frames.removeAll() } // closed windows pile up; start over now and then
        frames[Key(window: window)] = frame
    }

    func forget(_ window: AXUIElement) {
        frames[Key(window: window)] = nil
    }

    // MARK: Dragging

    /// Called for every resize notification of any window.
    func resized(_ window: AXUIElement) {
        let now = ProcessInfo.processInfo.systemUptime
        if let current = drag, now - current.last < dragTimeout {
            if CFEqual(current.window, window) {
                drag?.last = now
                applyThrottled(now: now)
                return
            }
            // A follower resizing is our own doing
            if current.followers.contains(where: { CFEqual($0.window, window) }) { return }
        }
        drag = nil
        begin(window, now: now)
    }

    private func begin(_ window: AXUIElement, now: TimeInterval) {
        let key = Key(window: window)
        guard isEnabled, Self.isMouseDown(), let old = frames[key] else { return }
        let candidates = frames.filter { $0.key != key && LinkedBorder.hasNeighbour(old, among: [$0.value]) }
        guard !candidates.isEmpty, let new = window.frame else { return }
        let edges = LinkedBorder.draggedEdges(old: old, new: new)
        guard !edges.isEmpty else { return }

        var followers: [Follower] = []
        var onScreen: [OnScreenWindow]?
        for (candidate, remembered) in candidates {
            guard let edge = edges.first(where: { LinkedBorder.isNeighbour(remembered, of: old, edge: $0) }) else { continue }
            // The remembered frame must still be true, and the window must be what you see at the border
            guard let actual = candidate.window.frame else {
                frames[candidate] = nil
                continue
            }
            guard abs(actual.minX - remembered.minX) <= 1, abs(actual.minY - remembered.minY) <= 1,
                  abs(actual.width - remembered.width) <= 1, abs(actual.height - remembered.height) <= 1 else {
                frames[candidate] = actual
                continue
            }
            // The dragged window itself may already cover the border, so it is left out
            if onScreen == nil { onScreen = OnScreenWindow.all(except: window) }
            let point = LinkedBorder.probe(neighbour: actual, of: old, edge: edge)
            guard OnScreenWindow.isFrontmost(candidate.window, at: point, in: onScreen ?? []) else { continue }
            followers.append(Follower(window: candidate.window, edge: edge, start: actual, current: actual))
        }
        guard !followers.isEmpty else { return }

        drag = Drag(window: window, start: old, followers: followers, last: now)
        apply(frame: new, now: now)
    }

    /// Only a drag with the mouse links windows; an app resizing its own window doesn't.
    private static func isMouseDown() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DOCKSNUG_LINK_ANY_RESIZE"] != nil { return true }
        #endif
        return CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    private func applyThrottled(now: TimeInterval) {
        if now - lastApplied >= minInterval {
            trailing?.cancel()
            trailing = nil
            if let frame = drag?.window.frame { apply(frame: frame, now: now) }
        } else if trailing == nil {
            // Make sure the last position of a drag is always applied
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.trailing = nil
                if let frame = self.drag?.window.frame { self.apply(frame: frame, now: ProcessInfo.processInfo.systemUptime) }
            }
            trailing = item
            DispatchQueue.main.asyncAfter(deadline: .now() + minInterval, execute: item)
        }
    }

    private func apply(frame: CGRect, now: TimeInterval) {
        guard var current = drag else { return }
        lastApplied = now
        frames[Key(window: current.window)] = frame
        for index in current.followers.indices {
            let follower = current.followers[index]
            let delta = LinkedBorder.movement(of: follower.edge, old: current.start, new: frame)
            var target = LinkedBorder.adjusted(follower.start, edge: follower.edge, by: delta)
            guard target != follower.current, target.width > 1, target.height > 1 else { continue }

            if !LinkedBorder.movesOrigin(follower.edge) {
                follower.window.setSize(target.size)
            } else if target.width >= follower.current.width && target.height >= follower.current.height {
                follower.window.setPosition(target.origin)
                follower.window.setSize(target.size)
            } else {
                // Shrinking: a window that refuses to get smaller must keep its far edge in place
                follower.window.setSize(target.size)
                if let actual = follower.window.size, actual != target.size {
                    target.origin.x = follower.start.maxX - actual.width
                    target.origin.y = follower.start.maxY - actual.height
                    target.size = actual
                }
                follower.window.setPosition(target.origin)
            }
            current.followers[index].current = target
            frames[Key(window: follower.window)] = target
        }
        drag = current
    }
}

/// Windows as the window server stacks them, front to back.
private struct OnScreenWindow {
    let id: CGWindowID
    let bounds: CGRect

    static func all(except dragged: AXUIElement) -> [OnScreenWindow] {
        let skip = windowID(of: dragged)
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[CFString: Any]] else { return [] }
        return list.compactMap { info in
            guard info[kCGWindowLayer] as? Int == 0,
                  let id = info[kCGWindowNumber] as? CGWindowID, id != skip,
                  let dictionary = info[kCGWindowBounds] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            return OnScreenWindow(id: id, bounds: bounds)
        }
    }

    /// Is `window` the one you see at `point`? A window hidden behind another, or on another Space, isn't.
    static func isFrontmost(_ window: AXUIElement, at point: CGPoint, in windows: [OnScreenWindow]) -> Bool {
        guard let id = windowID(of: window) else { return true } // can't tell: assume it is
        return windows.first { $0.bounds.contains(point) }?.id == id
    }

    private typealias GetWindow = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private static let getWindow: GetWindow? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "_AXUIElementGetWindow") else { return nil }
        return unsafeBitCast(symbol, to: GetWindow.self)
    }()

    private static func windowID(of window: AXUIElement) -> CGWindowID? {
        var id: CGWindowID = 0
        guard let getWindow, getWindow(window, &id) == .success, id != 0 else { return nil }
        return id
    }
}
