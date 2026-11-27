import AppKit
import ApplicationServices

/// Keeps windows that share a border together while you drag that border.
///
/// It costs nothing until a window is resized with the mouse held down and another window sits
/// against it: window frames are remembered from work the app does anyway, so the check for a
/// neighbour is a look in memory. During the drag the neighbour follows the pointer itself, so it
/// doesn't have to wait for the dragged app to report its new size.
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

    /// What is known about one dragged edge while the pointer leads.
    private struct Lead {
        /// Border position minus pointer position, fixed at the moment the mouse went down.
        let grabOffset: CGFloat
        /// Set when the dragged window stopped following the pointer (its smallest or largest size):
        /// the border is then where the window really is, not where the pointer is.
        var stuckAt: CGFloat?
        var lastSeenEdge: CGFloat
        var pointerAtLastLook: CGFloat
    }

    private struct Drag {
        let window: AXUIElement
        let start: CGRect
        var followers: [Follower]
        var last: TimeInterval
        /// Empty when the pointer can't be trusted; the neighbour then follows the window's own reports.
        var leads: [WindowEdge: Lead] = [:]
        var lastLook: TimeInterval
    }

    private var frames: [Key: CGRect] = [:]
    private var drag: Drag?
    private var lastApplied: TimeInterval = -.infinity
    private var trailing: DispatchWorkItem?
    private var mouseDownMonitor: Any?
    private var dragMonitor: Any?
    private var mouseDownPoint: CGPoint?

    /// A drag is over when no resize has come for this long.
    private let dragTimeout: TimeInterval = 0.5
    /// At most this often is the neighbour moved; faster only burns CPU in both apps.
    private let minInterval: TimeInterval = 1.0 / 90
    /// How often the dragged window is asked where it really is while the pointer leads.
    private let lookInterval: TimeInterval = 0.15
    /// The mouse must have gone down this close to the border for the pointer to lead.
    private let grabTolerance: CGFloat = 12

    private var isEnabled: Bool {
        UserDefaults.standard.object(forKey: Self.settingKey) as? Bool ?? true
    }

    /// Clicks are rare, so noting where each one lands costs next to nothing.
    func start() {
        mouseDownMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown) { [weak self] _ in
            self?.mouseDownPoint = Self.pointer()
        }
    }

    /// Pointer position in the same top-left coordinates as window frames.
    private static func pointer() -> CGPoint? {
        CGEvent(source: nil)?.location
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
        // A release that was never reported must not leave a drag hanging
        if dragMonitor != nil && !CGEventSource.buttonState(.combinedSessionState, button: .left) { end() }
        if let current = drag, now - current.last < dragTimeout || dragMonitor != nil {
            if CFEqual(current.window, window) {
                drag?.last = now
                // While the pointer leads, the window's own reports are only late copies of it
                if current.leads.isEmpty { applyThrottled(now: now) }
                return
            }
            // A follower resizing is our own doing
            if current.followers.contains(where: { CFEqual($0.window, window) }) { return }
        }
        end()
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

        var current = Drag(window: window, start: old, followers: followers, last: now, lastLook: now)
        current.leads = leads(for: Set(followers.map(\.edge)), old: old, new: new)
        drag = current

        if current.leads.isEmpty {
            frames[key] = new
            apply(now: now) { LinkedBorder.movement(of: $0, old: old, new: new) }
        } else {
            // Only listens to the mouse for as long as this one drag lasts
            dragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp]) { [weak self] event in
                if event.type == .leftMouseUp { self?.mouseReleased() } else { self?.pointerMoved() }
            }
            pointerMoved()
        }
    }

    /// The pointer can lead only if the mouse went down right on each border being dragged.
    private func leads(for edges: Set<WindowEdge>, old: CGRect, new: CGRect) -> [WindowEdge: Lead] {
        guard CGEventSource.buttonState(.combinedSessionState, button: .left),
              let down = mouseDownPoint, let pointer = Self.pointer() else { return [:] }
        var result: [WindowEdge: Lead] = [:]
        for edge in edges {
            let offset = LinkedBorder.coordinate(edge, of: old) - LinkedBorder.along(edge, down)
            guard abs(offset) <= grabTolerance else { return [:] }
            result[edge] = Lead(grabOffset: offset, stuckAt: nil,
                                lastSeenEdge: LinkedBorder.coordinate(edge, of: new),
                                pointerAtLastLook: LinkedBorder.along(edge, pointer))
        }
        return result
    }

    // MARK: Pointer leads

    private func pointerMoved() {
        guard drag != nil, let pointer = Self.pointer() else { return }
        let now = ProcessInfo.processInfo.systemUptime
        drag?.last = now
        guard now - lastApplied >= minInterval else { return } // the next event, or the release, catches up
        if let current = drag, now - current.lastLook >= lookInterval { lookAtDraggedWindow(pointer: pointer, now: now) }
        guard let current = drag else { return }
        apply(now: now) { edge in
            guard let lead = current.leads[edge] else { return 0 }
            let border = lead.stuckAt ?? LinkedBorder.along(edge, pointer) + lead.grabOffset
            return border - LinkedBorder.coordinate(edge, of: current.start)
        }
    }

    /// Notices a dragged window that has stopped following the pointer, so the neighbour stops too.
    private func lookAtDraggedWindow(pointer: CGPoint, now: TimeInterval) {
        guard var current = drag, let frame = current.window.frame else { return }
        current.lastLook = now
        for (edge, var lead) in current.leads {
            let seen = LinkedBorder.coordinate(edge, of: frame)
            let pointerNow = LinkedBorder.along(edge, pointer)
            if abs(seen - lead.lastSeenEdge) > 0.5 {
                lead.stuckAt = nil
            } else if abs(pointerNow - lead.pointerAtLastLook) > 10 {
                lead.stuckAt = seen
            }
            lead.lastSeenEdge = seen
            lead.pointerAtLastLook = pointerNow
            current.leads[edge] = lead
        }
        drag = current
    }

    private func mouseReleased() {
        guard let finished = drag else { return end() }
        end()
        // The dragged app has the last word on where the border ended up
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self, self.drag == nil, let frame = finished.window.frame else { return }
            self.drag = finished
            self.apply(now: ProcessInfo.processInfo.systemUptime) { LinkedBorder.movement(of: $0, old: finished.start, new: frame) }
            self.frames[Key(window: finished.window)] = frame
            self.drag = nil
        }
    }

    private func end() {
        if let dragMonitor { NSEvent.removeMonitor(dragMonitor) }
        dragMonitor = nil
        trailing?.cancel()
        trailing = nil
        drag = nil
    }

    // MARK: Window leads

    /// Only a drag with the mouse links windows; an app resizing its own window doesn't.
    private static func isMouseDown() -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["DOCKSNUG_LINK_ANY_RESIZE"] != nil { return true }
        #endif
        return CGEventSource.buttonState(.combinedSessionState, button: .left)
    }

    private func applyFromWindow() {
        guard let current = drag, let frame = current.window.frame else { return }
        frames[Key(window: current.window)] = frame
        apply(now: ProcessInfo.processInfo.systemUptime) { LinkedBorder.movement(of: $0, old: current.start, new: frame) }
    }

    private func applyThrottled(now: TimeInterval) {
        if now - lastApplied >= minInterval {
            trailing?.cancel()
            trailing = nil
            applyFromWindow()
        } else if trailing == nil {
            // Make sure the last position of a drag is always applied
            let item = DispatchWorkItem { [weak self] in
                self?.trailing = nil
                self?.applyFromWindow()
            }
            trailing = item
            DispatchQueue.main.asyncAfter(deadline: .now() + minInterval, execute: item)
        }
    }

    // MARK: Moving the neighbours

    /// Moves every follower so its border sits `movement(edge)` from where the drag started.
    private func apply(now: TimeInterval, movement: (WindowEdge) -> CGFloat) {
        guard var current = drag else { return }
        lastApplied = now
        for index in current.followers.indices {
            let follower = current.followers[index]
            var target = LinkedBorder.adjusted(follower.start, edge: follower.edge, by: movement(follower.edge).rounded())
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
