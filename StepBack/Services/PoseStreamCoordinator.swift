import AVFoundation
import Combine
import CoreVideo
import Foundation
import ImageIO

/// Drives pose detection against an `AVPlayer`'s currently-displayed frame.
/// Attaches an `AVPlayerItemVideoOutput` to whatever item is current, polls
/// every 100ms while running, and publishes the latest pose + status. The
/// view observes those publications and draws/labels accordingly.
@MainActor
final class PoseStreamCoordinator: ObservableObject {

    /// Dashboard-friendly summary of what the pipeline is currently doing.
    /// `idle` = pipeline off. `waiting` = on, but no frame yet (e.g. just
    /// flipped the toggle and the next tick hasn't fired). The chip in the
    /// view keys off this directly.
    enum Status: Equatable {
        case idle
        case waiting
        case detected(jointCount: Int)
        case noPerson
        case error(String)
    }

    @Published private(set) var pose: DetectedPose?
    @Published private(set) var status: Status = .idle
    @Published private(set) var imageSize: CGSize?
    @Published private(set) var isActive: Bool = false
    /// Seconds since the most recent *successful* detection. Used by the
    /// overlay to fade the skeleton from solid (fresh) to transparent
    /// (about-to-be-cleared) so the dashboard can see when we're holding a
    /// stale frame vs reading the current one.
    @Published private(set) var poseAge: TimeInterval = .infinity

    /// 60ms tick (~16Hz). Was 100ms — bumped up because Vision routinely
    /// misses individual frames on dance footage and more attempts per
    /// second materially improves coverage. Detection runs on a background
    /// queue so the main thread isn't squeezed; the actual cycle time is
    /// roughly tickInterval + detection_time (~10-30ms on iPhone 12+).
    private static let tickInterval: Duration = .milliseconds(60)
    /// Last successful pose stays visible for this long after detection
    /// starts failing. Bridges the flicker when Vision drops a frame or
    /// two on hard footage (motion blur, partial occlusion, etc).
    private static let staleAfter: TimeInterval = 0.5

    private let player: AVPlayer
    private let detector: PoseDetectionService
    private let videoOutput: AVPlayerItemVideoOutput
    private let detectionQueue = DispatchQueue(
        label: "com.sauravpanda.stepback.pose-detection",
        qos: .userInitiated
    )
    private var tickTask: Task<Void, Never>?
    private var lastSuccessTime: Date?
    private var lastProcessedTime: CMTime?
    /// Cached `CGImagePropertyOrientation` derived from the current player
    /// item's video track preferredTransform. Set asynchronously after the
    /// item swaps; until resolved we default to `.up`, which matches the
    /// pre-orientation behaviour.
    private var orientation: CGImagePropertyOrientation = .up
    private weak var orientationItem: AVPlayerItem?
    private var orientationTask: Task<Void, Never>?

