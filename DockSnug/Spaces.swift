import Foundation

/// Tells whether a display is showing a native full-screen Space. macOS has no public API for this,
/// so the private function is looked up at runtime: if Apple removes it, DockSnug just treats
/// every Space as a normal one instead of crashing.
enum Spaces {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let fullscreenType = 4

    private static let symbols: (MainConnectionFn, CopySpacesFn)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let connection = dlsym(handle, "SLSMainConnectionID"),
              let copySpaces = dlsym(handle, "SLSCopyManagedDisplaySpaces") else { return nil }
        return (unsafeBitCast(connection, to: MainConnectionFn.self), unsafeBitCast(copySpaces, to: CopySpacesFn.self))
    }()

    static func isFullscreen(displayID: String) -> Bool {
        guard let (connection, copySpaces) = symbols,
              let displays = copySpaces(connection())?.takeRetainedValue() as? [[String: Any]] else { return false }
        for display in displays where (display["Display Identifier"] as? String) == displayID {
            let current = display["Current Space"] as? [String: Any]
            return (current?["type"] as? Int) == fullscreenType
        }
        return false
    }
}
