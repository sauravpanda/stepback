import SwiftUI

/// The one number people ask the library for, sitting under the title:
/// how many videos are in here, and how much dancing that adds up to.
/// With a tag filter on it says how many of them are showing, so the
/// grid never quietly looks smaller than the collection.
struct LibrarySummaryBar: View {
    /// The clips currently in the grid — all of them, or a tag's worth.
    let shown: [DanceClip]
    /// Everything in the library, filtered or not.
    let total: Int

    var body: some View {
        Text(
            LibraryFormatter.summary(
                shown: shown.count,
                total: total,
                seconds: shown.reduce(0) { $0 + $1.durationSeconds }
            )
        )
        .font(Theme.Font.caption)
        .foregroundStyle(Theme.Color.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .accessibilityAddTraits(.isHeader)
    }
}

extension LibraryFormatter {

    /// "12 videos", "1 video", or "4 of 12 videos" when a filter hides some.
    static func videoCount(shown: Int, total: Int) -> String {
        let noun = total == 1 ? "video" : "videos"
        guard shown != total else { return "\(total) \(noun)" }
        return "\(shown) of \(total) \(noun)"
    }

    /// Total running time at the coarseness a collection deserves — "1h 23m",
    /// "23m", "45s" — or nil when there is none to speak of, so the caller
    /// can leave it out rather than print "0s".
    static func totalDuration(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 1 else { return nil }
        let whole = Int(seconds.rounded())
        let hours = whole / 3_600
        let minutes = (whole % 3_600) / 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "\(whole)s"
    }

    /// The summary line: count, then running time when there is one.
    static func summary(shown: Int, total: Int, seconds: Double) -> String {
        [videoCount(shown: shown, total: total), totalDuration(seconds)]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}
