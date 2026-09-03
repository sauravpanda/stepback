import Foundation
import SwiftData

/// The importer used to cluster clips by date into "Event: Sep 2, 2026"
/// albums. They crowded out the albums people made on purpose, so they're
/// gone: nothing creates them any more, and any left in the store are
/// removed on the next visit to the Library.
enum LegacyEventAlbums {

    /// Matches exactly the shape the old clustering produced — the literal
    /// "Event: " prefix and a "<month> d, yyyy" date — so an album someone
    /// named by hand is never mistaken for one.
    static func isLegacyName(_ name: String) -> Bool {
        name.range(of: #"^Event: \S+ \d{1,2}, \d{4}$"#, options: .regularExpression) != nil
    }

    /// Deletes the legacy albums among `albums` and returns how many went.
    /// Clips lose only the label; an album is nothing but a label.
    @discardableResult
    static func remove(from albums: [Tag], in context: ModelContext) -> Int {
        let legacy = albums.filter { isLegacyName($0.name) }
        for album in legacy {
            context.delete(album)
        }
        return legacy.count
    }
}
