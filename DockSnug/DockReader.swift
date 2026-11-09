import AppKit
import ApplicationServices

/// Reads the physical position of the Dock, on whichever monitor it is currently shown.
final class DockReader {
    /// The Dock's icon list. Kept between reads so each poll is a single request; dropped if the Dock restarts.
    private var list: AXUIElement?

    func bounds() -> CGRect? {
        if list == nil { list = findList() }
        guard let list else { return nil }
        guard let frame = list.frame else {
            self.list = nil
            return nil
        }
        // Ignore hidden Docks (when auto-hidden, the Dock sits off-screen or has 0 size)
        return frame.width > 0 && frame.height > 0 ? frame : nil
    }

    private func findList() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            return nil
        }
        let children: [AXUIElement] = AXUIElementCreateApplication(app.processIdentifier).attribute(kAXChildrenAttribute) ?? []
        return children.first { ($0.attribute(kAXRoleAttribute) as String?) == kAXListRole }
    }
}
