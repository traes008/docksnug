import AppKit
import ApplicationServices

/// Small typed wrappers around the Accessibility C API.
extension AXUIElement {
    func attribute<T>(_ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    var position: CGPoint? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXPositionAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value as! AXValue, .cgPoint, &point) ? point : nil
    }

    var size: CGSize? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(self, kAXSizeAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value as! AXValue, .cgSize, &size) ? size : nil
    }

    /// Position and size in one round trip to the other app, instead of two.
    var frame: CGRect? {
        var values: CFArray?
        let names = [kAXPositionAttribute, kAXSizeAttribute] as CFArray
        if AXUIElementCopyMultipleAttributeValues(self, names, [], &values) == .success,
           let pair = values as? [AnyObject], pair.count == 2,
           CFGetTypeID(pair[0]) == AXValueGetTypeID(), CFGetTypeID(pair[1]) == AXValueGetTypeID() {
            var point = CGPoint.zero
            var size = CGSize.zero
            if AXValueGetValue(pair[0] as! AXValue, .cgPoint, &point), AXValueGetValue(pair[1] as! AXValue, .cgSize, &size) {
                return CGRect(origin: point, size: size)
            }
        }
        // An app that doesn't answer the combined request is asked the plain way
        guard let position, let size else { return nil }
        return CGRect(origin: position, size: size)
    }

    /// Size, then position, then size again: an app may clamp the size to fit the old position.
    func setFrame(_ frame: CGRect) {
        setSize(frame.size)
        setPosition(frame.origin)
        setSize(frame.size)
    }

    private func setSize(_ size: CGSize) {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return }
        AXUIElementSetAttributeValue(self, kAXSizeAttribute as CFString, value)
    }

    private func setPosition(_ point: CGPoint) {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return }
        AXUIElementSetAttributeValue(self, kAXPositionAttribute as CFString, value)
    }

    /// A normal window on screen: not a panel, not minimised, not native full screen.
    var isFittableWindow: Bool {
        let subrole: String? = attribute(kAXSubroleAttribute)
        let minimized: Bool? = attribute(kAXMinimizedAttribute)
        let fullScreen: Bool? = attribute("AXFullScreen")
        return subrole == kAXStandardWindowSubrole && minimized != true && fullScreen != true
    }

    var windows: [AXUIElement] {
        attribute(kAXWindowsAttribute) ?? []
    }
}

enum WindowList {
    /// Every normal window of every visible app. Accessibility only lists windows on the current Spaces.
    static func all() -> [AXUIElement] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isHidden }
            .flatMap { AXUIElementCreateApplication($0.processIdentifier).windows }
    }
}
