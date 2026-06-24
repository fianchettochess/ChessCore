import Foundation

// Storage seam — the portability boundary for ChessCore's persisted stores.
//
// The app's stat/SRS stores persist through `SyncedJSONBlob` (a SwiftData
// @Model row, CloudKit-mirrored, written through a debounced @MainActor
// coordinator). None of that — SwiftData, ModelContext, CloudKit — exists on
// Android, and Skip doesn't bridge it. So ChessCore can't reference any of it.
//
// Instead, the portable store LOGIC depends only on this tiny protocol: "give
// me / take a JSON string for a key." Each platform supplies the backend:
//   • Apple: a JSONBlobStore that reads/writes SyncedJSONBlob via ModelContext
//     and routes saves through the debounced, CloudKit-synced writer (the
//     existing app-side machinery — legacy-file migration, debounce, etc. all
//     stay there, behind this interface).
//   • Android: a JSONBlobStore backed by files / SharedPreferences / Room.
//
// This is the seam that lets the Elo engine, SRS rules, drill-history
// aggregation, etc. live ONCE in ChessCore instead of being reimplemented (and
// drifting) per platform.

/// A key→JSON-string blob backend. Implementations decide where the bytes live
/// (SwiftData+CloudKit on Apple, files/Room on Android) and how writes are
/// scheduled (the Apple impl debounces and syncs); the store logic above only
/// needs synchronous get/set by a stable key.
public protocol JSONBlobStore {
    /// The current JSON payload for `key`, or nil if absent/unreadable.
    func loadJSON(forKey key: String) -> String?
    /// Persist `json` for `key`. May be asynchronous/debounced internally;
    /// callers treat it as fire-and-forget.
    func saveJSON(_ json: String, forKey key: String)
}

/// A single-row `Codable` store persisted as one JSON blob under a stable key —
/// the portable form of the app's `BlobBackedStore`. Conformers supply the key
/// and a default `init()`; load/decode and encode/save are shared and run
/// against an injected ``JSONBlobStore`` rather than a SwiftData `ModelContext`.
/// (The Apple-side legacy-file migration lives in the app's JSONBlobStore impl.)
public protocol BlobBackedStore: Codable {
    /// Stable identifier for this store's row (e.g. "tacticsRating").
    static var blobKey: String { get }
    init()
}

public extension BlobBackedStore {
    /// Decode the store from `store[blobKey]`, falling back to a fresh `Self()`
    /// when the blob is missing or malformed.
    static func load(from store: JSONBlobStore, decoder: JSONDecoder = JSONDecoder()) -> Self {
        guard let json = store.loadJSON(forKey: blobKey),
              let data = json.data(using: .utf8),
              let decoded = try? decoder.decode(Self.self, from: data)
        else { return Self() }
        return decoded
    }

    /// Encode and persist the store to `store[blobKey]`. Silently drops on an
    /// encode failure (a single lost write shouldn't crash a drill flow).
    func save(to store: JSONBlobStore, encoder: JSONEncoder = JSONEncoder()) {
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8)
        else { return }
        store.saveJSON(json, forKey: Self.blobKey)
    }
}
