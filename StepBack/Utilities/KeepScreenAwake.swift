import SwiftUI
import UIKit

/// Disables the system idle timer while the modified view is on screen.
///
/// Apply to any practice surface (PracticeView, CompareView, TrimView) so a
/// phone parked on a studio stand doesn't sleep mid-loop. Each view manages
/// its own toggle: when SwiftUI swaps between them via push/cover, the
/// outgoing view's onDisappear briefly re-enables the timer and the incoming
/// view's onAppear immediately disables it again — net effect is "always
/// disabled while a practice surface is visible."
struct KeepScreenAwakeModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .onAppear { UIApplication.shared.isIdleTimerDisabled = true }
            .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
    }
}

extension View {
    func keepScreenAwake() -> some View {
        modifier(KeepScreenAwakeModifier())
    }
}
