import CoreGraphics
import Foundation

/// The clips either side of the one being played, in the order the user
/// came from — the Library grid as currently filtered — so a swipe on the
/// video moves to what they'd have tapped next without going back.
struct ClipNeighbors: Equatable {
    let previous: DanceClip?
    let next: DanceClip?

    static let none = ClipNeighbors(previous: nil, next: nil)

    init(previous: DanceClip?, next: DanceClip?) {
        self.previous = previous
        self.next = next
    }

    /// Neighbours of `clip` within `clips`; both nil when it isn't there.
    init(of clip: DanceClip, in clips: [DanceClip]) {
        guard let index = clips.firstIndex(where: { $0.id == clip.id }) else {
            self = .none
            return
        }
        previous = index > 0 ? clips[index - 1] : nil
        next = index + 1 < clips.count ? clips[index + 1] : nil
    }
}

/// Turns a finished drag on the video into a page turn, or nothing.
enum PlayerSwipe {
    enum Direction: Equatable {
        /// Finger moved left: the next clip slides in from the right.
        case toNext
        /// Finger moved right: the previous clip slides in from the left.
        case toPrevious
    }

    /// Points of horizontal travel before a drag counts as a swipe.
    static let minimumTravel: CGFloat = 60

    /// Nil unless the drag was a deliberate, mostly horizontal swipe on an
    /// un-zoomed video. When zoomed, horizontal drags are panning the
    /// picture and must never turn the page.
    static func direction(for translation: CGSize, isZoomed: Bool) -> Direction? {
        guard !isZoomed else { return nil }
        let horizontal = abs(translation.width)
        guard horizontal >= minimumTravel, horizontal > abs(translation.height) * 1.5 else {
            return nil
        }
        return translation.width < 0 ? .toNext : .toPrevious
    }
}
