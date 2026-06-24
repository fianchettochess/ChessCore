import XCTest
@testable import ChessCore

final class StorageTests: XCTestCase {
    /// In-memory ``JSONBlobStore`` — the portable test/Android-style backend
    /// (the Apple app backs the same protocol with SwiftData + CloudKit).
    final class MemoryBlobStore: JSONBlobStore {
        var storage: [String: String] = [:]
        func loadJSON(forKey key: String) -> String? { storage[key] }
        func saveJSON(_ json: String, forKey key: String) { storage[key] = json }
    }

    struct DemoStore: BlobBackedStore, Equatable {
        static let blobKey = "demo"
        var count: Int = 0
        var items: [String] = []
        init() {}
    }

    func testMissingBlobReturnsDefault() {
        let store = MemoryBlobStore()
        XCTAssertEqual(DemoStore.load(from: store), DemoStore())
    }

    func testBlobRoundTrip() {
        let store = MemoryBlobStore()
        var s = DemoStore()
        s.count = 3
        s.items = ["a", "b"]
        s.save(to: store)
        XCTAssertNotNil(store.storage["demo"])
        XCTAssertEqual(DemoStore.load(from: store), s)
    }

    func testMalformedBlobReturnsDefault() {
        let store = MemoryBlobStore()
        store.storage["demo"] = "{not valid json"
        XCTAssertEqual(DemoStore.load(from: store), DemoStore())
    }
}
