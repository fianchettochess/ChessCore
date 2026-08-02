import Foundation

/// The transport surface of a live UCI engine: send commands, read output lines.
///
/// Deliberately minimal and engine-agnostic, so one send-command / read-output /
/// parse-with-`UCIOutputParser` loop drives any engine you care to plug in.
///
/// It carries NO chess logic and NO construction requirement. Engines are
/// created concretely — each has its own initializer, network files and
/// provisioning — and the consumer picks which to link and declare conforming.
/// A conformance you do not own is declared `@retroactive`.
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
