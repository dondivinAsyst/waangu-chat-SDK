//
//  FinancialReferenceVersionTests.swift
//  FeatureChatTests
//
//  Tâche 10.1 — la politique de résolution de conflit.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinancialReferenceVersionTests: XCTestCase {

    private func ref(_ version: Int, id: String = "obj-1", type: FinancialObjectType = .payment) -> FinancialReference {
        FinancialReference(type: type, id: id, version: version, correlationID: CorrelationId(value: "c"))
    }

    // MARK: - supersedes

    func test_higherVersionSupersedes() {
        XCTAssertTrue(ref(9).supersedes(ref(8)))
    }

    /// L'égalité doit être refusée : un événement rejoué porte la même version que
    /// celui déjà appliqué, et le réappliquer relance les effets de bord.
    func test_equalVersionDoesNotSupersede() {
        XCTAssertFalse(ref(9).supersedes(ref(9)))
    }

    func test_lowerVersionDoesNotSupersede() {
        XCTAssertFalse(ref(8).supersedes(ref(9)))
    }

    /// Une version supérieure sur un **autre** objet ne remplace rien.
    /// Sans ce contrôle, un objet quelconque à version élevée écraserait tous les autres.
    func test_differentObjectNeverSupersedes() {
        XCTAssertFalse(ref(99, id: "obj-2").supersedes(ref(1, id: "obj-1")))
    }

    /// Même identifiant, type différent : deux objets distincts.
    func test_differentTypeNeverSupersedes() {
        XCTAssertFalse(ref(99, type: .refund).supersedes(ref(1, type: .payment)))
    }

    func test_identityIgnoresVersion() {
        XCTAssertTrue(ref(1).identifies(ref(42)))
        XCTAssertEqual(ref(1).identityKey, ref(42).identityKey)
    }

    /// La description ne doit jamais contenir l'identifiant brut : elle finit dans
    /// les logs.
    func test_descriptionOmitsRawIdentifier() {
        let reference = ref(3, id: "super-secret-object-id")
        XCTAssertFalse(reference.description.contains("super-secret-object-id"))
        XCTAssertTrue(reference.description.contains("v3"))
    }
}
