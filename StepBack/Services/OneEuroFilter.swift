import Foundation

/// Adaptive low-pass filter (Casiez, Roussel & Vogel, 2012) for smoothing a
/// noisy 1-D signal sampled at irregular intervals.
///
/// The cutoff frequency rises with the signal's speed: it removes jitter
/// when the value is roughly stationary but stays responsive during fast
/// motion. That's exactly the trade-off a dancing skeleton needs — steady
/// when the dancer is posed, snappy on a kick — and it's why a plain
/// fixed-cutoff low-pass (which would lag every fast move) isn't enough.
///
/// Pure value type: deterministic for a given input sequence, so it's
/// unit-tested directly without a player or Vision.
struct OneEuroFilter {

    /// Minimum cutoff frequency (Hz). Lower = smoother but laggier at rest.
    let minCutoff: Double
    /// Speed coefficient. Higher = more responsive during fast motion (less
    /// lag) at the cost of letting more jitter through while moving.
    let beta: Double
    /// Cutoff for the derivative's own low-pass. 1.0 is the paper's default
    /// and rarely needs tuning.
    let dCutoff: Double

    private var lastRawValue: Double?
    private var filteredValue: Double?       // x̂_{t-1}
    private var filteredDerivative: Double?  // dx̂_{t-1}
    private var lastTimestamp: Double?

    init(minCutoff: Double = 1.0, beta: Double = 0.0, dCutoff: Double = 1.0) {
        self.minCutoff = minCutoff
        self.beta = beta
        self.dCutoff = dCutoff
    }

    /// Exponential smoothing factor for a cutoff frequency and timestep.
    /// `dt` must be > 0; callers guarantee that.
    private static func alpha(cutoff: Double, dt: Double) -> Double {
        let tau = 1.0 / (2.0 * .pi * cutoff)
        return 1.0 / (1.0 + tau / dt)
    }

    /// Feeds a new sample and returns the smoothed value. `timestamp` is in
    /// seconds; intervals may be irregular. The first sample passes through
    /// unchanged (nothing to smooth against yet). A non-monotonic timestamp
    /// (a seek backward, or the same frame twice) is treated as a
    /// discontinuity and also passes through, resetting the derivative.
    mutating func filter(_ value: Double, timestamp: Double) -> Double {
        defer {
            lastRawValue = value
            lastTimestamp = timestamp
        }

        guard let lastTimestamp, let previousFiltered = filteredValue else {
            filteredValue = value
            filteredDerivative = 0
            return value
        }

        let dt = timestamp - lastTimestamp
        guard dt > 0 else {
            filteredValue = value
            filteredDerivative = 0
            return value
        }

        // Derivative of the raw signal, itself low-passed before it drives
        // the adaptive cutoff.
        let rawDerivative = (value - (lastRawValue ?? value)) / dt
        let aDerivative = Self.alpha(cutoff: dCutoff, dt: dt)
        let previousDerivative = filteredDerivative ?? 0
        let smoothedDerivative =
            aDerivative * rawDerivative + (1 - aDerivative) * previousDerivative
        filteredDerivative = smoothedDerivative

        // Cutoff rises with speed → less smoothing (more responsiveness)
        // during fast motion.
        let cutoff = minCutoff + beta * abs(smoothedDerivative)
        let a = Self.alpha(cutoff: cutoff, dt: dt)
        let smoothed = a * value + (1 - a) * previousFiltered
        filteredValue = smoothed
        return smoothed
    }

    /// Forgets all history. The next sample passes through as a fresh start.
    mutating func reset() {
        lastRawValue = nil
        filteredValue = nil
        filteredDerivative = nil
        lastTimestamp = nil
    }
}
