@testable import StepBack
import XCTest

final class ListeningExerciseTests: XCTestCase {

    func testLadderStartsWithTheBeatItself() {
        // The picker lists drills in order of difficulty; someone who
        // can't yet hear the beat must meet that one first.
        XCTAssertEqual(ListeningExercise.allCases.first, .tapTheBeat)
    }

    func testOnlyTapTheBeatGradesEveryBeat() {
        for exercise in ListeningExercise.allCases {
            XCTAssertEqual(exercise.gradesEveryBeat, exercise == .tapTheBeat, "\(exercise)")
        }
    }

    func testTapTheBeatIsAContinuousTakeInEights() {
        XCTAssertTrue(ListeningExercise.tapTheBeat.isContinuous)
        XCTAssertEqual(ListeningExercise.tapTheBeat.phraseLength(beatsPerMeasure: 4), 8)
        XCTAssertNotNil(ListeningExercise.tapTheBeat.lengthInPhrases)
    }

    func testTapTheBeatCatchWindowIsHalfABeat() {
        // Every tap is within half a beat of *some* beat, so nothing is a
        // stray: the drill is about how tight you are, not whether you hit.
        XCTAssertEqual(ListeningExercise.tapTheBeat.toleranceFraction, 0.5)
    }

    func testEveryExerciseTellsYouWhatToTapOn() {
        for exercise in ListeningExercise.allCases {
            XCTAssertFalse(exercise.tapPrompt.isEmpty, "\(exercise)")
        }
    }
}
