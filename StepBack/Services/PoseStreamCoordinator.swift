import AVFoundation
import Combine
import CoreVideo
import Foundation

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

    /// 100ms tick. At 10Hz, Vision's body-pose request runs cheaply enough
    /// to stay out of the main thread budget (work happens on
    /// `detectionQueue`) while still feeling reactive on the overlay.
    private static let tickInterval: Duration = .milliseconds(100)

    private let player: AVPlayer
    private let detector: PoseDetectionService
    private let videoOutput: AVPlayerItemVideoOutput
    private let detectionQueue = DispatchQueue(
        label: "com.sauravpanda.stepback.pose-detection",
        qos: .userInitiated
    )
    private var tickTask: Task<Void, Never>?

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

    private func tick() async {
        attachOutputIfNeeded()
        guard player.currentItem != nil else { return }
        let time = player.currentTime()
        guard videoOutput.hasNewPixelBuffer(forItemTime: time) else { return }
        guard let pixelBuffer = videoOutput.copyPixelBuffer(
            forItemTime: time,
            itemTimeForDisplay: nil
        ) else { return }

        if imageSize == nil {
            imageSize = CGSize(
                width: CVPixelBufferGetWidth(pixelBuffer),
                height: CVPixelBufferGetHeight(pixelBuffer)
            )
        }

        let result = await detect(pixelBuffer: pixelBuffer)
        switch result {
        case .success(let pose):
            self.pose = pose
            self.status = pose.map { .detected(jointCount: $0.joints.count) } ?? .noPerson
        case .failure(let error):
            self.status = .error(error.localizedDescription)
        }
    }

    /// Runs the synchronous Vision request on `detectionQueue` and bridges
    /// back to MainActor via a continuation. We capture `detector` by value
    /// so the queue closure doesn't touch `self` across the actor boundary.
    private func detect(pixelBuffer: CVPixelBuffer) async -> Result<DetectedPose?, Error> {
        let detector = self.detector
        return await withCheckedContinuation { continuation in
            detectionQueue.async {
                let outcome = Result {
                    try detector.detect(in: pixelBuffer)
                }
                continuation.resume(returning: outcome)
            }
        }
    }
}
