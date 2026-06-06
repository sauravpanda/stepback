@testable import StepBack
import XCTest

final class OneEuroFilterTests: XCTestCase {

    private let accuracy = 1e-9

    // MARK: - Pass-through cases

    func testFirstSamplePassesThroughUnchanged() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        XCTAssertEqual(filter.filter(0.42, timestamp: 0), 0.42, accuracy: accuracy)
    }

    func testConstantSignalStaysConstant() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        var dt = 0.0
        for _ in 0..<30 {
            let out = filter.filter(0.5, timestamp: dt)
            XCTAssertEqual(out, 0.5, accuracy: accuracy)
            dt += 0.06
        }
    }

    func testNonMonotonicTimestampPassesThrough() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        _ = filter.filter(0.1, timestamp: 1.0)
        _ = filter.filter(0.2, timestamp: 1.06)
        // Time goes backwards (a seek): the new value should pass through,
        // not blend with history across the discontinuity.
        let out = filter.filter(0.9, timestamp: 0.5)
        XCTAssertEqual(out, 0.9, accuracy: accuracy)
    }

    func testSameTimestampPassesThrough() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        _ = filter.filter(0.1, timestamp: 1.0)
        let out = filter.filter(0.8, timestamp: 1.0)  // dt == 0
        XCTAssertEqual(out, 0.8, accuracy: accuracy)
    }

    // MARK: - Smoothing behaviour

    func testSmoothedOutputLagsTowardNewValueWithoutOvershoot() {
        // Step from 0 to 1; output should move toward 1 monotonically and
        // never exceed it.
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.0)
        _ = filter.filter(0.0, timestamp: 0.0)
        var previous = 0.0
        var t = 0.06
        for _ in 0..<40 {
            let out = filter.filter(1.0, timestamp: t)
            XCTAssertGreaterThanOrEqual(out, previous - accuracy, "should not move backward")
            XCTAssertLessThanOrEqual(out, 1.0 + accuracy, "should not overshoot")
            previous = out
            t += 0.06
        }
        XCTAssertGreaterThan(previous, 0.9, "should converge close to the target")
    }

    func testReducesAlternatingJitter() {
        // Small-amplitude alternation around a mean, like real Vision noise.
        // The filter should shrink the swing.
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        let mean = 0.5
        let amplitude = 0.02
        var t = 0.0
        var lastOutputs: [Double] = []
        for i in 0..<40 {
            let raw = mean + (i % 2 == 0 ? amplitude : -amplitude)
            let out = filter.filter(raw, timestamp: t)
            if i >= 30 { lastOutputs.append(out) }
            t += 0.06
        }
        let maxDeviation = lastOutputs.map { abs($0 - mean) }.max() ?? .infinity
        XCTAssertLessThan(
            maxDeviation, amplitude,
            "smoothed swing (\(maxDeviation)) should be smaller than the raw amplitude (\(amplitude))"
        )
    }

    func testResetForgetsHistory() {
        var filter = OneEuroFilter(minCutoff: 1.0, beta: 0.5)
        _ = filter.filter(0.1, timestamp: 0.0)
        _ = filter.filter(0.1, timestamp: 0.06)
        filter.reset()
        // After reset the next sample is a fresh first sample → pass-through.
        XCTAssertEqual(filter.filter(0.95, timestamp: 0.12), 0.95, accuracy: accuracy)
    }
}
