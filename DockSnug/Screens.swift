import AppKit
import ColorSync

enum Screens {
    static func current() -> [ScreenInfo] {
        // NSScreen is bottom-left based; screens[0] is the main display, whose top is y = 0 for Accessibility
        guard let mainHeight = NSScreen.screens.first?.frame.height else { return [] }
        return NSScreen.screens.compactMap { screen in
            guard let id = uuid(of: screen) else { return nil }
            return ScreenInfo(id: id,
                              full: flipped(screen.frame, mainHeight: mainHeight),
                              visible: flipped(screen.visibleFrame, mainHeight: mainHeight))
        }
    }

    private static func flipped(_ rect: CGRect, mainHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainHeight - rect.maxY, width: rect.width, height: rect.height)
    }

    /// Looking up a display's UUID is the slow part, and this runs several times a second.
    private static var knownUUIDs: [CGDirectDisplayID: String] = [:]

    /// Call when displays are connected, removed or rearranged: macOS may hand an ID to another display.
    static func forgetDisplays() {
        knownUUIDs = [:]
    }

    private static func uuid(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
        let displayID = number.uint32Value
        if let known = knownUUIDs[displayID] { return known }
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else { return nil }
        let string = CFUUIDCreateString(nil, uuid) as String
        knownUUIDs[displayID] = string
        return string
    }
}
