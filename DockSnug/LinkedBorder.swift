import CoreGraphics

// Pure logic for windows that share a border, like snapped windows on Windows:
// drag the border of one and the window on the other side follows.

enum WindowEdge: CaseIterable {
    case left, right, top, bottom
}

enum LinkedBorder {
    /// How far apart two edges may be and still count as one shared border (tiled windows can have a margin).
    static let touchTolerance: CGFloat = 16
    /// How far inside the neighbour to look when checking that it is really visible at the border.
    static let probeInset: CGFloat = 24

    /// A point's position along the direction `edge` moves in.
    static func along(_ edge: WindowEdge, _ point: CGPoint) -> CGFloat {
        edge == .left || edge == .right ? point.x : point.y
    }

    static func coordinate(_ edge: WindowEdge, of frame: CGRect) -> CGFloat {
        switch edge {
        case .left: return frame.minX
        case .right: return frame.maxX
        case .top: return frame.minY
        case .bottom: return frame.maxY
        }
    }

    /// How far `edge` moved between two frames.
    static func movement(of edge: WindowEdge, old: CGRect, new: CGRect) -> CGFloat {
        coordinate(edge, of: new) - coordinate(edge, of: old)
    }

    /// Edges that moved while the opposite edge stayed put. A window that is being moved, not
    /// resized, has both edges moving and gives none.
    static func draggedEdges(old: CGRect, new: CGRect) -> [WindowEdge] {
        func moved(_ edge: WindowEdge) -> Bool { abs(movement(of: edge, old: old, new: new)) > 0.5 }
        var edges: [WindowEdge] = []
        if moved(.left) != moved(.right) { edges.append(moved(.left) ? .left : .right) }
        if moved(.top) != moved(.bottom) { edges.append(moved(.top) ? .top : .bottom) }
        return edges
    }

    /// Does `other` sit against `edge` of `frame`, along at least half of the shorter window?
    static func isNeighbour(_ other: CGRect, of frame: CGRect, edge: WindowEdge) -> Bool {
        let gap: CGFloat
        let overlap: CGFloat
        let shorter: CGFloat
        switch edge {
        case .left, .right:
            gap = edge == .right ? other.minX - frame.maxX : frame.minX - other.maxX
            overlap = min(frame.maxY, other.maxY) - max(frame.minY, other.minY)
            shorter = min(frame.height, other.height)
        case .top, .bottom:
            gap = edge == .bottom ? other.minY - frame.maxY : frame.minY - other.maxY
            overlap = min(frame.maxX, other.maxX) - max(frame.minX, other.minX)
            shorter = min(frame.width, other.width)
        }
        return abs(gap) <= touchTolerance && shorter > 0 && overlap >= shorter / 2
    }

    /// Is there any window in `others` that a drag of `frame` could take along?
    static func hasNeighbour(_ frame: CGRect, among others: [CGRect]) -> Bool {
        others.contains { other in WindowEdge.allCases.contains { isNeighbour(other, of: frame, edge: $0) } }
    }

    /// The neighbour's frame after the shared border moved by `delta`. Its far edge stays where it is.
    static func adjusted(_ neighbour: CGRect, edge: WindowEdge, by delta: CGFloat) -> CGRect {
        var result = neighbour
        switch edge {
        case .right:
            result.origin.x += delta
            result.size.width -= delta
        case .left:
            result.size.width += delta
        case .bottom:
            result.origin.y += delta
            result.size.height -= delta
        case .top:
            result.size.height += delta
        }
        return result
    }

    /// Does the neighbour's own position change when the border moves, or only its size?
    static func movesOrigin(_ edge: WindowEdge) -> Bool {
        edge == .right || edge == .bottom
    }

    /// A point just inside the neighbour, halfway along the shared border.
    static func probe(neighbour: CGRect, of frame: CGRect, edge: WindowEdge) -> CGPoint {
        let midX = (max(frame.minX, neighbour.minX) + min(frame.maxX, neighbour.maxX)) / 2
        let midY = (max(frame.minY, neighbour.minY) + min(frame.maxY, neighbour.maxY)) / 2
        switch edge {
        case .right: return CGPoint(x: neighbour.minX + probeInset, y: midY)
        case .left: return CGPoint(x: neighbour.maxX - probeInset, y: midY)
        case .bottom: return CGPoint(x: midX, y: neighbour.minY + probeInset)
        case .top: return CGPoint(x: midX, y: neighbour.maxY - probeInset)
        }
    }
}
