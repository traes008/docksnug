import Foundation

/// Holds back drawing on screen for a moment, so two changes to a window show up as one.
/// Private macOS functions, looked up at runtime: if Apple removes them the changes just show
/// one after the other. macOS itself lifts the hold after a second if it is never released.
enum ScreenUpdates {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias UpdateFn = @convention(c) (Int32) -> Int32

    private static let symbols: (MainConnectionFn, UpdateFn, UpdateFn)? = {
        let path = "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        guard let handle = dlopen(path, RTLD_LAZY),
              let connection = dlsym(handle, "SLSMainConnectionID"),
              let disable = dlsym(handle, "SLSDisableUpdate"),
              let reenable = dlsym(handle, "SLSReenableUpdate") else { return nil }
        return (unsafeBitCast(connection, to: MainConnectionFn.self),
                unsafeBitCast(disable, to: UpdateFn.self), unsafeBitCast(reenable, to: UpdateFn.self))
    }()

    static func together(_ changes: () -> Void) {
        guard let (connection, disable, reenable) = symbols else { return changes() }
        let id = connection()
        _ = disable(id)
        changes()
        _ = reenable(id)
    }
}
