//
//  SequenceGuardTests.swift
//  CoreKitTests
//
//  Bloc 8, P0-8 (§15) — preuve des quatre règles de séquence.
//

import XCTest
@testable import WaanguCoreKit

/// `SequenceGuard` portait les quatre règles du §15 sans aucun test et sans
/// appelant. Les figer ici avant de le câbler : une règle non testée qu'on
/// branche dans un chemin de synchronisation se découvre en production.
final class SequenceGuardTests: XCTestCase {

    private func verdict(_ incoming: Int64, last: Int64?,
                         id: String = "e", seen: Set<String> = []) -> SequenceVerdict {
        SequenceGuard.verdict(incoming: incoming, lastApplied: last,
                              eventID: id, seenEventIDs: seen)
    }

    // MARK: - Les quatre règles

    func test_nextSequenceIsApplied() {
        XCTAssertEqual(verdict(5, last: 4), .apply)
    }

    /// Le défaut central : un rang sauté doit être **signalé**, pas appliqué.
    func test_missingSequenceIsGap() {
        XCTAssertEqual(verdict(7, last: 4), .gap(expected: 5, received: 7))
    }

    func test_sameSequenceIsDuplicate() {
        XCTAssertEqual(verdict(4, last: 4), .duplicate)
    }

    func test_olderSequenceIsStale() {
        XCTAssertEqual(verdict(2, last: 4), .stale)
    }

    // MARK: - Précédences

    /// La déduplication par identifiant précède la position : un même événement
    /// arrivé par MQTT **et** par l'API porte la même séquence, et ce n'est pas
    /// un trou.
    func test_knownEventIDIsDuplicateEvenWhenSequenceLooksLikeAGap() {
        XCTAssertEqual(
            verdict(99, last: 4, id: "already", seen: ["already"]),
            .duplicate,
            "L'identifiant déjà vu doit primer sur le raisonnement de position."
        )
    }

    /// Sans état local, aucun trou n'est jugeable : la synchro initiale établit
    /// la base, et refuser ici bloquerait tout premier démarrage.
    func test_noLocalStateAccepts() {
        XCTAssertEqual(verdict(42, last: nil), .apply)
    }

    /// Une position nulle ou négative n'est pas interprétable : requêter
    /// l'autorité plutôt que deviner.
    func test_nonPositiveSequenceRequeries() {
        XCTAssertEqual(verdict(0, last: 4), .requery)
        XCTAssertEqual(verdict(-1, last: 4), .requery)
    }

    /// Seul `apply` autorise l'application. Si cette propriété devenait vraie
    /// pour `gap`, un trou serait franchi en silence.
    func test_onlyApplyPermitsApplication() {
        XCTAssertTrue(SequenceVerdict.apply.permitsApplication)
        XCTAssertFalse(SequenceVerdict.duplicate.permitsApplication)
        XCTAssertFalse(SequenceVerdict.stale.permitsApplication)
        XCTAssertFalse(SequenceVerdict.requery.permitsApplication)
        XCTAssertFalse(SequenceVerdict.gap(expected: 5, received: 7).permitsApplication)
    }
}
