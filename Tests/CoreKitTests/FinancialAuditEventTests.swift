//
//  FinancialAuditEventTests.swift
//  CoreKitTests
//
//  Bloc 9, G9-05 — preuve (niveau 6) des champs de corrélation et de la redaction.
//

import XCTest
@testable import WaanguCoreKit

final class FinancialAuditEventTests: XCTestCase {

    private func makeEvent(
        metadata: [String: String] = [:],
        causationID: String? = nil,
        previousHash: String? = nil
    ) -> FinancialAuditEvent {
        FinancialAuditEvent(
            action: .mandateCreated,
            category: .mandate,
            actorID: "user-1",
            actorType: "user",
            resourceIDHash: "hash",
            correlationID: CorrelationId(),
            causationID: causationID,
            previousHash: previousHash,
            metadata: metadata
        )
    }

    // MARK: - Identifiant

    /// La convention du projet est le minuscule partout. `UUID.uuidString` rend
    /// des majuscules ; un identifiant émis dans les deux casses produit deux
    /// chaînes qui ne comparent jamais égal — donc des événements d'audit qui ne
    /// se corrèlent pas, ce qui vide le journal de sa seule raison d'être.
    func test_id_isLowercase() {
        let event = makeEvent()

        XCTAssertEqual(event.id, event.id.lowercased(),
                       "L'identifiant d'audit doit être en minuscules")
        XCTAssertNotNil(UUID(uuidString: event.id), "…tout en restant un UUID valide")
    }

    func test_id_isUniquePerEvent() {
        XCTAssertNotEqual(makeEvent().id, makeEvent().id)
    }

    // MARK: - Redaction

    /// Le filtre est dans le constructeur, pas au site d'appel : un journal
    /// d'audit se lit après incident, quand plus personne ne relit les appelants.
    func test_metadata_dropsForbiddenKeys() {
        let event = makeEvent(metadata: [
            "pin": "1234",
            "otp": "999888",
            "token": "eyJ...",
            "cvv": "123",
            "pan": "4111111111111111",
            "amount": "5000"
        ])

        XCTAssertNil(event.metadata["pin"])
        XCTAssertNil(event.metadata["otp"])
        XCTAssertNil(event.metadata["token"])
        XCTAssertNil(event.metadata["cvv"])
        XCTAssertNil(event.metadata["pan"])
        XCTAssertEqual(event.metadata["amount"], "5000",
                       "Une clé non sensible doit survivre au filtre")
    }

    /// Le filtre compare en minuscules : « PIN » et « Token » doivent tomber
    /// aussi. Un filtre sensible à la casse se contourne en changeant une
    /// majuscule, ce qui n'est pas une protection.
    func test_metadata_forbiddenKeysAreCaseInsensitive() {
        let event = makeEvent(metadata: ["PIN": "1234", "Token": "x", "CVV": "1"])

        XCTAssertTrue(event.metadata.isEmpty,
                      "Le filtre doit être insensible à la casse")
    }

    // MARK: - Corrélation

    /// L'horodatage serveur est absent tant que l'événement n'a pas été accepté.
    /// Le fabriquer côté client reviendrait à signer une preuve avec l'outil
    /// qu'on cherche à contrôler.
    func test_serverTimestamp_isAbsentUntilAccepted() {
        XCTAssertNil(makeEvent().occurredAtServer)
        XCTAssertNotNil(makeEvent().occurredAtClient)
    }

    /// La causation est distincte de la corrélation : l'une regroupe, l'autre
    /// ordonne. Sans causation, une chaîne d'actions ne se reconstitue pas.
    func test_causationIsSeparateFromCorrelation() {
        let event = makeEvent(causationID: "parent-event")

        XCTAssertEqual(event.causationID, "parent-event")
        XCTAssertNotEqual(event.causationID, event.correlationID.value)
    }

    /// Le chaînage est transporté, jamais calculé localement : le §22 place la
    /// chaîne côté serveur, parce qu'une chaîne calculée sur l'appareil est
    /// réécrivable en entier par qui contrôle l'appareil.
    func test_previousHash_isCarriedNotComputed() {
        XCTAssertNil(makeEvent().previousHash,
                     "Aucune empreinte ne doit être fabriquée côté client")
        XCTAssertEqual(makeEvent(previousHash: "abc").previousHash, "abc")
    }
}
