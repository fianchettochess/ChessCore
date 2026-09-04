import XCTest
@testable import ChessCore

/// Phase 2 of the `PieceColor`/`PieceType` serialization migration.
///
/// The type had two disagreeing spellings: `persistenceKey` says `"white"` and
/// is documented as the form to write to disk, while synthesized `Codable`
/// emitted `{"white":{}}`. Phase 1 pinned READ BOTH, WRITE THE LEGACY ONE;
/// phase 2 moved the encoder, so these tests now pin READ BOTH, WRITE THE
/// STRING FORM — the two spellings agree from here on. The legacy-decode
/// tests stay: blobs written before this release are on disk in real
/// installs and this type will keep reading them.
final class PieceCodableMigrationTests: XCTestCase {

    private func decoded<T: Decodable>(_ json: String, as: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(value), as: UTF8.self)
    }

    // MARK: - The legacy form still reads. This is the one on disk.

    func testLegacyKeyedFormDecodes() throws {
        XCTAssertEqual(try decoded(#"{"white":{}}"#, as: PieceColor.self), .white)
        XCTAssertEqual(try decoded(#"{"black":{}}"#, as: PieceColor.self), .black)
        XCTAssertEqual(try decoded(#"{"knight":{}}"#, as: PieceType.self), .knight)
        XCTAssertEqual(try decoded(#"{"king":{}}"#, as: PieceType.self), .king)
    }

    func testLegacyNestedInAPieceDecodes() throws {
        let piece = try decoded(
            #"{"color":{"black":{}},"type":{"rook":{}}}"#, as: Piece.self
        )
        XCTAssertEqual(piece, Piece(type: .rook, color: .black))
    }

    // MARK: - The forward form reads too, ahead of anything writing it.

    func testBareStringFormDecodes() throws {
        XCTAssertEqual(try decoded(#""white""#, as: PieceColor.self), .white)
        XCTAssertEqual(try decoded(#""black""#, as: PieceColor.self), .black)
        for expected in [PieceType.king, .queen, .rook, .bishop, .knight, .pawn] {
            XCTAssertEqual(
                try decoded("\"\(expected.persistenceKey)\"", as: PieceType.self),
                expected
            )
        }
    }

    func testBareStringNestedInAPieceDecodes() throws {
        let piece = try decoded(#"{"color":"white","type":"pawn"}"#, as: Piece.self)
        XCTAssertEqual(piece, Piece(type: .pawn, color: .white))
    }

    /// The decoder accepts a payload that mixes the two, because a blob written
    /// across the migration boundary can legitimately contain both.
    func testMixedFormsDecodeInOnePayload() throws {
        let piece = try decoded(#"{"color":"black","type":{"queen":{}}}"#, as: Piece.self)
        XCTAssertEqual(piece, Piece(type: .queen, color: .black))
    }

    // MARK: - The encoder now writes the string form. Phase 2, landed.

    func testEncoderNowEmitsTheStringForm() throws {
        XCTAssertEqual(try encoded(PieceColor.white), #""white""#)
        XCTAssertEqual(try encoded(PieceColor.black), #""black""#)
        XCTAssertEqual(try encoded(PieceType.knight), #""knight""#)
        XCTAssertEqual(
            try encoded(Piece(type: .knight, color: .white)),
            #"{"color":"white","type":"knight"}"#
        )
    }

    /// Every value survives its own encoder, which is what stops a phase-2
    /// change from silently breaking the pairing.
    func testRoundTripThroughTheShippedEncoder() throws {
        for color in [PieceColor.white, .black] {
            XCTAssertEqual(try decoded(try encoded(color), as: PieceColor.self), color)
        }
        for type in [PieceType.king, .queen, .rook, .bishop, .knight, .pawn] {
            XCTAssertEqual(try decoded(try encoded(type), as: PieceType.self), type)
        }
    }

    // MARK: - The two spellings now agree, which is the whole point.

    func testPersistenceKeyIsTheStringFormTheDecoderAccepts() throws {
        for color in [PieceColor.white, .black] {
            XCTAssertEqual(
                try decoded("\"\(color.persistenceKey)\"", as: PieceColor.self),
                color
            )
        }
    }

    // MARK: - Refusals stay loud.

    func testUnknownValuesThrowRatherThanDefaulting() {
        XCTAssertThrowsError(try decoded(#""purple""#, as: PieceColor.self))
        XCTAssertThrowsError(try decoded(#"{"purple":{}}"#, as: PieceColor.self))
        XCTAssertThrowsError(try decoded(#""archbishop""#, as: PieceType.self))
        XCTAssertThrowsError(try decoded(#"{}"#, as: PieceColor.self))
        XCTAssertThrowsError(try decoded(#"42"#, as: PieceColor.self))
    }
}
