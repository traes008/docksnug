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

    private static func uuid(of screen: NSScreen) -> String? {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              let uuid = CGDisplayCreateUUIDFromDisplayID(number.uint32Value)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String
    }
}
