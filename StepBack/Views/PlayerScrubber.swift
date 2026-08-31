import SwiftUI

/// Timeline with beat ticks, downbeat accents and the A/B loop region.
///
/// Shared by the Practice and Listen tabs — both want the same picture of
/// where the beats are, so this lives on its own rather than being copied.
struct PlayerScrubber: View {
    let currentTime: Double
    let duration: Double
    let loopStart: Double?
    let loopEnd: Double?
    let beatTimes: [Double]
    let downbeatIndices: Set<Int>
    let onSeek: (Double) -> Void

    @GestureState private var dragProgress: Double?

    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let progress = dragProgress ?? (duration > 0 ? min(1, currentTime / duration) : 0)
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Theme.Color.surfaceElevated)
                    .frame(height: 6)
                beatTicksOverlay(width: width)
                loopRegionOverlay(width: width)
                Capsule()
                    .fill(Theme.Color.accent)
                    .frame(width: width * progress, height: 6)
                Circle()
                    .fill(Theme.Color.accent)
                    .frame(width: 16, height: 16)
                    .offset(x: max(0, width * progress - 8))
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($dragProgress) { value, state, _ in
                        state = min(1, max(0, value.location.x / width))
                    }
                    .onEnded { value in
                        let ratio = min(1, max(0, value.location.x / width))
                        if duration > 0 {
                            onSeek(ratio * duration)
                        }
                    }
            )
        }
        .frame(height: 32)
    }

    @ViewBuilder
    private func beatTicksOverlay(width: CGFloat) -> some View {
        if duration > 0, !beatTimes.isEmpty {
            ZStack(alignment: .leading) {
                ForEach(Array(beatTimes.enumerated()), id: \.offset) { index, time in
                    let isDownbeat = downbeatIndices.contains(index)
                    Rectangle()
                        .fill(isDownbeat ? Theme.Color.accent : Theme.Color.textTertiary.opacity(0.6))
                        .frame(
                            width: isDownbeat ? 2 : 1,
                            height: isDownbeat ? 14 : 8
                        )
                        .offset(x: width * (time / duration))
                }
            }
        }
    }

    @ViewBuilder
    private func loopRegionOverlay(width: CGFloat) -> some View {
        if duration > 0, let start = loopStart, let end = loopEnd, end > start {
            let startX = width * min(1, max(0, start / duration))
            let endX = width * min(1, max(0, end / duration))
            Capsule()
                .fill(Theme.Color.accentSoft)
                .frame(width: max(2, endX - startX), height: 10)
                .offset(x: startX)
            ForEach([startX, endX], id: \.self) { edge in
                Rectangle()
                    .fill(Theme.Color.accent)
                    .frame(width: 2, height: 14)
                    .offset(x: max(0, edge - 1))
            }
        }
    }
}