    init(
        player: AVPlayer,
        detector: PoseDetectionService = PoseDetectionService()
    ) {
        self.player = player
        self.detector = detector
        videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
        ])
    }

    deinit {
        tickTask?.cancel()
    }

    func start() {
        guard tickTask == nil else { return }
        isActive = true
        status = .waiting
        pose = nil
        lastSuccessTime = nil
        lastProcessedTime = nil
        poseAge = .infinity
        attachOutputIfNeeded()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(for: Self.tickInterval)
            }
        }
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        isActive = false
        status = .idle
        pose = nil
        lastSuccessTime = nil
        lastProcessedTime = nil
        poseAge = .infinity
        detachOutput()
    }

    // MARK: - Internals

    /// AVPlayerItemVideoOutput is bound to a specific AVPlayerItem; when
    /// the player swaps items (trim export, reload, etc.) we need to
    /// re-attach. Cheap to call repeatedly, so the tick does it every loop.
    private func attachOutputIfNeeded() {
        guard let item = player.currentItem else { return }
        if !item.outputs.contains(where: { $0 === videoOutput }) {
            item.add(videoOutput)
        }
    }

    private func detachOutput() {
        if let item = player.currentItem,
           item.outputs.contains(where: { $0 === videoOutput }) {
            item.remove(videoOutput)
        }
    }

    /// Resolves the current item's video orientation from its preferred
    /// transform. Cached by item identity so we don't re-load the track
    /// on every tick — and so swapping items (after trim, after reload)
    /// triggers a fresh resolution. Until the async load completes we
    /// stay at the cached value, which on first item is `.up`.
    private func updateOrientationIfNeeded() {
        guard let item = player.currentItem else { return }
        if item === orientationItem { return }
        orientationItem = item
        // Reset cached imageSize so it gets re-derived with the new
        // orientation on the next pixel-buffer copy.
        imageSize = nil
        orientationTask?.cancel()
        orientationTask = Task { [weak self] in
            let resolved = await Self.resolveOrientation(for: item)
            await MainActor.run {
                guard let self else { return }
                guard self.orientationItem === item else { return }
                self.orientation = resolved
            }
        }
    }

    /// Async-loads the video track's preferred transform off the main
    /// actor so the tick doesn't block on it.
    nonisolated private static func resolveOrientation(
        for item: AVPlayerItem
    ) async -> CGImagePropertyOrientation {
        do {
            let tracks = try await item.asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { return .up }
            let transform = try await track.load(.preferredTransform)
            return CGImagePropertyOrientation(transform: transform)
        } catch {
            return .up
        }
    }

    private func tick() async {
        attachOutputIfNeeded()
        updateOrientationIfNeeded()
        guard player.currentItem != nil else { return }
        let time = player.currentTime()

        // Re-run detection if a new buffer is ready (playing) *or* the
        // current time changed since last process (the user scrubbed or
        // pause-stepped). Without the second condition, paused frames
        // would never get re-detected after a seek.
        let timeAdvanced: Bool = {
            guard let last = lastProcessedTime else { return true }
            return abs(CMTimeGetSeconds(time) - CMTimeGetSeconds(last)) > 0.01
        }()
        let hasNewBuffer = videoOutput.hasNewPixelBuffer(forItemTime: time)
        guard hasNewBuffer || timeAdvanced else {
            updatePoseAge()
            ageOutIfStale()
            return
        }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: time,
            itemTimeForDisplay: nil
        ) else {
            updatePoseAge()
            ageOutIfStale()
            return
        }
        lastProcessedTime = time

        if imageSize == nil {
            let raw = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
            // Vision returns joint coords in the upright (orientation-
            // corrected) frame, so we need to surface the *displayed*
            // dimensions for the overlay's aspect-fit math — that means
            // swapping width and height for 90°-rotated sources.
            imageSize = orientation.swapsAxes
                ? CGSize(width: raw.height, height: raw.width)
                : raw
        }

        let result = await detect(pixelBuffer: pixelBuffer, orientation: orientation)
        switch result {
        case .success(let detected):
            if let detected {
                self.pose = detected
                self.lastSuccessTime = Date()
                self.poseAge = 0
                self.status = .detected(jointCount: detected.joints.count)
            } else {
                // Vision returned no observation — the dancer might have
                // turned away, gone partially off-screen, or the frame's
                // hard. Don't immediately clear the skeleton; hold for up
                // to `staleAfter` so a single bad frame doesn't flicker.
                handleMissedDetection(reason: .noPerson)
            }
        case .failure(let error):
            handleMissedDetection(reason: .error(error.localizedDescription))
        }
    }

    /// Keeps the last successful pose visible until it's older than
    /// `staleAfter`. After that, clears it and surfaces the miss reason.
    private func handleMissedDetection(reason: Status) {
        updatePoseAge()
        if poseAge > Self.staleAfter {
            pose = nil
            status = reason
        }
        // Otherwise: keep showing the prior pose, leave status as it was —
        // the overlay's fade-by-age makes the staleness visible without
        // flickering the dashboard chip back and forth.
    }

    /// Called every tick whether we re-ran detection or not, so the view
    /// can fade the overlay smoothly between ticks.
    private func updatePoseAge() {
        guard let last = lastSuccessTime else {
            poseAge = .infinity
            return
        }
        poseAge = Date().timeIntervalSince(last)
    }

    /// When we skip detection (no new buffer, no scrub), we still want
    /// stale poses to age out — otherwise the last pose would linger
    /// indefinitely on a perfectly paused frame.
    private func ageOutIfStale() {
        if poseAge > Self.staleAfter, pose != nil {
            pose = nil
            status = .noPerson
        }
    }

    /// Runs the synchronous Vision request on `detectionQueue` and bridges
    /// back to MainActor via a continuation. We capture `detector` by value
    /// so the queue closure doesn't touch `self` across the actor boundary.
    private func detect(
        pixelBuffer: CVPixelBuffer,
        orientation: CGImagePropertyOrientation
    ) async -> Result<DetectedPose?, Error> {
        let detector = self.detector
        return await withCheckedContinuation { continuation in
            detectionQueue.async {
                let outcome = Result {
                    try detector.detect(in: pixelBuffer, orientation: orientation)
                }
                continuation.resume(returning: outcome)
            }
        }
    }
}
