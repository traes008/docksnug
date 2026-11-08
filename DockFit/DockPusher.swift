import CoreGraphics
import Foundation

/// Moves the Dock to a screen the way you would by hand: pushing the pointer against the edge the
/// Dock sits on. Runs on a timer so the app never blocks; the pointer jumps back afterwards.
final class DockPusher {
    private static let pushCount = 15
    private static let pushDistance: Int64 = 8

    private var timer: Timer?

    func push(to screen: ScreenInfo, side: DockSide) {
        let edge: CGPoint
        let deltaX: Int64
        let deltaY: Int64
        switch side {
        case .left:
            (edge, deltaX, deltaY) = (CGPoint(x: screen.full.minX, y: screen.full.midY), -Self.pushDistance, 0)
        case .right:
            (edge, deltaX, deltaY) = (CGPoint(x: screen.full.maxX - 1, y: screen.full.midY), Self.pushDistance, 0)
        case .bottom:
            (edge, deltaX, deltaY) = (CGPoint(x: screen.full.midX, y: screen.full.maxY - 1), 0, Self.pushDistance)
        }

        let saved = CGEvent(source: nil)?.location
        CGWarpMouseCursorPosition(edge)

        var pushes = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { [weak self] timer in
            if let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved,
                                   mouseCursorPosition: edge, mouseButton: .left) {
                event.setIntegerValueField(.mouseEventDeltaX, value: deltaX)
                event.setIntegerValueField(.mouseEventDeltaY, value: deltaY)
                event.post(tap: .cgSessionEventTap)
            }
            pushes += 1
            if pushes >= Self.pushCount {
                timer.invalidate()
                self?.timer = nil
                if let saved { CGWarpMouseCursorPosition(saved) }
            }
        }
    }
}
