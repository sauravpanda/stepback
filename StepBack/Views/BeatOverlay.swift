import SwiftUI

// MARK: - Overlay on the Practice video

/// Beats and phrase changes drawn over the video, so the eye can put the
/// dancer's foot and the beat on the same screen at the same instant.
///
/// Three things say where you are: the lane scrolls the coming beats
/// toward a fixed "now" line, the count on the left says which beat of the
/// 8 this is, and the strip under it says which 8 of the 32. A phrase start
/// only comes round every 32 beats, so it also announces itself: the count
/// and the scrim go pink for that whole beat. Touches pass straight through
/// to the video's own gestures underneath.
struct BeatOverlay: View {
    let beatTimes: [Double]
    /// Indices of the "1" of each 8-count.
    let countStarts: Set<Int>
    /// Indices of the first beat of each 32-count phrase.
    let phraseStarts: Set<Int>
    /// 1-based position within the 8, nil off the grid.
    let position: Int?
    /// 1-based position within the 32, nil off the grid.
    let phrasePosition: Int?
    let time: Double
    /// Bumped on every beat by the player's boundary observer.
    let pulseID: Int

    @State private var scale: CGFloat = 1

    private var isPhraseStart: Bool {
        phrasePosition == 1
    }

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                Text(position.map(String.init) ?? "–")
                    .font(.system(size: 44, weight: .black, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(position == 1 || isPhraseStart ? Theme.Color.accent : Theme.Color.textPrimary)
                    .scaleEffect(scale)
                    .frame(width: 60, height: 48)
                PhraseProgress(
                    eight: phrasePosition.map {
                        BeatLaneGeometry.eightOfPhrase(phrasePosition: $0, countLength: PhraseAnchor.countLength)
                    },
                    eightsPerPhrase: PhraseAnchor.phraseLength / PhraseAnchor.countLength
                )
            }
            .onChange(of: pulseID) { _, _ in
                withAnimation(.easeOut(duration: 0.05)) { scale = 1.15 }
                withAnimation(.easeIn(duration: 0.18).delay(0.05)) { scale = 1 }
            }
            BeatLane(
                beatTimes: beatTimes,
                countStarts: countStarts,
                phraseStarts: phraseStarts,
                time: time
            )
        }
        .padding(.horizontal, 12)
        .padding(.top, 22)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [.clear, (isPhraseStart ? Theme.Color.accent : .black).opacity(isPhraseStart ? 0.55 : 0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeOut(duration: 0.12), value: isPhraseStart)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let position, let phrasePosition else { return "Beat overlay" }
        let eight = BeatLaneGeometry.eightOfPhrase(phrasePosition: phrasePosition, countLength: PhraseAnchor.countLength)
        return "Count \(position) of 8, eight \(eight) of 4"
    }
}

/// Which 8 of the phrase this is: four short bars, the current one lit.
/// The bar that lights on a phrase change is the first, so the eye learns
/// to expect the turn-over as the fourth bar runs out.
struct PhraseProgress: View {
    /// 1-based, nil off the grid.
    let eight: Int?
    let eightsPerPhrase: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...max(1, eightsPerPhrase), id: \.self) { slot in
                Capsule()
                    .fill(color(for: slot))
                    .frame(width: 12, height: 4)
            }
        }
        .animation(.easeOut(duration: 0.1), value: eight)
    }

    private func color(for slot: Int) -> Color {
        guard let eight else { return Theme.Color.surfaceElevated }
        if slot == eight { return Theme.Color.accent }
        return slot < eight ? .white.opacity(0.6) : .white.opacity(0.22)
    }
}

/// The scrolling beat strip: a fixed "now" line, ticks for every beat
/// sliding toward it, taller and labelled "1" for the 1 of an 8, tallest
/// and in the accent, labelled "phrase", where a phrase turns over.
struct BeatLane: View {
    let beatTimes: [Double]
    let countStarts: Set<Int>
    let phraseStarts: Set<Int>
    let time: Double

    /// Seconds shown behind and ahead of now. Weighted forward: a beat
    /// that has gone is only context, a beat that's coming is the one
    /// you're aiming for, and three seconds is six beats at 120 BPM —
    /// enough warning to see a phrase change coming.
    static let past: Double = 1.0
    static let future: Double = 3.0
    static let height: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let pointsPerSecond = size.width / (Self.past + Self.future)
            let nowX = Self.past * pointsPerSecond
            let visible = BeatLaneGeometry.visibleIndices(
                beatTimes: beatTimes, around: time, past: Self.past, future: Self.future
            )
            for index in visible {
                let beat = beatTimes[index]
                let role = BeatLaneGeometry.role(of: index, countStarts: countStarts, phraseStarts: phraseStarts)
                let x = nowX + (beat - time) * pointsPerSecond
                let isPast = beat < time - 0.02
                let height = (size.height - 14) * role.heightFraction
                let rect = CGRect(x: x - role.width / 2, y: size.height - height, width: role.width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: role.width / 2),
                    with: .color(role.color.opacity(isPast ? 0.3 : 1))
                )
                if let label = role.label, !isPast {
                    context.draw(
                        Text(label)
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(role.color),
                        at: CGPoint(x: x, y: 6)
                    )
                }
            }
            let now = CGRect(x: nowX - 1, y: 0, width: 2, height: size.height)
            context.fill(Path(now), with: .color(.white.opacity(0.9)))
        }
        .frame(height: Self.height)
        .clipped()
    }
}

