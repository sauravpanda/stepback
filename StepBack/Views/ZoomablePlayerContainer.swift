import SwiftUI

/// Wraps video content with pinch-to-zoom, drag-to-pan (when zoomed), and
/// double-tap to toggle between 1x and 2x. Clips the content so zoomed pixels
/// don't overflow into surrounding controls.
///
/// Zooming anchors at the center of the frame. This is a deliberate
/// simplification — pinch-around-centroid felt fiddlier than useful during
/// playback, and users can just pan after zooming.
struct ZoomablePlayerContainer<Content: View>: View {

    private let content: Content
    private let onSingleTap: (() -> Void)?
    /// Reports a long-press as a fraction (0…1) of the *un-zoomed* container,
    /// so callers can map it back through their own letterbox/rotation to
    /// image space. Used for "hold a dancer to track them."
    private let onLongPressLocated: ((CGPoint) -> Void)?

    init(
        onSingleTap: (() -> Void)? = nil,
        onLongPressLocated: ((CGPoint) -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.onSingleTap = onSingleTap
        self.onLongPressLocated = onLongPressLocated
        self.content = content()
    }

    @State private var scale: CGFloat = 1.0
    @State private var baseScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var baseOffset: CGSize = .zero

    private let minScale: CGFloat = 1.0
    private let maxScale: CGFloat = 5.0
    private let doubleTapZoom: CGFloat = 2.0

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // The video itself. allowsHitTesting(false) lets UIKit's
                // default touch-swallowing step out of the way so SwiftUI
                // gestures on the overlay actually fire.
                content
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)
                    .allowsHitTesting(false)

                // Transparent gesture surface sitting on top of the video.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        SimultaneousGesture(
                            magnifyGesture(in: proxy.size),
                            panGesture(in: proxy.size)
                        )
                    )
                    .onTapGesture(count: 2) {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            if scale > minScale + 0.001 {
                                scale = minScale
                                offset = .zero
                            } else {
                                scale = doubleTapZoom
                                offset = .zero
                            }
                            baseScale = scale
                            baseOffset = offset
                        }
                    }
                    // Order matters: registering the count: 1 gesture after
                    // count: 2 lets SwiftUI disambiguate — a quick second tap
                    // still triggers zoom, not two single-tap pauses.
                    .onTapGesture(count: 1) {
                        onSingleTap?()
                    }
                    // Long-press to pin a person. Sequenced before a
                    // zero-distance drag so we can read the touch location;
                    // simultaneous so it coexists with pinch/pan, and the
                    // 0.45s hold keeps it from firing on taps or quick pans.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.45)
                            .sequenced(before: DragGesture(minimumDistance: 0))
                            .onEnded { value in
                                if case .second(true, let drag?) = value {
                                    let fraction = PoseCoordinateTransform.unzoomedFraction(
                                        location: drag.location,
                                        containerSize: proxy.size,
                                        scale: scale,
                                        offset: offset
                                    )
                                    onLongPressLocated?(fraction)
                                }
                            }
                    )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .clipped()
    }

    // MARK: - Gestures

    private func magnifyGesture(in size: CGSize) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let proposed = baseScale * value.magnification
                scale = min(max(proposed, minScale), maxScale)
                offset = clampedOffset(baseOffset, for: scale, in: size)
            }
            .onEnded { _ in
                baseScale = scale
                // Snap back to 1x if the user pinched essentially closed.
                if scale <= minScale + 0.01 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                        scale = minScale
                        baseScale = minScale
                        offset = .zero
                        baseOffset = .zero
                    }
                }
                baseOffset = offset
            }
    }

    private func panGesture(in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard scale > minScale + 0.01 else { return }
                let proposed = CGSize(
                    width: baseOffset.width + value.translation.width,
                    height: baseOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, for: scale, in: size)
            }
            .onEnded { _ in
                baseOffset = offset
            }
    }

    /// Keeps the zoomed content from panning off past its own edges. With
    /// `scale` = s and frame size W×H, the zoomed content occupies s·W × s·H,
    /// so the maximum offset in each axis is half the overflow.
    private func clampedOffset(_ proposed: CGSize, for scale: CGFloat, in size: CGSize) -> CGSize {
        let extraW = max(0, (size.width * scale - size.width) / 2)
        let extraH = max(0, (size.height * scale - size.height) / 2)
        return CGSize(
            width: min(max(proposed.width, -extraW), extraW),
            height: min(max(proposed.height, -extraH), extraH)
        )
    }
}
