import Foundation

// Magic-bitboard attack tables for the ChessCore move generator.
//
// Square indexing matches `Square.index` (= rank * 8 + file): a1 = 0, h1 = 7,
// a8 = 56, h8 = 63 — the standard Little-Endian Rank-File mapping. Bit `i` of a
// `Bitboard` (UInt64) is set iff square index `i` is occupied/relevant.
//
// All tables are computed lazily on first use via a thread-safe `static let`
// singleton (Swift guarantees one-time, race-free initialization of a global /
// static `let`). The 128 rook/bishop "magic" multipliers are EMBEDDED constants
// (see `rookMagics` / `bishopMagics`); init just fills each square's attack
// table in one collision-free pass (no runtime search — that was fast in
// optimized builds but catastrophically slow unoptimized, stalling the debug
// test suite). Regenerate the constants with the dev-only `testDumpMagics`. The
// resulting attack tables are ~2.3 MB total.
//
// Foundation-only, network-free — fits ChessCore's platform contract.

typealias Bitboard = UInt64

@inline(__always) func bit(_ index: Int) -> Bitboard { 1 << UInt64(index) }

/// Number of set bits (population count).
@inline(__always) func popcount(_ b: Bitboard) -> Int { b.nonzeroBitCount }

/// Index of the least-significant set bit (must be non-zero).
@inline(__always) func lsbIndex(_ b: Bitboard) -> Int { b.trailingZeroBitCount }

/// Clears the least-significant set bit and returns its index.
@inline(__always) func popLSB(_ b: inout Bitboard) -> Int {
    let idx = b.trailingZeroBitCount
    b = b & (b &- 1)
    return idx
}

// MARK: - Leaper attack tables (knight / king / pawn)

/// Precomputed knight, king, and pawn attack tables, plus per-square ray masks
/// used for between-square / pin computations.
struct LeaperTables {
    let knight: [Bitboard]
    let king: [Bitboard]
    // pawn[0] = white pawn attacks, pawn[1] = black pawn attacks
    let pawn: [[Bitboard]]

    init() {
        var knight = [Bitboard](repeating: 0, count: 64)
        var king = [Bitboard](repeating: 0, count: 64)
        var whitePawn = [Bitboard](repeating: 0, count: 64)
        var blackPawn = [Bitboard](repeating: 0, count: 64)

        let knightDeltas = [(1, 2), (2, 1), (2, -1), (1, -2),
                            (-1, -2), (-2, -1), (-2, 1), (-1, 2)]
        let kingDeltas = [(-1, -1), (-1, 0), (-1, 1), (0, -1),
                          (0, 1), (1, -1), (1, 0), (1, 1)]

        for sq in 0..<64 {
            let file = sq % 8
            let rank = sq / 8

            for (df, dr) in knightDeltas {
                let f = file + df, r = rank + dr
                if (0..<8).contains(f) && (0..<8).contains(r) {
                    knight[sq] = knight[sq] | (bit(r * 8 + f))
                }
            }
            for (df, dr) in kingDeltas {
                let f = file + df, r = rank + dr
                if (0..<8).contains(f) && (0..<8).contains(r) {
                    king[sq] = king[sq] | (bit(r * 8 + f))
                }
            }
            // White pawn attacks one rank up; black one rank down.
            for df in [-1, 1] {
                let f = file + df
                if (0..<8).contains(f) {
                    if rank + 1 < 8 { whitePawn[sq] = whitePawn[sq] | (bit((rank + 1) * 8 + f)) }
                    if rank - 1 >= 0 { blackPawn[sq] = blackPawn[sq] | (bit((rank - 1) * 8 + f)) }
                }
            }
        }

        self.knight = knight
        self.king = king
        self.pawn = [whitePawn, blackPawn]
    }
}

// MARK: - Magic sliders (rook / bishop)

/// One square's magic entry: the relevant-occupancy mask, the magic multiplier,
/// the right-shift, and the per-square slice of the shared attack table.
struct MagicEntry {
    var mask: Bitboard = Bitboard(0)
    var magic: Bitboard = Bitboard(0)
    var shift: UInt64 = UInt64(0)
    var attacks: [Bitboard] = []
}

