import Foundation
import ChessCore

/// Spaced-repetition mastery counts keyed by `fen:correctSAN`, shared by every
/// surface that asks the user to find the correct move from a flagged position
/// (the cross-library blunder drill and the game-review quiz both read/write
/// through it).
///
/// Pure logic + a `[String: Int]` blob over the ``JSONBlobStore`` seam. The
/// app's legacy-UserDefaults → blob migration stays app-side (in its
/// JSONBlobStore implementation); ChessCore just reads/writes the current blob.
public enum BlunderMasteryStore {
    /// Consecutive-correct attempts before a position counts as mastered and
    /// stops surfacing in the "due" queue.
    public static let masteryThreshold = 3

    /// Stable blob key for this store's row.
    public static let blobKey = "blunderMastery"

    /// Cross-store identity key (matches `TacticsAttempt.puzzleKey`).
    public static func key(fen: String, correctSAN: String) -> String {
        "\(fen):\(correctSAN)"
    }

    /// The FEN+SAN → consecutive-correct count map (empty if absent/malformed).
    public static func history(in store: JSONBlobStore) -> [String: Int] {
        guard let json = store.loadJSON(forKey: blobKey),
              let data = json.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: Int].self, from: data)
        else { return [:] }
        return dict
    }

    /// Record one attempt: correct bumps the per-key counter; wrong resets it to
    /// zero so the position resurfaces (parity with the pre-store behaviour).
    public static func record(fen: String, correctSAN: String, correct: Bool, in store: JSONBlobStore) {
        var dict = history(in: store)
        let k = key(fen: fen, correctSAN: correctSAN)
        if correct {
            dict[k, default: 0] += 1
        } else {
            dict[k] = 0
        }
        guard let data = try? JSONEncoder().encode(dict),
              let json = String(data: data, encoding: .utf8) else { return }
        store.saveJSON(json, forKey: blobKey)
    }

    public static func mastery(fen: String, correctSAN: String, in store: JSONBlobStore) -> Int {
        history(in: store)[key(fen: fen, correctSAN: correctSAN)] ?? 0
    }

    public static func isMastered(fen: String, correctSAN: String, in store: JSONBlobStore) -> Bool {
        mastery(fen: fen, correctSAN: correctSAN, in: store) >= masteryThreshold
    }
}
