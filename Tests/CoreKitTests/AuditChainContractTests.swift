//
//  AuditChainContractTests.swift
//  CoreKitTests
//
//  Bloc 9, §21-22 — preuve du contrat d'émission d'audit.
//

import XCTest
@testable import WaanguCoreKit

/// Fige ce que l'autorité d'audit doit garantir, indépendamment de qui
/// l'implémente — simulation aujourd'hui, backend demain.
final class AuditChainContractTests: XCTestCase {

    private func event(
        id: String = UUID().lowercasedString,
        previousHash: String? = nil,
        metadata: [String: String] = [:]
    ) -> FinancialAuditEvent {
        FinancialAuditEvent(
            id: id,
            action: .mandateCreated,
            category: .mandate,
            actorID: "user-1",
            actorType: "user",
            resourceIDHash: "hash",
            correlationID: CorrelationId(),
            previousHash: previousHash,
            metadata: metadata
        )
    }

    // MARK: - L'accusé porte ce que le client ne peut pas fabriquer

    func test_acknowledgement_carriesServerEstablishedFacts() {
        let ack = AuditAcknowledgement(
            eventID: "e1", acceptedAt: Date(),
            previousHash: "p", hash: "h", sequence: 1
        )

        // Les quatre champs que le §22 réserve au serveur.
        XCTAssertEqual(ack.previousHash, "p")
        XCTAssertEqual(ack.hash, "h")
        XCTAssertEqual(ack.sequence, 1)
        XCTAssertNotNil(ack.acceptedAt)
    }

    /// Une émission ratée doit être **distinguable** d'un refus de contenu :
    /// la première se rejoue, la seconde jamais.
    func test_errors_distinguishRetryableFromPermanent() {
        XCTAssertNotEqual(
            AuditEmissionError.unreachable,
            AuditEmissionError.rejectedContent(reason: "pin")
        )

        guard case .chainMismatch(let expected) =
                AuditEmissionError.chainMismatch(expectedPrevious: "abc") else {
            return XCTFail("cas inattendu")
        }
        XCTAssertEqual(expected, "abc",
                       "Le maillon attendu doit revenir : sans lui, impossible de resynchroniser.")
    }

    /// `unreachable` ne doit jamais être confondu avec un succès. Un incident
    /// réseau qui effacerait sa propre trace est précisément ce que le §21
    /// cherche à éviter.
    func test_unavailableEmitter_failsRatherThanSilentlySucceeding() async {
        let result = await UnavailableAuditEmitter().emit(event())

        guard case .failure(let error) = result else {
            return XCTFail("Un émetteur absent ne doit pas rendre un succès")
        }
        XCTAssertEqual(error, .unreachable)
    }
}
