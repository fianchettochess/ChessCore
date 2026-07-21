import Foundation

/// An escape-safe, compact string codec for an ordered PGN tag set.
///
/// The format is semicolon-separated `key=value` pairs with backslash escapes.
/// It is useful when an integration needs the complete tag set in one string;
/// structured storage should generally preserve tags as ordered key/value pairs
/// instead. Keeping this codec in ChessCore gives every consumer one set of
/// escaping rules without coupling the core model to a persistence framework.
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
    /// tags into one. Real inputs include PGN `\"` escapes, Windows paths,
    /// and free-text tag values.
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

    /// Decode preserving original key order. PGN tag order matters for the
    /// canonical seven-tag roster and for faithful re-export.
    public static func decodeOrdered(_ encoded: String) -> PGNGame.OrderedTags {
        var tags = PGNGame.OrderedTags()
        for (key, value) in walkPairs(encoded) {
            tags[key] = value
        }
        return tags
    }

    /// Decode into an unordered dictionary for consumers that only need lookup
    /// semantics and do not need to re-export the original tag order.
    public static func decode(_ encoded: String) -> [String: String] {
        var tags: [String: String] = [:]
        for (key, value) in walkPairs(encoded) {
            tags[key] = value
        }
        return tags
    }

    /// Targeted single-key lookup through the same escape walk as the full
    /// decoders, avoiding a second parser whose behavior could drift.
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
