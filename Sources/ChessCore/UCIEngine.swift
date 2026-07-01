import Foundation

/// The transport surface of a live UCI engine: send commands, read output lines.
///
/// This is deliberately minimal and engine-agnostic — it's the seam that lets the
/// app drive more than one engine (Stockfish, Reckless, …) through one code path.
/// Both `SwiftStockfish.StockfishEngine` and `SwiftReckless.RecklessEngine` already
/// expose exactly this surface; the app declares their conformances (each app links
/// the engine packages, and does so `@retroactive` since it owns neither type).
///
/// It intentionally carries NO chess logic and NO construction requirement — engines
/// are created concretely (each has its own `init?(networkDirectory:)` + net
/// provisioning), and the app selects which to build. Everything downstream (the
/// send-UCI / read-output / parse-with `UCIOutputParser` loop) is written once against
/// this protocol.
///
/// - Note: implementations may hijack process-global stdio while live (e.g. an
///   in-process engine driving its UCI loop over pipes), so only ONE engine should be
///   live at a time and callers should avoid writing to stdout while one is running.
public protocol UCIEngine: AnyObject, Sendable {
    /// Ordered UCI output lines from the engine, without trailing newlines.
    var output: AsyncStream<String> { get }

    /// Send a raw UCI command (no trailing newline needed).
    func send(_ command: String)

    /// Convenience: `send("uci")`.
    func uci()

    /// Convenience: `send("isready")`.
    func isReady()

    /// Convenience: `send("quit")`.
    func quit()
}
