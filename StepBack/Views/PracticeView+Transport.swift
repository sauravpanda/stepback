import SwiftUI

// MARK: - Transport

extension PracticeView {
    /// Single-row transport: A/B markers on the left, frame-step + play in
    /// the middle, speed selector on the right. Replaces the previous
    /// three rows (loop controls / play / speed pills) — which together
    /// cost ~150pt of vertical chrome on every clip. The compact A/B
    /// timestamps drop from the buttons here; the loop region is already
    /// rendered on the scrubber, and the Trim/Save Pattern action row above
    /// confirms the action visually when the user does something with A/B.
    var transportRow: some View {
        HStack(spacing: 14) {
            HStack(spacing: 6) {
                LoopButton(
                    label: "A",
                    filled: vm.loopStart != nil,
                    caption: nil
                ) {
                    vm.markLoopStart()
                }
                LoopButton(
                    label: "B",
                    filled: vm.loopEnd != nil,
                    caption: nil
                ) {
                    vm.markLoopEnd()
                }
                if vm.loopStart != nil || vm.loopEnd != nil {
                    Button {
                        vm.clearLoop()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(Theme.Color.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear loop")
                }
            }
            Spacer(minLength: 8)
            HStack(spacing: 18) {
                FrameStepButton(systemName: "backward.frame.fill") {
                    vm.stepBackward()
                }
                Button {
                    vm.togglePlayPause()
                } label: {
                    Image(systemName: vm.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.black)
                        .frame(width: 56, height: 56)
                        .background(Theme.Color.accent, in: Circle())
                }
                .buttonStyle(.plain)
                FrameStepButton(systemName: "forward.frame.fill") {
                    vm.stepForward()
                }
            }
            Spacer(minLength: 8)
            SpeedMenuButton(selected: vm.speed, onSelect: vm.setSpeed(_:))
        }
    }
}
