import CoreGraphics

// All frames use the Accessibility coordinate space: origin at the top-left of the main display,
// y grows downward. Everything in this file is pure, so it can be checked without a real screen.

struct ScreenInfo: Equatable {
    let id: String
    let full: CGRect
    /// What macOS reports as usable: the screen minus the menu bar and the space reserved for the Dock.
    let visible: CGRect
}

enum DockSide {
    case bottom, left, right
}

struct Settings {
    /// How far a window edge may sit from the usable-area edge and still count as touching it.
    var edgeTolerance: CGFloat = 8
    /// Seconds between checks of the Dock's position, since macOS sends no event when it jumps.
    var pollInterval: Double = 0.25
    /// Seconds between checks while nothing is going on. Each check wakes the app, and the wake-up
    /// costs far more than the check, so this is what keeps the app cheap.
    var idlePollInterval: Double = 1
    /// How long after the pointer last moved, or the Dock last changed, the faster checks continue.
    var activeLinger: Double = 3
    /// A window counts as maximised if its top is within this distance of the top of the usable area...
    var nearTopTolerance: CGFloat = 35
    /// ...and it is at most this much shorter than the usable area.
    var fullHeightSlack: CGFloat = 140
    /// A maximised window at least this fraction of the screen's width also gets its width fitted.
    var fullWidthRatio: CGFloat = 0.90
    /// Seconds macOS may keep Dock space reserved on a monitor the Dock has left before the Dock is restarted.
    var repairDelay: Double = 1.5
    /// Minimum seconds between Dock restarts, so a restart that doesn't help can't loop.
    var repairCooldown: Double = 60
    /// Seconds the pointer may press against a monitor's Dock edge before DockSnug brings the Dock there.
    var edgeAssistDelay: Double = 0.75
    /// Minimum seconds between those assists.
    var edgeAssistCooldown: Double = 2
}

enum DockGeometry {
    /// Measured: the Dock's Accessibility frame starts this far before macOS's reserved edge.
    private static let dockFrameInset: CGFloat = 4

    static func isDock(_ dock: CGRect?, on screen: ScreenInfo) -> Bool {
        guard let dock else { return false }
        let center = CGPoint(x: dock.midX, y: dock.midY)
        return center.x >= screen.full.minX && center.x <= screen.full.maxX &&
               center.y >= screen.full.minY && center.y <= screen.full.maxY
    }

    static func screen(withDock dock: CGRect?, in screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first { isDock(dock, on: $0) }
    }

    static func side(ofDock dock: CGRect, on screen: ScreenInfo) -> DockSide {
        if dock.width >= dock.height { return .bottom }
        return dock.minX - screen.full.minX < screen.full.width / 2 ? .left : .right
    }

    /// The true free area of a screen: minus the menu bar and the physical Dock, if it is here.
    /// macOS's own `visible` can be wrong or stale after the Dock moves, so it is only the fallback.
    static func usableFrame(of screen: ScreenInfo, dock: CGRect?) -> CGRect {
        let top = screen.visible.minY
        var bottom = screen.full.maxY
        var left = screen.full.minX
        var right = screen.full.maxX

        if let dock, isDock(dock, on: screen) {
            // Fit flush against the Dock: macOS's reserved edge is exactly that line and ignores
            // magnification, so use it when it's on this screen. If macOS has it stuck elsewhere,
            // work out the same line from the Dock, whose frame reaches past it.
            let tolerance = Settings().edgeTolerance
            switch side(ofDock: dock, on: screen) {
            case .bottom: bottom = bottom - screen.visible.maxY > tolerance ? screen.visible.maxY : dock.minY + dockFrameInset
            case .left: left = screen.visible.minX - left > tolerance ? screen.visible.minX : dock.maxX - dockFrameInset
            case .right: right = right - screen.visible.maxX > tolerance ? screen.visible.maxX : dock.minX + dockFrameInset
            }
        } else if dock == nil {
            bottom = screen.visible.maxY
            left = screen.visible.minX
            right = screen.visible.maxX
        }
        // (Dock found on another monitor: this screen gets its full area below the menu bar)

        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// New frame for a maximised (or half-snapped) window, or nil if it should be left alone.
    static func fitted(_ frame: CGRect, usable: CGRect, full: CGRect, settings: Settings) -> CGRect? {
        let isNearTop = abs(frame.minY - usable.minY) <= settings.nearTopTolerance
        let isFullHeight = frame.height >= usable.height - settings.fullHeightSlack
        let isFullWidth = frame.width >= full.width * settings.fullWidthRatio
        guard isNearTop && isFullHeight else { return nil }

        var result = frame
        var changed = false
        if abs(frame.height - usable.height) > 1 || abs(frame.minY - usable.minY) > 1 {
            result.origin.y = usable.minY
            result.size.height = usable.height
            changed = true
        }
        if isFullWidth && (abs(frame.width - usable.width) > 1 || abs(frame.minX - usable.minX) > 1) {
            result.origin.x = usable.minX
            result.size.width = usable.width
            changed = true
        }
        return changed ? result : nil
    }

    /// When the usable area changes, windows that exactly filled the old area follow it.
    /// E.g. a window sized to stop just above the Dock grows to the screen bottom when the Dock leaves.
    static func followed(_ frame: CGRect, old: CGRect, new: CGRect, settings: Settings) -> CGRect? {
        func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) <= settings.edgeTolerance }

