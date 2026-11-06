//
//  FinancialCardRegistryTests.swift
//  FeatureChatTests
//
//  Tâche 10.4 — un type non enregistré ne casse jamais le fil.

import XCTest
import SwiftUI
@testable import WaanguFeatureChat
import WaanguCoreKit

@MainActor
final class FinancialCardRegistryTests: XCTestCase {

    override func setUp() async throws {
        FinancialCardRegistry.reset()
    }

    override func tearDown() async throws {
        FinancialCardRegistry.reset()
    }

    private func payload(_ type: FinancialObjectType) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(type: type),
            status: .confirmed,
            amount: 1500,
            currency: "BIF"
        )
    }

    /// Le contrat central : un type inconnu produit une carte, pas un vide ni un crash.
    func test_unregisteredTypeFallsBackWithoutCrashing() {
        let view = FinancialCardRegistry.view(for: payload(.dispute))
        XCTAssertNotNil(view)
    }

    func test_registeredTypeUsesItsRenderer() {
        FinancialCardRegistry.register(.refund) { _ in AnyView(Text("remboursement")) }
        XCTAssertEqual(FinancialCardRegistry.registeredCount, 1)
        XCTAssertNotNil(FinancialCardRegistry.view(for: payload(.refund)))
    }

    func test_reregisteringReplacesRenderer() {
        FinancialCardRegistry.register(.payment) { _ in AnyView(Text("a")) }
        FinancialCardRegistry.register(.payment) { _ in AnyView(Text("b")) }
        XCTAssertEqual(FinancialCardRegistry.registeredCount, 1)
    }

    /// Les cartes livrées avec le Bloc 1 doivent s'enregistrer sans exception,
    /// et l'appel doit être idempotent — il a lieu au montage du module.
    func test_builtInRegistrationIsIdempotent() {
        FinancialCardRegistry.registerBuiltInCards()
        let first = FinancialCardRegistry.registeredCount
        FinancialCardRegistry.registerBuiltInCards()
        XCTAssertEqual(FinancialCardRegistry.registeredCount, first)
        XCTAssertGreaterThan(first, 0)
    }

    /// Chaque type doit produire une vue, enregistré ou non.
    func test_everyObjectTypeResolvesToSomething() {
        FinancialCardRegistry.registerBuiltInCards()
        for type in FinancialObjectType.allCases {
            XCTAssertNotNil(FinancialCardRegistry.view(for: payload(type)), "\(type) sans vue")
        }
    }
}
