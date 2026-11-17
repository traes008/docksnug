import CoreGraphics

/// Mission Control, App Exposé and Show Desktop are drawn by the Dock. Restarting the Dock or
/// pushing the pointer while one is open throws you out of it.
enum MissionControl {
    /// The Dock only has windows on this layer while one of those views is open.
    private static let overlayLayer = 18

    static var isOpen: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return windows.contains {
            ($0[kCGWindowOwnerName as String] as? String) == "Dock" && ($0[kCGWindowLayer as String] as? Int) == overlayLayer
        }
    }
}