// MARK: - Lane geometry

enum BeatLaneRole: Equatable {
    case beat
    /// The 1 of an 8-count.
    case count
    /// The first beat of a 32-count phrase.
    case phrase

    var heightFraction: CGFloat {
        switch self {
        case .beat: 0.4
        case .count: 0.7
        case .phrase: 1.0
        }
    }

    var width: CGFloat {
        switch self {
        case .beat: 3
        case .count: 4
        case .phrase: 5
        }
    }

    var color: Color {
        switch self {
        case .beat: .white.opacity(0.7)
        case .count: .white
        case .phrase: Theme.Color.accent
        }
    }

    /// Drawn above the tick while it's still ahead.
    var label: String? {
        switch self {
        case .beat: nil
        case .count: "1"
        case .phrase: "phrase"
        }
    }
}

/// The pure parts of the lane, kept out of the `Canvas` closure so they
/// can be tested without drawing anything.
enum BeatLaneGeometry {

    /// A phrase start is also the 1 of an 8, so the phrase role wins.
    static func role(of index: Int, countStarts: Set<Int>, phraseStarts: Set<Int>) -> BeatLaneRole {
        if phraseStarts.contains(index) { return .phrase }
        if countStarts.contains(index) { return .count }
        return .beat
    }

    /// Which 8 of the phrase a 1-based phrase position falls in, 1-based.
    static func eightOfPhrase(phrasePosition: Int, countLength: Int) -> Int {
        guard countLength > 0 else { return 1 }
        return max(0, phrasePosition - 1) / countLength + 1
    }

    /// The indices of the beats from `past` seconds before `time` to
    /// `future` seconds after it, found by binary search so a ten-minute
    /// clip costs the same per frame as a ten-second one. `beatTimes` must
    /// be sorted.
    static func visibleIndices(beatTimes: [Double], around time: Double, past: Double, future: Double) -> Range<Int> {
        let lower = firstIndex(in: beatTimes, atOrAfter: time - past)
        let upper = firstIndex(in: beatTimes, atOrAfter: time + future + .ulpOfOne * 16)
        return lower..<max(lower, upper)
    }

    private static func firstIndex(in times: [Double], atOrAfter value: Double) -> Int {
        var low = 0
        var high = times.count
        while low < high {
            let mid = (low + high) / 2
            if times[mid] < value {
                low = mid + 1
            } else {
                high = mid
            }
        }
        return low
    }
}

// MARK: - Practice wiring

/// Feeds `BeatOverlay` from the Practice player at display rate.
///
/// Samples the player's own clock through `TimelineView` rather than the
/// view model's 0.1s `currentTime`, the same way the Listen counter does:
/// ticks that move ten times a second stutter, and a beat that lands
/// between samples flashes late.
struct PracticeBeatOverlay: View {
    @ObservedObject var vm: PracticePlayerViewModel
    let clip: DanceClip

    var body: some View {
        let beatTimes = clip.beatTimes
        let countStarts = BeatGrid.downbeatIndices(
            beatTimes: beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: PhraseAnchor.countLength
        )
        let phraseStarts = BeatGrid.downbeatIndices(
            beatTimes: beatTimes,
            anchor: clip.firstDownbeatSeconds,
            beatsPerMeasure: PhraseAnchor.phraseLength
        )
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !vm.isPlaying)) { _ in
            let time = vm.precisePlaybackTime
            BeatOverlay(
                beatTimes: beatTimes,
                countStarts: countStarts,
                phraseStarts: phraseStarts,
                position: PhraseGrid.phrasePosition(
                    currentTime: time,
                    beatTimes: beatTimes,
                    anchor: clip.firstDownbeatSeconds,
                    phraseLength: PhraseAnchor.countLength
                ),
                phrasePosition: PhraseGrid.phrasePosition(
                    currentTime: time,
                    beatTimes: beatTimes,
                    anchor: clip.firstDownbeatSeconds,
                    phraseLength: PhraseAnchor.phraseLength
                ),
                time: time,
                pulseID: vm.beatPulseID
            )
        }
    }
}
