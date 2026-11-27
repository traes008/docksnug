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
let hiddenDock = CGRect(x: 2762, y: 1346, width: 1108, height: 53)
func staleWithMacFullscreen(_ dock: CGRect?, _ screens: [ScreenInfo]) -> String {
    DockGeometry.staleReservation(dock: dock, screens: screens, settings: settings) { $0.id == "MAC" }?.id ?? "nil"
}
check("stale: full-screen app hides the Dock, Dell still reserved", staleWithMacFullscreen(hiddenDock, [dellReserved, macOK]), "DELL")
check("stale: same when the hidden Dock can't be read", staleWithMacFullscreen(nil, [dellReserved, macOK]), "DELL")
check("healthy: full-screen app hides the Dock, nothing reserved", staleWithMacFullscreen(hiddenDock, [dellOK, macOK]), "nil")
check("healthy: Dock on Dell while the MacBook is full screen", staleWithMacFullscreen(dockOnDell, [dellReserved, macOK]), "nil")

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

// Linked borders: two half-screen windows on the Dell
let leftHalf = CGRect(x: 0, y: 30, width: 1280, height: 1410)
let rightHalf = CGRect(x: 1280, y: 30, width: 1280, height: 1410)
let leftWider = CGRect(x: 0, y: 30, width: 1400, height: 1410)
check("link: dragging the right edge is seen", LinkedBorder.draggedEdges(old: leftHalf, new: leftWider), [.right])
check("link: moving a window is not a drag of an edge", LinkedBorder.draggedEdges(old: leftHalf, new: leftHalf.offsetBy(dx: 40, dy: 0)), [])
check("link: dragging a left edge is seen", LinkedBorder.draggedEdges(old: rightHalf, new: CGRect(x: 1400, y: 30, width: 1160, height: 1410)), [.left])
check("link: a corner drag gives two edges", LinkedBorder.draggedEdges(old: leftHalf, new: CGRect(x: 0, y: 30, width: 1400, height: 1300)), [.right, .bottom])
check("link: halves are neighbours", LinkedBorder.isNeighbour(rightHalf, of: leftHalf, edge: .right), true)
check("link: and the other way round", LinkedBorder.isNeighbour(leftHalf, of: rightHalf, edge: .left), true)
check("link: not on the wrong edge", LinkedBorder.isNeighbour(rightHalf, of: leftHalf, edge: .left), false)
check("link: a tiling margin still counts", LinkedBorder.isNeighbour(rightHalf.offsetBy(dx: 8, dy: 0), of: leftHalf, edge: .right), true)
check("link: a window further away doesn't", LinkedBorder.isNeighbour(rightHalf.offsetBy(dx: 60, dy: 0), of: leftHalf, edge: .right), false)
check("link: a quarter next to a half counts", LinkedBorder.isNeighbour(CGRect(x: 1280, y: 735, width: 1280, height: 705), of: leftHalf, edge: .right), true)
check("link: barely overlapping doesn't", LinkedBorder.isNeighbour(CGRect(x: 1280, y: 1300, width: 800, height: 600), of: leftHalf, edge: .right), false)
check("link: stacked windows are neighbours", LinkedBorder.isNeighbour(CGRect(x: 0, y: 735, width: 1280, height: 705), of: CGRect(x: 0, y: 30, width: 1280, height: 705), edge: .bottom), true)
check("link: neighbour is found in a list", LinkedBorder.hasNeighbour(leftHalf, among: [CGRect(x: 300, y: 300, width: 500, height: 400), rightHalf]), true)
check("link: no neighbour, nothing to do", LinkedBorder.hasNeighbour(leftHalf, among: [CGRect(x: 300, y: 300, width: 500, height: 400)]), false)
check("link: right neighbour gives way", LinkedBorder.adjusted(rightHalf, edge: .right, by: 120), CGRect(x: 1400, y: 30, width: 1160, height: 1410))
check("link: left neighbour grows into the space", LinkedBorder.adjusted(leftHalf, edge: .left, by: 120), leftWider)
check("link: lower neighbour gives way", LinkedBorder.adjusted(CGRect(x: 0, y: 735, width: 1280, height: 705), edge: .bottom, by: -100), CGRect(x: 0, y: 635, width: 1280, height: 805))
check("link: probe is inside the neighbour", rightHalf.contains(LinkedBorder.probe(neighbour: rightHalf, of: leftHalf, edge: .right)), true)

print(failures == 0 ? "\nAll checks passed" : "\n\(failures) check(s) failed")
exit(failures == 0 ? 0 : 1)
