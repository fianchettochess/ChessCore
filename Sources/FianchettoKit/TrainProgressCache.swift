import Foundation
import ChessCore

/// Last-known progress per Train drill, written through by each drill when it
/// loads its pool and read by the Train hub (so a cold launch shows meaningful
/// counts without eagerly re-running every extractor). A device-local display
/// hint over the ``JSONBlobStore`` seam — the authoritative mastery history is
/// `BlunderMasteryStore`.
public enum TrainProgressCache {
    /// Counts as a drill's menu derives them. For Study (which drills mistakes
    /// from the loaded game) `total` carries the mistake count and `due` /
    /// `mastered` are 0.
    public struct Snapshot: Codable, Equatable {
        public var total: Int
        public var due: Int
        public var mastered: Int
        public init(total: Int, due: Int, mastered: Int) {
            self.total = total
            self.due = due
            self.mastered = mastered
        }
    }

    private static func key(for mode: PracticeMode) -> String {
        "trainProgress.\(mode.rawValue)"
    }

    /// Write through the counts a drill just derived.
    public static func record(_ snapshot: Snapshot, for mode: PracticeMode, into store: JSONBlobStore) {
        guard let data = try? JSONEncoder().encode(snapshot),
              let json = String(data: data, encoding: .utf8) else { return }
        store.saveJSON(json, forKey: key(for: mode))
    }

    /// The last recorded counts for a drill, or nil if never recorded.
    public static func snapshot(for mode: PracticeMode, from store: JSONBlobStore) -> Snapshot? {
        guard let json = store.loadJSON(forKey: key(for: mode)),
              let data = json.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}
