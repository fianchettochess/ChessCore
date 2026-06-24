import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

extension URLSession {
    /// `data(for:)` back-deployed to iOS 13 / macOS 10.15 by wrapping the
    /// completion-handler `dataTask` in a checked continuation.
    ///
    /// The async `URLSession.data(for:)` / `bytes(for:)` are iOS 15 / macOS 12
    /// only; this keeps ChessCore's network services (TablebaseService,
    /// LichessExplorer, ChessAPIService) on the package's generous floor — the
    /// same approach SwiftStockfish's NNUE loader uses — and relies only on the
    /// completion-handler `dataTask`, which is broadly available (including on
    /// Android's swift-corelibs-foundation).
    ///
    /// Note: this does not forward Swift task cancellation to the underlying
    /// `URLSessionDataTask` (the async `data(for:)` does). The services here are
    /// short single-shot fetches, so that's an acceptable simplification.
    func dataResult(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await withCheckedThrowingContinuation { continuation in
            let task = dataTask(with: request) { data, response, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let data, let response else {
                    continuation.resume(throwing: URLError(.badServerResponse))
                    return
                }
                continuation.resume(returning: (data, response))
            }
            task.resume()
        }
    }

    /// Convenience `data(from:)` equivalent over `dataResult(for:)`.
    func dataResult(from url: URL) async throws -> (Data, URLResponse) {
        try await dataResult(for: URLRequest(url: url))
    }
}
