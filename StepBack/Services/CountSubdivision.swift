import Foundation

/// How finely to count the beat out loud.
///
/// Dancers don't only count "1 2 3 4" — a triple step lives on "1 & 2", a
/// swung feel on "1 trip let", and tight footwork on "1 e & a". The count
/// display and the metronome both read this, so choosing a subdivision
/// changes what you see *and* what you hear.
enum CountSubdivision: String, CaseIterable, Identifiable {
    case quarter
    case eighth
    case triplet
    case sixteenth

    var id: String {
        rawValue
    }

    /// Clicks per beat.
    var perBeat: Int {
        switch self {
        case .quarter: 1
        case .eighth: 2
        case .triplet: 3
        case .sixteenth: 4
        }
    }

    /// What each slot inside a beat is called. Index 0 is empty because the
    /// downbeat of the beat is spoken as its number — "1", not "1 and".
    var syllables: [String] {
        switch self {
        case .quarter: [""]
        case .eighth: ["", "&"]
        case .triplet: ["", "trip", "let"]
        case .sixteenth: ["", "e", "&", "a"]
        }
    }

    /// Menu label, written the way it is counted.
    var label: String {
        switch self {
        case .quarter: "1 2 3 4"
        case .eighth: "1 & 2 &"
        case .triplet: "1 trip let"
        case .sixteenth: "1 e & a"
        }
    }

    /// What to display for slot `index` of a beat numbered `beat`.
    ///
    /// Out-of-range indices fall back to the number rather than crashing or
    /// showing nothing — a count display that blanks out is worse than one
    /// that repeats itself.
    func spoken(beat: Int, index: Int) -> String {
        guard index > 0, index < syllables.count else { return "\(beat)" }
        return syllables[index]
    }
}

extension PhraseGrid {

    /// Which slot inside its beat `currentTime` falls in, 0-based.
    ///
    /// Works off the ratio through the enclosing beat rather than a fixed
    /// duration, so it stays correct when the grid's spacing drifts — beat
    /// times come from onset alignment, not from a perfect metronome.
    static func subdivisionIndex(
        currentTime: Double,
        beatTimes: [Double],
        perBeat: Int
    ) -> Int? {
        guard perBeat > 0, beatTimes.count >= 2 else { return nil }
        guard let start = beatTimes.lastIndex(where: { $0 <= currentTime }) else {
            return nil
        }
        // Past the final beat there is no interval to divide; hold on the
        // beat rather than extrapolating a spacing we can't know.
        guard start + 1 < beatTimes.count else { return 0 }

        let span = beatTimes[start + 1] - beatTimes[start]
        guard span > 0 else { return 0 }
        let fraction = (currentTime - beatTimes[start]) / span
        return min(perBeat - 1, max(0, Int(fraction * Double(perBeat))))
    }

    /// Expands a beat grid so it has `perBeat` evenly spaced points inside
    /// every beat. Used to click the subdivisions, not to replace the stored
    /// grid — drills and step timing keep scoring against real beats.
    ///
    /// The final beat contributes only itself: with no following beat there
    /// is no interval to subdivide.
    static func subdivide(beatTimes: [Double], perBeat: Int) -> [Double] {
        guard perBeat > 1, beatTimes.count >= 2 else { return beatTimes }
        var result: [Double] = []
        result.reserveCapacity(beatTimes.count * perBeat)
        for index in 0..<(beatTimes.count - 1) {
            let start = beatTimes[index]
            let step = (beatTimes[index + 1] - start) / Double(perBeat)
            result.append(start)
            for slot in 1..<perBeat {
                result.append(start + step * Double(slot))
            }
        }
        if let last = beatTimes.last {
            result.append(last)
        }
        return result
    }
}
