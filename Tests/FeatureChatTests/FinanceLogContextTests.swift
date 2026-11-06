//
//  FinanceLogContextTests.swift
//  FeatureChatTests
//
//  Tâches 2.3 et 9.5 — rien d'identifiant ne doit pouvoir atteindre les logs.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinanceLogContextTests: XCTestCase {

    // MARK: - Hachage

    /// L'identifiant brut ne doit être accessible nulle part, y compris en
    /// interpolant la structure entière — c'est ce qui rend la faute impossible
    /// plutôt qu'interdite par convention.
    func test_rawIdentifierIsNeverExposed() {
        let context = FinanceLogContext(
            correlationID: CorrelationId(value: "corr-1"),
            financialObjectID: "objet-tres-secret-42",
            operation: "confirm"
        )

        XCTAssertFalse("\(context)".contains("objet-tres-secret-42"))
        XCTAssertFalse(context.fields.values.contains("objet-tres-secret-42"))
        XCTAssertNotNil(context.financialObjectIDHash)
    }

    /// Le hachage doit être stable entre appareils et sessions, sinon deux logs
    /// du même objet ne se recoupent pas — ce qui est leur seule raison d'être.
    func test_hashIsStableAcrossInstances() {
        let a = FinanceLogContext(correlationID: CorrelationId(), financialObjectID: "x", operation: "o")
        let b = FinanceLogContext(correlationID: CorrelationId(), financialObjectID: "x", operation: "o")
        XCTAssertEqual(a.financialObjectIDHash, b.financialObjectIDHash)
    }

    func test_differentIdentifiersHashDifferently() {
        let a = FinanceLogContext(correlationID: CorrelationId(), financialObjectID: "x", operation: "o")
        let b = FinanceLogContext(correlationID: CorrelationId(), financialObjectID: "y", operation: "o")
        XCTAssertNotEqual(a.financialObjectIDHash, b.financialObjectIDHash)
    }

    /// Avant qu'un objet n'existe, il n'y a rien à hacher — et la clé est omise
    /// plutôt que rendue `"nil"`, qui se confondrait avec une valeur.
    func test_absentIdentifierOmitsTheField() {
        let context = FinanceLogContext(
            correlationID: CorrelationId(value: "c"),
            financialObjectID: nil,
            operation: "create"
        )
        XCTAssertNil(context.financialObjectIDHash)
        XCTAssertNil(context.fields["fin_object"])
        XCTAssertEqual(context.fields["operation"], "create")
    }

    /// Construit depuis une référence, le contexte ne peut pas diverger de l'objet.
    func test_contextFromReferenceCarriesTypeAndVersion() {
        let context = FinanceLogContext(
            reference: FinanceFixtures.reference(type: .refund, id: "r-1", version: 7),
            operation: "refresh"
        )
        XCTAssertEqual(context.objectType, .refund)
        XCTAssertEqual(context.objectVersion, 7)
        XCTAssertEqual(context.fields["fin_version"], "7")
        XCTAssertFalse("\(context)".contains("r-1"))
    }

    // MARK: - Deep links

    /// Le défaut du §3.4 : `AppCoordinator` journalisait l'URL complète, donc
    /// l'identifiant d'objet financier, dans les sysdiagnose et les crash reports.
    func test_deepLinkIdentifierIsRedacted() {
        let url = URL(string: "waangu://chat/financial-object/abc123?token=xyz")!
        let redacted = FinanceLogContext.redactedURL(url)

        XCTAssertFalse(redacted.contains("abc123"))
        XCTAssertFalse(redacted.contains("xyz"))
        XCTAssertFalse(redacted.contains("token"))
        // Le routage reste lisible : c'est ce qu'on veut réellement déboguer.
        XCTAssertTrue(redacted.contains("financial-object"))
        XCTAssertTrue(redacted.contains("chat"))
    }

    func test_conversationIdentifierIsRedactedToo() {
        let url = URL(string: "waangu://chat/conversation/conv-secret-99")!
        let redacted = FinanceLogContext.redactedURL(url)
        XCTAssertFalse(redacted.contains("conv-secret-99"))
        XCTAssertTrue(redacted.contains("conversation"))
    }

    func test_hostOnlyURLSurvives() {
        let url = URL(string: "waangu://chat")!
        XCTAssertEqual(FinanceLogContext.redactedURL(url), "waangu://chat")
    }

    /// Aucune URL ne doit faire lever la rédaction — elle s'exécute sur un chemin
    /// de navigation, où une exception serait pire que le log.
    func test_redactionNeverCrashes() {
        let urls = ["waangu://", "x://y/z/", "waangu://chat/a/b/c/d/e"]
        for raw in urls {
            guard let url = URL(string: raw) else { continue }
            XCTAssertFalse(FinanceLogContext.redactedURL(url).isEmpty)
        }
    }
}
