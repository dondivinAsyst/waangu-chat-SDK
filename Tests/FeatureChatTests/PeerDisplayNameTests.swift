import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Answers with whatever it was given, so a test can stage a payload that has
/// the key, one that doesn't, and one that has it under a different language.
private final class StubTranslationService: TranslationServiceProtocol {
    private let entries: [String: String]

    init(entries: [String: String]) { self.entries = entries }

    func resolve(key: String, module: String, args: [String]) -> TranslationResult {
        guard let value = entries[key] else {
            return TranslationResult(
                key: key, module: module, locale: activeLocale,
                value: key, resolution: .keyFallback
            )
        }
        return TranslationResult(
            key: key, module: module, locale: activeLocale,
            value: value, resolution: .module
        )
    }

    func resolveAll(keys: [String], module: String, args: [String]) -> [TranslationResult] {
        keys.map { resolve(key: $0, module: module, args: args) }
    }

    func resolveRequests(
        _ requests: [(key: String, args: [String])],
        module: String
    ) -> [TranslationResult] {
        requests.map { resolve(key: $0.key, module: module, args: $0.args) }
    }

    func updatePayload(_ payload: TranslationPayload) {}
    func updatePayload(from data: Data, using mapper: ([String: Any]) -> TranslationPayload?) {}
    func reloadPayload(for locale: String) {}
    var activePayloadVersion: Int { 1 }
    var activeLocale: String { "fr" }
}

final class PeerDisplayNameTests: XCTestCase {

    // MARK: - Identifiers are not names

    func test_accountIdIsNotAName() {
        // What the server actually sends as `displayName` when it has no name:
        // the peer's Mongo ObjectId, 24 hex characters.
        XCTAssertEqual(PeerDisplayName.sanitized("6a1fe7bc18f5cd1e344b5ab4"), "")
    }

    func test_uuidIsNotAName() {
        XCTAssertEqual(PeerDisplayName.sanitized("645a3503-ddb8-4a00-8085-da11a1b2c3d4"), "")
    }

    func test_dashedIdFragmentIsNotAName() {
        XCTAssertEqual(PeerDisplayName.sanitized("645a3503ddb88a00085-da11a"), "")
    }

    func test_candidateMatchingThisRowsOwnIdIsRejectedWhateverItLooksLike() {
        XCTAssertEqual(
            PeerDisplayName.sanitized("conv_42", identifiers: ["conv_42"]),
            ""
        )
    }

    func test_identifierComparisonIgnoresCase() {
        XCTAssertEqual(
            PeerDisplayName.sanitized("ABC123", identifiers: ["abc123"]),
            ""
        )
    }

    // MARK: - Names are left alone

    func test_ordinaryNamesSurvive() {
        XCTAssertEqual(PeerDisplayName.sanitized("Dany Lead Android"), "Dany Lead Android")
        XCTAssertEqual(PeerDisplayName.sanitized("Jakin Irisa"), "Jakin Irisa")
    }

    func test_shortHexLookingNameSurvives() {
        // "Ada" and "Bebe" are hex by spelling. Nothing that short is an id.
        XCTAssertEqual(PeerDisplayName.sanitized("Ada"), "Ada")
        XCTAssertEqual(PeerDisplayName.sanitized("Bebe"), "Bebe")
    }

    func test_multiWordNameIsNeverTreatedAsAnIdentifier() {
        XCTAssertFalse(PeerDisplayName.looksLikeIdentifier("dead beef cafe babe face"))
    }

    func test_nameWithNonHexLettersSurvivesHoweverLong() {
        XCTAssertEqual(
            PeerDisplayName.sanitized("Xhosephinaxxxxxxxxxxxxxxx"),
            "Xhosephinaxxxxxxxxxxxxxxx"
        )
    }

    func test_whitespaceIsTrimmedAndBlankIsEmpty() {
        XCTAssertEqual(PeerDisplayName.sanitized("  Sarah  "), "Sarah")
        XCTAssertEqual(PeerDisplayName.sanitized("   "), "")
        XCTAssertEqual(PeerDisplayName.sanitized(nil), "")
    }

    func test_sanitizedOrNilCollapsesEmptyToNil() {
        XCTAssertNil(PeerDisplayName.sanitizedOrNil("6a1fe7bc18f5cd1e344b5ab4"))
        XCTAssertEqual(PeerDisplayName.sanitizedOrNil("Sarah"), "Sarah")
    }

    // MARK: - The display ladder

    func test_displayFallsBackToTheNumberWhenTheNameIsAnId() {
        let text = ChatDisplayName.text(
            name: "6a1fe7bc18f5cd1e344b5ab4",
            phone: "+25761234567",
            translator: nil
        )
        XCTAssertFalse(text.contains("6a1fe7bc"))
        XCTAssertTrue(text.contains("61"), "expected the formatted number, got \(text)")
    }

    func test_displayFallsBackToUnknownWhenNothingIsUsable() {
        XCTAssertEqual(
            ChatDisplayName.text(name: nil, phone: nil, translator: nil),
            "Unknown user"
        )
        XCTAssertEqual(
            ChatDisplayName.text(name: "", phone: "", translator: nil),
            "Unknown user"
        )
    }

    func test_displayNeverShowsAnIdentifierStoredInThePhoneColumn() {
        // `upsertDirectPeerParticipant` used to key on `contact.userId.isEmpty
        // ? contact.phone : contact.userId`, so ids reached the phone column too.
        XCTAssertEqual(
            ChatDisplayName.text(
                name: nil,
                phone: "6a1fe7bc18f5cd1e344b5ab4",
                translator: nil
            ),
            "Unknown user"
        )
    }

    // MARK: - Translation

    func test_unknownUserIsTranslatedWhenThePayloadHasTheKey() {
        let french = StubTranslationService(
            entries: [ChatTranslationKeys.CHAT_UNKNOWN_USER: "Utilisateur inconnu"]
        )

        XCTAssertEqual(
            ChatDisplayName.text(name: nil, phone: nil, translator: french),
            "Utilisateur inconnu"
        )
    }

    func test_aPayloadMissingTheKeyReadsAsEnglishAndNeverAsTheKey() {
        // Payloads are served remotely, so a device on an older one has no
        // `chat_unknown_user` — and `resolve` answers a miss with the key
        // itself. Printing "chat_unknown_user" in the inbox is not an option.
        let stale = StubTranslationService(entries: [:])

        XCTAssertEqual(
            ChatDisplayName.text(name: nil, phone: nil, translator: stale),
            "Unknown user"
        )
    }

    func test_translationIsOnlyReachedWhenThereIsNothingBetterToShow() {
        let french = StubTranslationService(
            entries: [ChatTranslationKeys.CHAT_UNKNOWN_USER: "Utilisateur inconnu"]
        )

        XCTAssertEqual(
            ChatDisplayName.text(name: "Sarah", phone: nil, translator: french),
            "Sarah"
        )
        XCTAssertNotEqual(
            ChatDisplayName.text(name: nil, phone: "+25761234567", translator: french),
            "Utilisateur inconnu"
        )
    }

    func test_displayPrefersTheNameWhenThereIsOne() {
        XCTAssertEqual(
            ChatDisplayName.text(name: "Sarah", phone: "+25761234567", translator: nil),
            "Sarah"
        )
    }
}
