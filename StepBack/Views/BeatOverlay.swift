import SwiftUI

// MARK: - Overlay on the Practice video

/// Beats and phrase changes drawn over the video, so the eye can put the
/// dancer's foot and the beat on the same screen at the same instant.
///
/// The lane scrolls the coming beats toward a fixed "now" line; the count
/// on the left says where in the 8 you are and jumps on each beat. Touches
/// pass straight through to the video's own gestures underneath.
struct BeatOverlay: View {
    let beatTimes: [Double]
    /// Indices of the "1" of each 8-count.
    let countStarts: Set<Int>
    /// Indices of the first beat of each 32-count phrase.
    let phraseStarts: Set<Int>
    /// 1-based position within the 8, nil off the grid.
    let position: Int?
    let time: Double
    /// Bumped on every beat by the player's boundary observer.
    let pulseID: Int

    @State private var scale: CGFloat = 1

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(position.map(String.init) ?? "–")
                .font(.system(size: 44, weight: .black, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(position == 1 ? Theme.Color.accent : Theme.Color.textPrimary)
                .scaleEffect(scale)
                .frame(width: 52, height: 52)
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
                colors: [.clear, .black.opacity(0.72)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(position.map { "Count \($0) of 8" } ?? "Beat overlay")
    }
}

/// The scrolling beat strip: a fixed "now" line at the centre, ticks for
/// every beat sliding toward it, taller for the 1 of an 8 and tallest, in
/// the accent, where a phrase turns over.
struct BeatLane: View {
    let beatTimes: [Double]
    let countStarts: Set<Int>
    let phraseStarts: Set<Int>
    let time: Double

    /// Seconds visible either side of now. Two seconds is four beats at
    /// 120 BPM: enough warning to see a phrase coming, close enough that
    /// the ticks stay far apart.
    static let window: Double = 2.0
    static let height: CGFloat = 46

    var body: some View {
        Canvas { context, size in
            let midX = size.width / 2
            let pointsPerSecond = midX / Self.window
            for index in BeatLaneGeometry.visibleIndices(beatTimes: beatTimes, around: time, window: Self.window) {
                let beat = beatTimes[index]
                let role = BeatLaneGeometry.role(of: index, countStarts: countStarts, phraseStarts: phraseStarts)
                let x = midX + (beat - time) * pointsPerSecond
                let isPast = beat < time - 0.02
                let height = (size.height - 12) * role.heightFraction
                let rect = CGRect(x: x - role.width / 2, y: size.height - height, width: role.width, height: height)
                context.fill(
                    Path(roundedRect: rect, cornerRadius: role.width / 2),
                    with: .color(role.color.opacity(isPast ? 0.3 : 1))
                )
                if role == .phrase, !isPast {
                    context.draw(
                        Text("phrase")
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Color.accent),
                        at: CGPoint(x: x, y: 5)
                    )
                }
            }
            let now = CGRect(x: midX - 1, y: 0, width: 2, height: size.height)
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

    /// The indices of the beats within `window` seconds of `time`, found by
    /// binary search so a ten-minute clip costs the same per frame as a
    /// ten-second one. `beatTimes` must be sorted.
    static func visibleIndices(beatTimes: [Double], around time: Double, window: Double) -> Range<Int> {
        let lower = firstIndex(in: beatTimes, atOrAfter: time - window)
        let upper = firstIndex(in: beatTimes, atOrAfter: time + window + .ulpOfOne * 16)
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
                time: time,
                pulseID: vm.beatPulseID
            )
        }
    }
}
