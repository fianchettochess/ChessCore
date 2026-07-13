import Foundation

/// Single-source-of-truth codec for the `tagsJSON` field on
/// `StoredGame`. The format is semicolon-separated `key=value`
/// pairs with backslash escapes — chosen so the encoded string can
/// itself be a SwiftData property without needing a separate
/// `Data` blob, while still round-tripping the full PGN tag set
/// (where keys and values can contain any printable character).
///
/// Two call sites in the app used to maintain their own copy of
/// the decoder (`StoredGame.decodeTags` returning an OrderedTags,
/// `GameStatsView.parseTags` returning a plain dictionary). The
/// 2026-06-09 audit (V1-REVIEW §5) flagged the duplication as a
/// silent-correctness hazard — if the escaping rules ever needed
/// to change, only one site would get updated and stats would
/// quietly misparse every tag. Centralised here so both surfaces
/// share the same character-handling.
public nonisolated enum GameTagCodec {

    /// Encode an ordered PGN tag set. Keys and values are escaped for `\`,
    /// `=`, and `;` so the escape
    /// character, the separator, and the key/value delimiter all
    /// survive a round-trip even when they appear inside a key or value.
    ///
    /// The backslash must be escaped FIRST: the decoder's escape
    /// walk treats every `\` as "take the next character literally",
    /// so an unescaped literal backslash either swallows the
    /// following character (`a\b` decoded to `ab`) or — for a value
    /// ending in `\` — escapes the pair separator and merges two
    /// tags into one. Real inputs hit this: PGN `\"` escapes,
    /// Windows paths, TagEditorSheet free text. (V1-REVIEW follow-up
    /// 2026-06-10 §1 758d33c.)
    public static func encode(_ tags: PGNGame.OrderedTags) -> String {
        let pairs = tags.orderedKeys.compactMap { key -> String? in
            guard let value = tags[key] else { return nil }
            let escapedKey = key
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "=", with: "\\=")
                .replacingOccurrences(of: ";", with: "\\;")
            let escapedValue = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "=", with: "\\=")
                .replacingOccurrences(of: ";", with: "\\;")
            return "\(escapedKey)=\(escapedValue)"
        }
        return pairs.joined(separator: ";")
    }

    /// Decode preserving original key order. Used by `StoredGame`
    /// when reconstructing a `PGNGame` for export — PGN tag order
    /// is part of the canonical seven-tag-roster layout and round-
    /// trips matter for tooling parity.
    public static func decodeOrdered(_ encoded: String) -> PGNGame.OrderedTags {
        var tags = PGNGame.OrderedTags()
        for (key, value) in walkPairs(encoded) {
            tags[key] = value
        }
        return tags
    }

    /// Decode into an unordered dictionary. Used by analytics
    /// surfaces (GameStatsView speed/Elo classification) that only
    /// care about lookups, not order. Matches the historical
    /// `GameStatsView.parseTags` return shape so call sites can
    /// switch over without touching downstream code.
    public static func decode(_ encoded: String) -> [String: String] {
        var tags: [String: String] = [:]
        for (key, value) in walkPairs(encoded) {
            tags[key] = value
        }
        return tags
    }

    /// Targeted single-key lookup: the value of the first pair whose
    /// key equals `key`, or `nil` when absent. Exists so
    /// `StoredGame`'s cached-Elo fast path reads through the same
    /// escape walk as the full decoders instead of maintaining a
    /// third hand-rolled copy of the encoding — the drift hazard
    /// where a future escaping change silently mis-parses and
    /// durably persists wrong Elos via the CloudKit-synced cache
    /// fields. (V1-REVIEW follow-up 2026-06-10 §1 758d33c.)
    public static func firstValue(forKey key: String, in encoded: String) -> String? {
        walkPairs(encoded).first(where: { $0.0 == key })?.1
    }

    /// Common decoder pipeline. Yields `(key, value)` tuples in the
    /// order they appear in the encoded string. The
    /// character-by-character escape walk handles `\\`, `\=`, and
    /// `\;` consistently between the pair-splitting and
    /// key/value-splitting passes so an escaped `;` inside a value
    /// doesn't terminate the pair, and an escaped `=` inside a key
    /// doesn't promote the parser into value mode early.
    private static func walkPairs(_ encoded: String) -> [(String, String)] {
        guard !encoded.isEmpty else { return [] }

        // Split on unescaped semicolons.
        var pairs: [String] = []
        var current = ""
        var escaped = false
        for ch in encoded {
            if escaped {
                // Preserve the escape pair intact — pass 2 (the
                // key/value split) performs the single authoritative
                // unescape. Consuming the backslash here unescaped
                // twice: "\\;" inside a value lost its backslash and
                // pass 2 swallowed the following character.
                // (V1-REVIEW follow-up 2026-06-10 §1 758d33c)
                current.append("\\")
                current.append(ch)
                escaped = false
            } else if ch == "\\" {
                escaped = true
            } else if ch == ";" {
                pairs.append(current)
                current = ""
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { pairs.append(current) }

        // Split each pair on the first unescaped `=`.
        var out: [(String, String)] = []
        out.reserveCapacity(pairs.count)
        for pair in pairs {
            var key = ""
            var value = ""
            var inValue = false
            var pairEscaped = false
            for ch in pair {
                if pairEscaped {
                    if inValue { value.append(ch) } else { key.append(ch) }
                    pairEscaped = false
                } else if ch == "\\" {
                    pairEscaped = true
                } else if ch == "=" && !inValue {
                    inValue = true
                } else {
                    if inValue { value.append(ch) } else { key.append(ch) }
                }
            }
            if !key.isEmpty { out.append((key, value)) }
        }
        return out
    }
}
