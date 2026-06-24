import Foundation

/// Schedules a piece of work to run after a fixed delay, cancelling
/// any previously-scheduled work so only the most recent call lands.
/// Used by the macOS AppKit split-view bridge to debounce
/// per-resize-callback writes to `UserDefaults` — but factored out so
/// the contract (cancel-then-reschedule, no leak on deinit) is
/// unit-testable without standing up an `NSSplitViewController`.
@MainActor
final class DebouncedWriter {
    private let delay: TimeInterval
    private var pendingWork: DispatchWorkItem?

    init(delay: TimeInterval) {
        self.delay = delay
    }

    /// Schedule `work` to run after `delay`. Cancels any previously
    /// scheduled call.
    func schedule(_ work: @escaping @Sendable () -> Void) {
        pendingWork?.cancel()
        let item = DispatchWorkItem(block: work)
        pendingWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Cancel any pending work without running it.
    func cancel() {
        pendingWork?.cancel()
        pendingWork = nil
    }

    /// True when a scheduled work item is still waiting to fire. Used
    /// by tests; not part of the production API.
    var hasPendingWork: Bool {
        pendingWork.map { !$0.isCancelled } ?? false
    }

    // `isolated deinit` (SE-0371) runs the deinit on the main actor, so it can
    // safely touch the main-actor-isolated, non-Sendable `pendingWork` under
    // Swift 6 strict concurrency.
    isolated deinit {
        pendingWork?.cancel()
    }
}
