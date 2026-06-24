import Foundation

/// Consecutive-correct streak math shared by the drill stat stores. The
/// current/best-run algorithms were reimplemented identically in
/// TacticsPerformanceStore and RepertoireDrillStats (differing only in the
/// per-attempt success predicate); callers now map attempts to `[Bool]`
/// (most-recent last) and call these. (dedup audit 2026-06-16)
nonisolated enum StreakMath {
    /// Length of the trailing run of `true` (the streak ending at the most
    /// recent attempt). Any `false` breaks it.
    static func current(_ flags: [Bool]) -> Int {
        var streak = 0
        for flag in flags.reversed() {
            guard flag else { return streak }
            streak += 1
        }
        return streak
    }

    /// Longest run of `true` anywhere in the sequence.
    static func best(_ flags: [Bool]) -> Int {
        var best = 0
        var current = 0
        for flag in flags {
            if flag {
                current += 1
                if current > best { best = current }
            } else {
                current = 0
            }
        }
        return best
    }
}
