import AppKit
import ApplicationServices

/// Reads the physical position of the Dock, on whichever monitor it is currently shown.
final class DockReader {
    private var dock: AXUIElement?

    func bounds() -> CGRect? {
        if dock == nil {
            // Cached so the frequent poll doesn't search all running apps; dropped if the Dock restarts
            guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
                return nil
            }
            dock = AXUIElementCreateApplication(app.processIdentifier)
        }

        guard let children: [AXUIElement] = dock?.attribute(kAXChildrenAttribute) else {
            dock = nil
            return nil
        }
        for child in children {
            let role: String? = child.attribute(kAXRoleAttribute)
            // Ignore hidden Docks (when auto-hidden, the Dock sits off-screen or has 0 size)
            if role == kAXListRole, let frame = child.frame, frame.width > 0, frame.height > 0 {
                return frame
            }
        }
        return nil
    }
}