struct MagicTables {
    let rook: [MagicEntry]
    let bishop: [MagicEntry]

    init() {
        self.rook = MagicTables.buildAll(isRook: true)
        self.bishop = MagicTables.buildAll(isRook: false)
    }

    // Deterministic xorshift* PRNG so magic search is reproducible.
    struct XorShift64 {
        var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            var x = state
            x = x ^ (x >> 12)
            x = x ^ (x << 25)
            x = x ^ (x >> 27)
            state = x
            return x &* 0x2545F4914F6CDD1D
        }
        // Sparse candidates (few set bits) converge to working magics fastest.
        mutating func sparse() -> UInt64 { next() & next() & next() }
    }

    /// Slow but exact ray-cast attack set for a slider, given a blocker set.
    static func slidingAttacks(square: Int, occupancy: Bitboard, isRook: Bool) -> Bitboard {
        let deltas = isRook
            ? [(0, 1), (0, -1), (1, 0), (-1, 0)]
            : [(1, 1), (1, -1), (-1, 1), (-1, -1)]
        let file = square % 8
        let rank = square / 8
        var attacks: Bitboard = Bitboard(0)
        for (df, dr) in deltas {
            var f = file + df, r = rank + dr
            while (0..<8).contains(f) && (0..<8).contains(r) {
                let s = r * 8 + f
                attacks = attacks | (bit(s))
                if occupancy & bit(s) != 0 { break }
                f += df; r += dr
            }
        }
        return attacks
    }

    /// Relevant-occupancy mask: the squares a slider's rays pass through,
    /// excluding the board edges (edges never change the attack set since the
    /// ray stops there regardless of occupancy).
    static func relevantMask(square: Int, isRook: Bool) -> Bitboard {
        let file = square % 8
        let rank = square / 8
        var mask: Bitboard = Bitboard(0)
        if isRook {
            var r = rank + 1
            while r <= 6 { mask = mask | (bit(r * 8 + file)); r += 1 }
            r = rank - 1
            while r >= 1 { mask = mask | (bit(r * 8 + file)); r -= 1 }
            var f = file + 1
            while f <= 6 { mask = mask | (bit(rank * 8 + f)); f += 1 }
            f = file - 1
            while f >= 1 { mask = mask | (bit(rank * 8 + f)); f -= 1 }
        } else {
            let deltas = [(1, 1), (1, -1), (-1, 1), (-1, -1)]
            for (df, dr) in deltas {
                var f = file + df, r = rank + dr
                while (1...6).contains(f) && (1...6).contains(r) {
                    mask = mask | (bit(r * 8 + f))
                    f += df; r += dr
                }
            }
        }
        return mask
    }

    /// Enumerate the `index`-th subset of the set bits in `mask` (carry-rippler
    /// indexing), used to enumerate every blocker configuration.
    static func occupancyForIndex(_ index: Int, mask: Bitboard) -> Bitboard {
        var result: Bitboard = Bitboard(0)
        var m = mask
        var i = 0
        let bits = popcount(mask)
        while i < bits {
            let sq = popLSB(&m)
            if index & (1 << i) != 0 { result = result | (bit(sq)) }
            i += 1
        }
        return result
    }

    /// Build all 64 entries from the EMBEDDED magics — one collision-free pass
    /// per square, no search. Fast even in unoptimized debug builds (the runtime
    /// search was catastrophically slow there).
    static func buildAll(isRook: Bool) -> [MagicEntry] {
        let magics = isRook ? rookMagics : bishopMagics
        var entries = [MagicEntry](repeating: MagicEntry(), count: 64)
        for sq in 0..<64 {
            entries[sq] = buildEntry(square: sq, isRook: isRook, magic: magics[sq])
        }
        return entries
    }

    /// Fill one square's attack table using a known-good magic (no search): a
    /// single pass over the relevant-occupancy subsets, writing each blocker
    /// configuration's true attack set at its magic-mapped index.
    static func buildEntry(square: Int, isRook: Bool, magic: Bitboard) -> MagicEntry {
        let mask = relevantMask(square: square, isRook: isRook)
        let bits = popcount(mask)
        let count = 1 << bits
        let shift = UInt64(64 - bits)
        var attacks = [Bitboard](repeating: 0, count: count)
        for i in 0..<count {
            let occ = occupancyForIndex(i, mask: mask)
            let idx = Int((occ &* magic) >> shift)
            attacks[idx] = slidingAttacks(square: square, occupancy: occ, isRook: isRook)
        }
        var entry = MagicEntry()
        entry.mask = mask
        entry.magic = magic
        entry.shift = shift
        entry.attacks = attacks
        return entry
    }

    static func buildOne(square: Int, isRook: Bool, prng: inout XorShift64) -> MagicEntry {
        let mask = relevantMask(square: square, isRook: isRook)
        let bits = popcount(mask)
        let count = 1 << bits

        // Precompute every occupancy subset and its true attack set.
        var occupancies = [Bitboard](repeating: 0, count: count)
        var reference = [Bitboard](repeating: 0, count: count)
        for i in 0..<count {
            let occ = occupancyForIndex(i, mask: mask)
            occupancies[i] = occ
            reference[i] = slidingAttacks(square: square, occupancy: occ, isRook: isRook)
        }

        let shift = UInt64(64 - bits)
        var used = [Bitboard](repeating: 0, count: count)

        // Search for a magic that maps all occupancies to collision-free
        // indices (or collisions that agree on the attack set).
        while true {
            let magic = prng.sparse()
            // Heuristic reject: magic must spread the high bits of the product.
            if popcount((mask &* magic) & 0xFF00_0000_0000_0000) < 6 { continue }

            for i in 0..<count { used[i] = 0 }
            var fail = false
            for i in 0..<count {
                let idx = Int((occupancies[i] &* magic) >> shift)
                if used[idx] == 0 {
                    used[idx] = reference[i]
                } else if used[idx] != reference[i] {
                    fail = true
                    break
                }
            }
            if !fail {
                var entry = MagicEntry()
                entry.mask = mask
                entry.magic = magic
                entry.shift = shift
                entry.attacks = used
                return entry
            }
        }
    }

    // MARK: - Embedded magics
    //
    // Precomputed by `testDumpMagics` (the runtime search in release) and pasted
    // here. Indexed by square (a1 = 0 … h8 = 63). Regenerate with:
    //   DUMP_MAGICS=1 swiftly run swift test -c release --filter testDumpMagics
    // `testEmbeddedMagicsAreCollisionFree` proves each entry is valid, so a bad
    // paste fails loudly rather than silently corrupting attack lookups.

    static let rookMagics: [Bitboard] = [
        0x008000908064C000, 0x0040200040001000, 0x0180100080A0010A, 0x8880041000800800,
        0x1200100201200804, 0x0200020004011008, 0x2180010000800600, 0x0200005088210204,
        0x0400800040008021, 0x0400400020005000, 0x8240801000200080, 0x8611001004200900,
        0x008180800C001800, 0x0100800200800400, 0x0A02000102000408, 0x8020802300104280,
        0x0080004000402000, 0xE010104000402000, 0x0800808010002000, 0xA280210008100100,
        0x0001818014000800, 0xA002010100080400, 0x0080240001020870, 0x0001020004048845,
        0x0081826280004004, 0x2020810900284000, 0x0200100080802000, 0x0200080080100080,
        0x8083080100100500, 0x4406000901000400, 0x0005020080800100, 0x0090204200008114,
        0x0010400094800420, 0x0900804000802002, 0x0201001841002000, 0x4100080080801000,
        0x4540040080800800, 0x0002001004040020, 0x0281195814001002, 0x1240800040800100,
        0x0880042000524004, 0x02C080410206002C, 0x0801200241050010, 0x8400080010008080,
        0x0008000500090010, 0x0082009084020008, 0x4012000108020004, 0x9000104D08860004,
        0x2004204114800100, 0x0148802112400300, 0x0202842000100880, 0x001B080080900080,
        0x001A002008100600, 0x0004008004020080, 0x5181000600040300, 0x0000044401128A00,
        0x8044110480002441, 0x2008110084402202, 0x90806005090010C1, 0x000420310A004A42,
        0x0023001004020801, 0x0882001008040102, 0x000230088118020C, 0x0000019025040042,
    ]

    static let bishopMagics: [Bitboard] = [
        0x0045010808008680, 0x2002080204004898, 0x0210009A10400006, 0x0824050200810200,
        0x0006061105004090, 0x00010108C0000000, 0x0814040282104004, 0x0012012201106800,
        0x10823014100C1040, 0x0080C2088802808C, 0x0281108410404000, 0x0101212041826200,
        0x0020141028221058, 0x2201020202200202, 0x000082A801482000, 0x0000008401411044,
        0x0007103014300404, 0x0002091110010100, 0x42140012040C0808, 0x0800808802004020,
        0x90C4004210140000, 0x0800200900A01000, 0x00D0400201108810, 0x80820183814412A0,
        0x00A01008202202B4, 0x01C2021A09500402, 0x0084440208042400, 0x800400400C090100,
        0xBA10040010802100, 0xD182009006005000, 0x5011021001009004, 0x0020420200510400,
        0x0292104000468800, 0x00043009091C0500, 0x0280441000020025, 0x0042820080080080,
        0x0440101010010040, 0x1000900100808080, 0x0108108120089800, 0x0044010200012682,
        0xC002500420900400, 0x0040482210710800, 0x0002060024000200, 0x0281020A44000800,
        0xA0021200A4000200, 0x0001301000840840, 0x2868500108444220, 0x0004111041000200,
        0x8044020842080200, 0x0000220104210200, 0x0000021201044000, 0x0000280884040028,
        0x4012114010858003, 0x0000081004082B88, 0x3892700508208002, 0x00220A041B060400,
        0x0812020284014881, 0x010434A282103100, 0x0490400824020800, 0x4A20002C00208800,
        0x000000A011020200, 0x4002940A02482202, 0x5100100202140406, 0x02102000840540C1,
    ]

    // MARK: - Dev-only magic search (regenerates the embedded constants)

    /// Search for one valid magic, returning just the multiplier. Used by the
    /// `testDumpMagics` dev tool to regenerate `rookMagics` / `bishopMagics`.
    static func searchOne(square: Int, isRook: Bool, prng: inout XorShift64) -> Bitboard {
        buildOne(square: square, isRook: isRook, prng: &prng).magic
    }

    /// Search all 64 magics for a slider, in the same PRNG order the original
    /// runtime search used, so the dumped constants are self-consistent.
    static func searchAll(isRook: Bool, prng: inout XorShift64) -> [Bitboard] {
        (0..<64).map { searchOne(square: $0, isRook: isRook, prng: &prng) }
    }
}

