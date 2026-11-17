import GridCore

final class GestureTests {
    func testAdaptiveGridAndIncompleteRows() {
        let six = Grid(desktopCount: 6)
        expectEqual(six.columns, 3)
        expectEqual(six.rows, 2)
        expectEqual(six.neighbor(of: 2, toward: .down), 5)
        expectEqual(six.neighbor(of: 4, toward: .up), 1)
        expectNil(six.neighbor(of: 2, toward: .right))
        expectNil(six.neighbor(of: 5, toward: .down))
        let five = Grid(desktopCount: 5)
        expectNil(five.neighbor(of: 2, toward: .down))
        expectNil(five.neighbor(of: 4, toward: .right))
        for count in 4...16 {
            let grid = Grid(desktopCount: count)
            for index in 0..<count {
                for direction in Direction.allCases {
                    if let neighbor = grid.neighbor(of: index, toward: direction) {
                        expectFalse(neighbor < 0 || neighbor >= count)
                    }
                }
            }
        }
    }
    func testGridNeighborsAndEdges() {
        let grid = Grid()
        expectEqual(grid.neighbor(of: 0, toward: .right), 1)
        expectEqual(grid.neighbor(of: 0, toward: .down), 2)
        expectEqual(grid.neighbor(of: 3, toward: .up), 1)
        expectEqual(grid.neighbor(of: 3, toward: .left), 2)
        expectNil(grid.neighbor(of: 0, toward: .left))
        expectNil(grid.neighbor(of: 0, toward: .up))
        expectNil(grid.neighbor(of: 3, toward: .right))
        expectNil(grid.neighbor(of: 3, toward: .down))
        expectNil(grid.neighbor(of: -1, toward: .down))
        expectNil(grid.neighbor(of: 4, toward: .up))
    }

    func testContactAssemblyAndTwoFingerScrolling() {
        var tracker = SwipeTracker()
        for count in [1, 2] {
            expectNil(tracker.update(count: count, identity: 1, x: 0.5, y: 0.5, time: 0))
        }
        expectNil(tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 1))
        expectNotNil(tracker.update(count: 3, identity: 7, x: 0.4, y: 0.5, time: 1.1))
        expectEqual(tracker.sample?.direction, .right)
    }

    func testSlowShortSwipeReturnsAndLongSwipeCommits() {
        var tracker = SwipeTracker()
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 1)
        _ = tracker.update(count: 3, identity: 7, x: 0.46, y: 0.5, time: 1.5)
        expectEqual(tracker.finish(count: 0, time: 1.7)?.commits, false)
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 2)
        _ = tracker.update(count: 3, identity: 7, x: 0.39, y: 0.5, time: 2.5)
        expectEqual(tracker.finish(count: 0, time: 2.7)?.commits, true)
    }

    func testDirectionalFlickAndVelocityExpiry() {
        var tracker = SwipeTracker()
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 1)
        _ = tracker.update(count: 3, identity: 7, x: 0.48, y: 0.5, time: 1.02)
        expectEqual(tracker.finish(count: 0, time: 1.03)?.commits, true)
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 2)
        _ = tracker.update(count: 3, identity: 7, x: 0.48, y: 0.5, time: 2.02)
        expectEqual(tracker.finish(count: 0, time: 2.3)?.commits, false)
        expectFalse(SwipeSample(horizontal: true, displacement: 0.1, velocity: -2).commits)
    }

    func testAxisLockAndReversal() {
        var tracker = SwipeTracker()
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 1)
        // Ambiguous diagonal does not steal the gesture.
        expectNil(tracker.update(count: 3, identity: 7, x: 0.52, y: 0.52, time: 1.1))
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.6, time: 1.2)
        expectEqual(tracker.sample?.direction, .down)
        _ = tracker.update(count: 3, identity: 7, x: 0.8, y: 0.48, time: 1.3)
        expectEqual(tracker.sample?.direction, .up)
        expectEqual(tracker.sample?.horizontal, false)
        expectEqual(tracker.finish(count: 0, time: 1.6)?.commits, false)
    }

    func testIdentityChangesAndFourthFingerCancelUntilLift() {
        var tracker = SwipeTracker()
        _ = tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 1)
        _ = tracker.update(count: 3, identity: 7, x: 0.3, y: 0.5, time: 1.1)
        expectNil(tracker.update(count: 3, identity: 8, x: 0.2, y: 0.5, time: 1.2))
        expectNil(tracker.finish(count: 0, time: 1.3))
        _ = tracker.update(count: 4, identity: 7, x: 0.5, y: 0.5, time: 2)
        expectNil(tracker.update(count: 3, identity: 7, x: 0.3, y: 0.5, time: 2.1))
        expectNil(tracker.finish(count: 0, time: 2.2))
        expectNil(tracker.update(count: 3, identity: 7, x: 0.5, y: 0.5, time: 3))
        expectNotNil(tracker.update(count: 3, identity: 7, x: 0.3, y: 0.5, time: 3.1))
    }

    func testInvalidInputDoesNotAnimate() {
        var tracker = SwipeTracker()
        expectNil(tracker.update(count: 3, identity: 1, x: .nan, y: 0, time: 0))
        expectNil(tracker.sample)
    }
}

// A dependency-free runner so the checks work with Command Line Tools alone.
func expectEqual<T: Equatable>(_ actual: T, _ expected: T, file: StaticString = #file, line: UInt = #line) {
    guard actual == expected else { fatalError("Expected \(expected), got \(actual)", file: file, line: line) }
}
func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    guard value == nil else { fatalError("Expected nil", file: file, line: line) }
}
func expectNotNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) {
    guard value != nil else { fatalError("Expected a value", file: file, line: line) }
}
func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    guard !value else { fatalError("Expected false", file: file, line: line) }
}
let tests = GestureTests()
let cases: [(String, () -> Void)] = [
    ("adaptive grids and incomplete rows", tests.testAdaptiveGridAndIncompleteRows),
    ("grid neighbors and edges", tests.testGridNeighborsAndEdges),
    ("contact assembly and two-finger scrolling", tests.testContactAssemblyAndTwoFingerScrolling),
    ("slow short and long swipes", tests.testSlowShortSwipeReturnsAndLongSwipeCommits),
    ("flick and velocity expiry", tests.testDirectionalFlickAndVelocityExpiry),
    ("axis lock and reversal", tests.testAxisLockAndReversal),
    ("contact changes and fourth finger", tests.testIdentityChangesAndFourthFingerCancelUntilLift),
    ("invalid input", tests.testInvalidInputDoesNotAnimate)
]
for (name, run) in cases { run(); print("PASS: \(name)") }
print("\(cases.count) checks passed.")