        var result = frame
        var changed = false
        if near(frame.minY, old.minY) && near(frame.maxY, old.maxY) &&
           (abs(frame.minY - new.minY) > 1 || abs(frame.height - new.height) > 1) {
            result.origin.y = new.minY
            result.size.height = new.height
            changed = true
        }
        if near(frame.minX, old.minX) && near(frame.maxX, old.maxX) &&
           (abs(frame.minX - new.minX) > 1 || abs(frame.width - new.width) > 1) {
            result.origin.x = new.minX
            result.size.width = new.width
            changed = true
        }
        return changed ? result : nil
    }

    /// Sometimes (seen around full-screen apps) macOS keeps the Dock's space reserved on the monitor
    /// the Dock just left. Every app then refuses to grow into that strip, so resizing can't fix it;
    /// restarting the Dock makes macOS recalculate it.
    /// Returns the screen that still has Dock space reserved although the Dock is elsewhere.
    static func staleReservation(dock: CGRect?, screens: [ScreenInfo], settings: Settings,
                                 isFullscreen: (ScreenInfo) -> Bool) -> ScreenInfo? {
        guard let dockScreen = screen(withDock: dock, in: screens) else { return nil } // hidden or between monitors
        for screen in screens where screen.id != dockScreen.id {
            let reserved = screen.full.maxY - screen.visible.maxY > settings.edgeTolerance ||
                           screen.visible.minX - screen.full.minX > settings.edgeTolerance ||
                           screen.full.maxX - screen.visible.maxX > settings.edgeTolerance
            if reserved && !isFullscreen(screen) { return screen }
        }
        return nil
    }

    /// How long to wait before the next check. The Dock only jumps between monitors when the
    /// pointer pushes against an edge, so a still pointer with nothing pending can be checked rarely.
    static func nextPollInterval(sincePointerMoved: Double, sinceActivity: Double, settings: Settings) -> Double {
        min(sincePointerMoved, sinceActivity) < settings.activeLinger ? settings.pollInterval : settings.idlePollInterval
    }

    /// Is the pointer pressed against the edge of `screen` where the Dock lives?
    static func isAtDockEdge(_ point: CGPoint, of screen: ScreenInfo, side: DockSide) -> Bool {
        switch side {
        case .left: return point.x <= screen.full.minX + 1
        case .right: return point.x >= screen.full.maxX - 2
        case .bottom: return point.y >= screen.full.maxY - 2
        }
    }

    /// The screen a window is mostly on.
    static func bestScreen(for frame: CGRect, in screens: [ScreenInfo]) -> ScreenInfo? {
        var best: ScreenInfo?
        var bestArea: CGFloat = 0
        for screen in screens {
            let overlap = frame.intersection(screen.full)
            let area = overlap.isNull ? 0 : overlap.width * overlap.height
            if area > bestArea {
                best = screen
                bestArea = area
            }
        }
        return best
    }

    static func screen(at point: CGPoint, in screens: [ScreenInfo]) -> ScreenInfo? {
        screens.first {
            point.x >= $0.full.minX && point.x <= $0.full.maxX && point.y >= $0.full.minY && point.y <= $0.full.maxY
        }
    }
}