// MARK: - One-time shared singleton

/// Holds the lazily-built leaper and magic tables. Access via
/// `Magics.shared`; Swift initializes the `static let` exactly once,
/// thread-safely, on first touch.
final class Magics: @unchecked Sendable {
    static let shared = Magics()

    let leapers = LeaperTables()
    let magics = MagicTables()

    private init() {}

    @inline(__always) func knightAttacks(_ sq: Int) -> Bitboard { leapers.knight[sq] }
    @inline(__always) func kingAttacks(_ sq: Int) -> Bitboard { leapers.king[sq] }
    /// `color`: 0 = white, 1 = black.
    @inline(__always) func pawnAttacks(_ sq: Int, color: Int) -> Bitboard { leapers.pawn[color][sq] }

    @inline(__always) func rookAttacks(_ sq: Int, occupancy: Bitboard) -> Bitboard {
        let e = magics.rook[sq]
        let idx = Int(((occupancy & e.mask) &* e.magic) >> e.shift)
        return e.attacks[idx]
    }

    @inline(__always) func bishopAttacks(_ sq: Int, occupancy: Bitboard) -> Bitboard {
        let e = magics.bishop[sq]
        let idx = Int(((occupancy & e.mask) &* e.magic) >> e.shift)
        return e.attacks[idx]
    }

    @inline(__always) func queenAttacks(_ sq: Int, occupancy: Bitboard) -> Bitboard {
        rookAttacks(sq, occupancy: occupancy) | bishopAttacks(sq, occupancy: occupancy)
    }
}
