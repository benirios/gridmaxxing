import Foundation

public enum Direction: CaseIterable {
    case left, right, up, down
    public var horizontal: Bool { self == .left || self == .right }
}

public struct Grid {
    public let columns: Int
    public let rows: Int
    public let count: Int
    public init(columns: Int = 2, rows: Int = 2) {
        self.columns = columns; self.rows = rows; self.count = max(0, columns * rows)
    }
    public init(desktopCount: Int) {
        count = max(0, desktopCount)
        columns = max(1, Int(ceil(sqrt(Double(count)))))
        rows = (count + columns - 1) / columns
    }
    public func neighbor(of index: Int, toward direction: Direction) -> Int? {
        guard columns > 0, rows > 0, (0..<count).contains(index) else { return nil }
        let x = index % columns, y = index / columns
        switch direction {
        case .left: return x > 0 ? index - 1 : nil
        case .right: return x + 1 < columns && index + 1 < count ? index + 1 : nil
        case .up: return y > 0 ? index - columns : nil
        case .down: return y + 1 < rows && index + columns < count ? index + columns : nil
        }
    }
}

/// Input coordinates are normalized trackpad positions, with y pointing upward.
/// Output is the movement of the desktop surface, measured in screen widths/heights.
public struct SwipeSample {
    public let horizontal: Bool
    public let displacement: Double
    public let velocity: Double
    public init(horizontal: Bool, displacement: Double, velocity: Double) {
        self.horizontal = horizontal; self.displacement = displacement; self.velocity = velocity
    }
    public var direction: Direction {
        horizontal ? (displacement < 0 ? .right : .left) : (displacement < 0 ? .up : .down)
    }
    public var commits: Bool {
        abs(displacement) >= 0.25 || (abs(displacement) >= 0.025 && velocity * displacement > 0 && abs(velocity) >= 1)
    }
}

public struct SwipeTracker {
    private var origin: (Double, Double)?
    private var previous: (Double, Double)?
    private var axis: Bool?
    private var identity: UInt64 = 0
    private var blocked = false
    public private(set) var sample: SwipeSample?
    public init() {}

    /// A contact change cancels rather than treating a centroid jump as a swipe.
    public mutating func update(count: Int, identity: UInt64, x: Double, y: Double, time: Double) -> SwipeSample? {
        guard x.isFinite, y.isFinite, time.isFinite else { reset(); return nil }
        if count == 0 { reset(); return nil }
        if origin == nil && count < 3 { return nil }
        guard count == 3, !blocked else { blocked = true; sample = nil; return nil }
        guard let origin else {
            self.origin = (x, y); self.identity = identity
            previous = (0, time)
            return nil
        }
        guard self.identity == identity else { blocked = true; sample = nil; return nil }
        // A comfortable ~one-third trackpad traversal moves one screen.
        let dx = (x - origin.0) * 3, dy = (y - origin.1) * 3
        if axis == nil {
            guard max(abs(dx), abs(dy)) > 0.035,
                  max(abs(dx), abs(dy)) > min(abs(dx), abs(dy)) * 1.2 else { return nil }
            axis = abs(dx) > abs(dy)
        }
        let amount = max(-1, min(1, axis! ? dx : dy))
        let dt = time - (previous?.1 ?? time)
        let rawVelocity = dt > 0 && dt < 0.15 ? (amount - (previous?.0 ?? amount)) / dt : 0
        let velocity = (sample?.velocity ?? rawVelocity) * 0.65 + rawVelocity * 0.35
        sample = SwipeSample(horizontal: axis!, displacement: amount, velocity: velocity)
        previous = (amount, time)
        return sample
    }

    /// Only a clean lift commits. Adding/removing individual contacts cancels.
    public mutating func finish(count: Int, time: Double) -> SwipeSample? {
        defer { if count == 0 { reset() } else { blocked = true; sample = nil } }
        guard count == 0, !blocked, let sample else { return nil }
        if time - (previous?.1 ?? time) > 0.12 {
            return SwipeSample(horizontal: sample.horizontal, displacement: sample.displacement, velocity: 0)
        }
        return sample
    }
    public mutating func reset() { origin = nil; previous = nil; axis = nil; sample = nil; blocked = false }
}
