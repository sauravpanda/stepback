@testable import StepBack
import XCTest

final class LoopEvaluatorTests: XCTestCase {

    func testNoLoopReturnsNone() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: nil, loopEnd: nil),
            .none
        )
    }

    func testHalfLoopReturnsNone() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: 3, loopEnd: nil),
            .none
        )
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: nil, loopEnd: 8),
            .none
        )
    }

    func testDegenerateRangeReturnsNone() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: 8, loopEnd: 8),
            .none
        )
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: 10, loopEnd: 8),
            .none
        )
    }

    func testInsideLoopReturnsNone() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 5, loopStart: 3, loopEnd: 8),
            .none
        )
    }

    func testAtLoopEndSeeksToStart() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 8, loopStart: 3, loopEnd: 8),
            .seek(to: 3)
        )
    }

    func testPastLoopEndSeeksToStart() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 8.4, loopStart: 3, loopEnd: 8),
            .seek(to: 3)
        )
    }

    func testBeforeLoopStartReturnsNone() {
        XCTAssertEqual(
            LoopEvaluator.action(currentTime: 1, loopStart: 3, loopEnd: 8),
            .none
        )
    }
}
