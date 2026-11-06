import Testing
import Foundation
@testable import WaanguCoreKit

/// Fraîcheur de projection et états techniques EIG — Waangu 360 §5, §10.
@Suite("Bloc 11 — fraîcheur des projections et états EIG")
struct Bloc11ProjectionAndIntegrationStateTests {

    private func decode<T: Decodable>(_ type: T.Type, _ raw: String) throws -> T {
        try JSONDecoder().decode(type, from: Data("\"\(raw)\"".utf8))
    }

    @Test("Seul CURRENT se présente comme à jour")
    func onlyCurrentIsCurrent() {
        for state in ProjectionFreshness.allCases {
            #expect(state.mayBePresentedAsCurrent == (state == .current))
        }
    }

    @Test("Une fraîcheur inconnue devient UNKNOWN, jamais CURRENT")
    func unknownFreshnessNeverCurrent() throws {
        let value = try decode(ProjectionFreshness.self, "FUTURE_STATE")
        #expect(value == .unknown)
        #expect(!value.mayBePresentedAsCurrent)
    }

    @Test("Aucun état EIG n'implique d'issue financière")
    func eigStateNeverImpliesPayment() {
        for state in EIGTechnicalState.allCases {
            #expect(state.impliedPaymentStatus == nil)
        }
    }

    @Test("EIG_ACKNOWLEDGED n'est pas un paiement abouti")
    func acknowledgedIsNotPaid() {
        #expect(EIGTechnicalState.acknowledged.impliedPaymentStatus != .completed)
        #expect(EIGTechnicalState.acknowledged.impliedPaymentStatus != .confirmed)
    }

    @Test("Timeout et état inconnu laissent l'effet externe inconnu")
    func timeoutLeavesEffectUnknown() throws {
        #expect(EIGTechnicalState.timeout.externalEffectIsUnknown)
        #expect(try decode(EIGTechnicalState.self, "EIG_NEW").externalEffectIsUnknown)
        #expect(!EIGTechnicalState.callbackReceived.externalEffectIsUnknown)
    }

    @Test("Les valeurs EIG se décodent depuis leur identifiant contractuel")
    func eigDecodesContractIdentifiers() throws {
        #expect(try decode(EIGTechnicalState.self, "EIG_TIMEOUT") == .timeout)
        #expect(try decode(EIGTechnicalState.self, "EIG_CALLBACK_RECEIVED") == .callbackReceived)
    }
}
