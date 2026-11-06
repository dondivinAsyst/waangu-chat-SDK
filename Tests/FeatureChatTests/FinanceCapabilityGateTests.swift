//
//  FinanceCapabilityGateTests.swift
//  FeatureChatTests
//
//  Tâches 10.5 et 10.15 — le catalogue est fermé par défaut.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinanceCapabilityGateTests: XCTestCase {

    /// Un catalogue construit sans argument n'ouvre rien.
    func test_defaultCapabilitiesAreClosed() {
        let caps = FinanceCapabilities.none
        XCTAssertFalse(caps.sendMoney)
        XCTAssertFalse(caps.viewFinancialCards)
        XCTAssertFalse(caps.allowsAnyOutgoingOperation)
    }

    /// Une clé absente du JSON vaut `false`, et ne fait pas perdre tout le catalogue.
    func test_missingKeysDecodeToFalseWithoutLosingOthers() throws {
        let json = Data(#"{"sendMoney": true}"#.utf8)
        let caps = try JSONDecoder().decode(FinanceCapabilities.self, from: json)

        XCTAssertTrue(caps.sendMoney)
        XCTAssertFalse(caps.qrPayment)
        XCTAssertFalse(caps.remittance)
    }

    /// Un JSON entièrement inconnu ne doit pas ouvrir de capacité.
    func test_unknownPayloadOpensNothing() throws {
        let json = Data(#"{"somethingElse": true}"#.utf8)
        let caps = try JSONDecoder().decode(FinanceCapabilities.self, from: json)
        XCTAssertFalse(caps.allowsAnyOutgoingOperation)
        XCTAssertFalse(caps.viewFinancialCards)
    }

    /// Un catalogue expiré vaut `.none` — il ne se prolonge pas hors ligne.
    func test_expiredCatalogueIsClosed() {
        let expired = FinanceCapabilities(
            sendMoney: true,
            viewFinancialCards: true,
            context: FinanceFixtures.testContext,
            expiresAt: Date().addingTimeInterval(-1)
        )
        XCTAssertFalse(expired.isValid())
        XCTAssertFalse(expired.effective().sendMoney)
        XCTAssertFalse(expired.effective().viewFinancialCards)
    }

    func test_validCatalogueSurvivesEffective() {
        let valid = FinanceCapabilities(
            viewFinancialCards: true,
            context: FinanceFixtures.testContext,
            expiresAt: Date().addingTimeInterval(3600)
        )
        XCTAssertTrue(valid.effective().viewFinancialCards)
    }

    /// Un contexte non résolu ne correspond à rien — pas même à lui-même — pour
    /// qu'un catalogue jamais résolu ne soit jamais réutilisé.
    func test_unknownContextNeverMatches() {
        XCTAssertFalse(FinanceCapabilityContext.unknown.matches(.unknown))
        XCTAssertFalse(FinanceFixtures.testContext.matches(.unknown))
    }

    /// Changement de pays : le catalogue précédent ne s'applique plus.
    func test_contextChangeInvalidatesMatch() {
        let burundi = FinanceCapabilityContext(country: "BI", channel: "ios", appVersion: "1.0")
        let rwanda  = FinanceCapabilityContext(country: "RW", channel: "ios", appVersion: "1.0")
        XCTAssertFalse(burundi.matches(rwanda))
        XCTAssertTrue(burundi.matches(burundi))
    }

    /// Le repli injecté par défaut dans `ChatDependencies` n'ouvre rien.
    func test_closedProviderOpensNothing() async {
        let provider = ClosedFinanceCapabilities()
        let canRender = await provider.canRenderFinancialCards()
        let canInitiate = await provider.canInitiateFromComposer()
        XCTAssertFalse(canRender)
        XCTAssertFalse(canInitiate)
    }

    /// Lecture et émission sont dissociées : un marché peut autoriser la
    /// réception d'un paiement sans en autoriser l'émission.
    func test_readOnlyCatalogueDoesNotAllowOutgoing() async {
        let provider = MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities)
        let canRender = await provider.canRenderFinancialCards()
        let canInitiate = await provider.canInitiateFromComposer()
        XCTAssertTrue(canRender)
        XCTAssertFalse(canInitiate)
    }
}
