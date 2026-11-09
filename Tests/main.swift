// Checks the window and Dock logic with made-up screens. Run with scripts/check.sh.
import CoreGraphics
import Foundation

var failures = 0
func check<T: Equatable>(_ name: String, _ actual: T, _ expected: T) {
    if actual == expected {
        print("ok    \(name)")
    } else {
        failures += 1
        print("FAIL  \(name): got \(actual), wanted \(expected)")
    }
}

let settings = Settings()
let dellFull = CGRect(x: 0, y: 0, width: 2560, height: 1440)
let macFull = CGRect(x: 2560, y: 364, width: 1512, height: 982)
let dellOK = ScreenInfo(id: "DELL", full: dellFull, visible: CGRect(x: 0, y: 30, width: 2560, height: 1410))
let dellReserved = ScreenInfo(id: "DELL", full: dellFull, visible: CGRect(x: 0, y: 30, width: 2560, height: 1351))
let macOK = ScreenInfo(id: "MAC", full: macFull, visible: CGRect(x: 2560, y: 397, width: 1512, height: 949))
let macReserved = ScreenInfo(id: "MAC", full: macFull, visible: CGRect(x: 2560, y: 397, width: 1512, height: 890))
let dockOnMac = CGRect(x: 2762, y: 1283, width: 1108, height: 53)
let dockOnDell = CGRect(x: 726, y: 1377, width: 1108, height: 53)

func stale(_ dock: CGRect?, _ screens: [ScreenInfo], fullscreen: Bool = false) -> String {
    DockGeometry.staleReservation(dock: dock, screens: screens, settings: settings) { _ in fullscreen }?.id ?? "nil"
}

// Same six cases the Hammerspoon version was checked against
check("stale: Dock on MacBook, Dell reserved", stale(dockOnMac, [dellReserved, macOK]), "DELL")
check("healthy: Dock on MacBook, MacBook reserved", stale(dockOnMac, [dellOK, macReserved]), "nil")
check("healthy: Dock on Dell, Dell reserved", stale(dockOnDell, [dellReserved, macOK]), "nil")
check("stale but Dell is full screen", stale(dockOnMac, [dellReserved, macOK], fullscreen: true), "nil")
check("Dock hidden", stale(nil, [dellReserved, macOK]), "nil")
check("Dock off every screen", stale(CGRect(x: 100, y: 1500, width: 1108, height: 53), [dellReserved, macOK]), "nil")

// Usable areas, using values measured on the real machine
check("usable: Dell with Dock is flush with macOS's edge", DockGeometry.usableFrame(of: dellReserved, dock: dockOnDell),
      CGRect(x: 0, y: 30, width: 2560, height: 1351))
check("usable: reservation stuck elsewhere, same line from the Dock", DockGeometry.usableFrame(of: macOK, dock: dockOnMac),
      CGRect(x: 2560, y: 397, width: 1512, height: 890))
check("usable: magnified Dock doesn't move the edge", DockGeometry.usableFrame(of: dellReserved, dock: CGRect(x: 660, y: 1340, width: 1240, height: 90)),
      CGRect(x: 0, y: 30, width: 2560, height: 1351))
check("usable: Dell without Dock", DockGeometry.usableFrame(of: dellOK, dock: dockOnMac),
      CGRect(x: 0, y: 30, width: 2560, height: 1410))
check("usable: MacBook with Dock", DockGeometry.usableFrame(of: macReserved, dock: dockOnMac),
      CGRect(x: 2560, y: 397, width: 1512, height: 890))
check("usable: Dock unreadable falls back to macOS", DockGeometry.usableFrame(of: dellReserved, dock: nil),
      dellReserved.visible)

let usableNoDock = CGRect(x: 0, y: 30, width: 2560, height: 1410)
let usableWithDock = CGRect(x: 0, y: 30, width: 2560, height: 1345)

check("fit: 65pt gap is closed", DockGeometry.fitted(CGRect(x: 0, y: 30, width: 2560, height: 1345), usable: usableNoDock, full: dellFull, settings: settings),
      usableNoDock)
check("fit: a 2pt shortfall is closed", DockGeometry.fitted(CGRect(x: 0, y: 30, width: 2560, height: 1408), usable: usableNoDock, full: dellFull, settings: settings),
      usableNoDock)
check("fit: already right is left alone",DockGeometry.fitted(usableNoDock, usable: usableNoDock, full: dellFull, settings: settings), nil)
check("fit: small window is left alone", DockGeometry.fitted(CGRect(x: 100, y: 100, width: 800, height: 600), usable: usableNoDock, full: dellFull, settings: settings), nil)
check("fit: half-width keeps its width", DockGeometry.fitted(CGRect(x: 0, y: 30, width: 1280, height: 1345), usable: usableNoDock, full: dellFull, settings: settings),
      CGRect(x: 0, y: 30, width: 1280, height: 1410))

check("follow: Dock leaves, window grows", DockGeometry.followed(usableWithDock, old: usableWithDock, new: usableNoDock, settings: settings), usableNoDock)
check("follow: unrelated window stays", DockGeometry.followed(CGRect(x: 100, y: 100, width: 800, height: 600), old: usableWithDock, new: usableNoDock, settings: settings), nil)

check("poll: pointer just moved is checked quickly", DockGeometry.nextPollInterval(sincePointerMoved: 0.4, sinceActivity: 60, settings: settings), 0.25)
check("poll: Dock just changed is checked quickly", DockGeometry.nextPollInterval(sincePointerMoved: 60, sinceActivity: 1, settings: settings), 0.25)
check("poll: nothing going on is checked rarely", DockGeometry.nextPollInterval(sincePointerMoved: 60, sinceActivity: 60, settings: settings), 1.0)

check("edge: Dell bottom row", DockGeometry.isAtDockEdge(CGPoint(x: 900, y: 1439), of: dellOK, side: .bottom), true)
check("edge: just above", DockGeometry.isAtDockEdge(CGPoint(x: 900, y: 1430), of: dellOK, side: .bottom), false)
check("best screen: window on MacBook", DockGeometry.bestScreen(for: CGRect(x: 2600, y: 400, width: 900, height: 800), in: [dellOK, macOK])?.id, "MAC")
check("side: wide Dock is bottom", DockGeometry.side(ofDock: dockOnDell, on: dellOK), .bottom)
check("side: tall Dock on left", DockGeometry.side(ofDock: CGRect(x: 4, y: 300, width: 60, height: 800), on: dellOK), .left)
check("side: tall Dock on right", DockGeometry.side(ofDock: CGRect(x: 2496, y: 300, width: 60, height: 800), on: dellOK), .right)

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
