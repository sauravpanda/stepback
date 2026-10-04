import Foundation

/// How finely to count the beat out loud.
///
/// Dancers don't only count "1 2 3 4" — a triple step lives on "1 & 2", a
/// swung feel on "1 trip let", and tight footwork on "1 e & a". The count
/// row's dots and the metronome both read this, so choosing a subdivision
/// changes what you see *and* what you hear. The big counter deliberately
/// does not: it stays on the beat number.
///
/// `swung` is the WCS triple: the beat splits in three like `triplet`, but
/// the middle third is silent, so what you hear and step is "1 . a 2" —
/// a long step, then a short late "a" pulled toward the next beat. Its whole
/// point is to stop the "a" drifting forward onto a straight "&".
enum CountSubdivision: String, CaseIterable, Identifiable {
    case quarter
    case eighth
    case swung
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
        case .swung, .triplet: 3
        case .sixteenth: 4
        }
    }

    /// Menu label, written the way it is counted.
    var label: String {
        switch self {
        case .quarter: "1 2 3 4"
        case .eighth: "1 & 2 &"
        case .swung: "1 (&) a 2"
        case .triplet: "1 trip let"
        case .sixteenth: "1 e & a"
        }
    }

    /// Slots that are counted in time but neither clicked nor stepped.
    var silentSlots: Set<Int> {
        self == .swung ? [1] : []
    }

    /// The slot a triple step lands on between beats, if this count has one.
    var stepSlot: Int? {
        self == .swung ? 2 : nil
    }
}

/// The clicks to mix for a subdivision, with each one's tier.
struct ClickPlan: Equatable {
    var times: [Double] = []
    var downbeats: Set<Int> = []
    var subdivisions: Set<Int> = []
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

    /// Lays out the metronome for `subdivision`: every slot of every beat
    /// except the silent ones, with downbeats every `beatsPerMeasure` beats
    /// counted from the click nearest `anchor`.
    ///
    /// Silent slots are dropped *after* tiers are assigned, so removing them
    /// can't shift which click counts as the downbeat.
    static func clickPlan(
        beatTimes: [Double],
        subdivision: CountSubdivision,
        anchor: Double?,
        beatsPerMeasure: Int
    ) -> ClickPlan {
        let perBeat = subdivision.perBeat
        let slots = subdivide(beatTimes: beatTimes, perBeat: perBeat)
        let measureStride = max(1, beatsPerMeasure) * perBeat
        let anchorIndex = BeatGrid.nearestBeatIndex(to: anchor ?? 0, in: slots) ?? 0

        var plan = ClickPlan()
        for (index, time) in slots.enumerated() {
            // Swift's % keeps the dividend's sign; fold it back into 0..<n
            // so slots before the anchor are classified the same way.
            let offset = index - anchorIndex
            let slot = ((offset % perBeat) + perBeat) % perBeat
            if subdivision.silentSlots.contains(slot) { continue }
            let clickIndex = plan.times.count
            plan.times.append(time)
            if slot != 0 {
                plan.subdivisions.insert(clickIndex)
            } else if offset % measureStride == 0 {
                plan.downbeats.insert(clickIndex)
            }
        }
        return plan
    }
}
