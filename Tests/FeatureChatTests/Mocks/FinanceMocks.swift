//
//  FinanceMocks.swift
//  FeatureChatTests
//
//  Doublures des contrats financiers CoreKit — tâche 3.6.
//
//  Permettent de tester toute la surface financière du Chat sans backend :
//  c'est la condition pour que les phases 4 à 8 soient vérifiables avant que les
//  contrats du §15 ne soient livrés.

import Foundation
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - FinanceAPIClient

/// Client financier scriptable.
///
/// Enregistre les appels reçus, ce qui permet de vérifier ce que les tests de
/// chaos exigent réellement : qu'un double tap ne produise qu'un appel, qu'un
/// retry réutilise la même clé, qu'un timeout ne déclenche pas de seconde
/// soumission.
actor MockFinanceAPIClient: FinanceAPIClientProtocol {

    struct Call: Equatable {
        let operation: String
        let objectID: String
        let idempotencyKey: String?
    }

    private(set) var calls: [Call] = []

    var capabilitiesResult: FinanceCapabilities = .none
    var objectResult: Result<PaymentEnvelope, FinanceError> = .failure(.timeoutUnknown)
    var createResult: Result<PaymentEnvelope, FinanceError>?
    var confirmResult: Result<PaymentEnvelope, FinanceError>?

    func setCapabilities(_ value: FinanceCapabilities) { capabilitiesResult = value }
    func setObjectResult(_ value: Result<PaymentEnvelope, FinanceError>) { objectResult = value }
    func setCreateResult(_ value: Result<PaymentEnvelope, FinanceError>) { createResult = value }
    func setConfirmResult(_ value: Result<PaymentEnvelope, FinanceError>) { confirmResult = value }

    var callCount: Int { calls.count }
    func callCount(for operation: String) -> Int {
        calls.filter { $0.operation == operation }.count
    }

    func capabilities() async throws -> FinanceCapabilities {
        capabilitiesResult
    }

    func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
        calls.append(.init(operation: "get", objectID: reference.id, idempotencyKey: nil))
        return try objectResult.get()
    }

    func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        calls.append(.init(operation: "refresh", objectID: reference.id, idempotencyKey: nil))
        return try objectResult.get()
    }

    func createPaymentIntent(
        _ request: CreatePaymentIntentRequest,
        idempotency: IdempotencyContext
    ) async throws -> PaymentEnvelope {
        calls.append(.init(
            operation: "create",
            objectID: request.recipientID,
            idempotencyKey: idempotency.key
        ))
        return try (createResult ?? objectResult).get()
    }

    func confirmPaymentIntent(
        reference: FinancialReference,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async throws -> PaymentEnvelope {
        calls.append(.init(
            operation: "confirm",
            objectID: reference.id,
            idempotencyKey: idempotency.key
        ))
        return try (confirmResult ?? objectResult).get()
    }
}

// MARK: - Capacités

struct MockFinanceCapabilityProvider: FinanceCapabilityProviding {
    let value: FinanceCapabilities
    init(_ value: FinanceCapabilities) { self.value = value }
    func capabilities() async -> FinanceCapabilities { value.effective() }
    func invalidate() async {}
}

// MARK: - Idempotence

/// Préserveur en mémoire, avec compteur de violations.
actor MockIdempotencyPreserver: IdempotencyKeyPreserving {

    private var contexts: [String: IdempotencyContext] = [:]
    private(set) var mismatchCount = 0

    func register(operationID: String, context: IdempotencyContext) async throws {
        if let existing = contexts[operationID], existing.key != context.key {
            throw IdempotencyViolation.alreadyRegistered(operationID: operationID)
        }
        contexts[operationID] = context
    }

    func context(for operationID: String) async -> IdempotencyContext? {
        contexts[operationID]
    }

    func assertSameKey(operationID: String, providedKey: String) async throws {
        guard let stored = contexts[operationID] else {
            throw IdempotencyViolation.keyMismatch(operationID: operationID)
        }
        guard stored.key == providedKey else {
            mismatchCount += 1
            throw IdempotencyViolation.keyMismatch(operationID: operationID)
        }
    }

    /// Comptes purgés, pour que les tests puissent vérifier que la purge a bien
    /// visé l'identifiant porté par l'événement de logout.
    private(set) var purgedUserIDs: [String] = []

    func purge(userID: String) async {
        purgedUserIDs.append(userID)
        contexts.removeAll()
    }

    func release(operationID: String) async {
        contexts.removeValue(forKey: operationID)
    }
}

// MARK: - Step-up

struct MockStepUpAuthenticator: StepUpAuthenticating {

    var level: StepUpLevel = .biometric
    var outcome: Result<StepUpAttestation, StepUpError>?

    var currentLevel: StepUpLevel { get async { .none } }

    func elevate(to level: StepUpLevel) async throws -> Bool {
        if case .failure(let error) = outcome { throw error }
        return true
    }

    func satisfyStepUp(
        level: StepUpLevel,
        reason: String,
        correlationID: CorrelationId,
        deviceID: String
    ) async throws -> StepUpAttestation {
        if let outcome { return try outcome.get() }
        return StepUpAttestation(
            level: level,
            correlationID: correlationID,
            deviceID: deviceID
        )
    }
}

// MARK: - Signature

/// Vérificateur scriptable — permet de tester les trois verdicts.
struct MockSignatureVerifier: FinancialSignatureVerifying {
    var verdict: FinancialSignatureVerdict = .authentic
    var operational = true

    func isOperational() async -> Bool { operational }

    func verify(
        signature: String,
        over payload: FinancialSignaturePayload
    ) async -> FinancialSignatureVerdict {
        verdict
    }
}

// MARK: - Risque de session

struct MockSessionRiskEvaluator: SessionRiskEvaluating {
    var assessment: SessionRiskAssessment

    init(requiredStepUp: StepUpLevel = .none, score: Double = 0) {
        self.assessment = SessionRiskAssessment(
            score: score,
            requiredStepUp: requiredStepUp,
            signals: [],
            evaluatedAt: Date()
        )
    }

    var riskStream: AsyncStream<SessionRiskAssessment> { AsyncStream { $0.finish() } }

    func evaluate(for operation: String, amount: Decimal?) async -> SessionRiskAssessment {
        assessment
    }
}

// MARK: - Fabriques

enum FinanceFixtures {

    static func reference(
        type: FinancialObjectType = .payment,
        id: String = "obj-1",
        version: Int = 1
    ) -> FinancialReference {
        FinancialReference(
            type: type,
            id: id,
            version: version,
            // Volontairement **non** dérivée de `id` : une corrélation construite
            // à partir de l'identifiant rendrait tout test de non-fuite vain,
            // puisque la chaîne contiendrait l'identifiant par construction.
            correlationID: CorrelationId(value: "corr-fixture")
        )
    }

    static func idempotency(key: String = "key-1") -> IdempotencyContext {
        IdempotencyContext(
            key: key,
            clientRequestID: UUID(),
            correlationID: CorrelationId(value: "corr-1"),
            deviceID: "device-1"
        )
    }

    static func envelope(
        id: String = "obj-1",
        status: PaymentStatus = .confirmed,
        amount: Decimal = 1000,
        signature: String = String(repeating: "a", count: 64),
        withRailProof: Bool = true,
        /// Révision rendue par le backend. `"n/a"` simule le contrat #2 non
        /// livré : aucune révision exploitable, donc aucune autorité.
        version: String = "1"
    ) -> PaymentEnvelope {
        PaymentEnvelope(
            id: id,
            paymentType: .p2p,
            amount: amount,
            currency: "BIF",
            timestamp: Date(),
            status: status,
            senderId: "sender-1",
            recipientId: "recipient-1",
            merchantId: nil,
            backendSignature: signature,
            railProof: RailProof(
                railProvider: withRailProof ? "brb" : "",
                railTransactionId: withRailProof ? "rail-1" : "",
                railSignature: withRailProof ? String(repeating: "b", count: 64) : "",
                railTimestamp: Date(),
                railStatus: "OK",
                railMetadata: [:]
            ),
            evidenceRefs: [],
            version: version,
            idempotencyKey: "key-1",
            correlationId: "corr-1",
            description: nil,
            metadata: [:],
            feeAmount: nil,
            feeCurrency: nil,
            exchangeRate: nil,
            crossBorder: false
        )
    }

    /// Catalogue ouvert en lecture seule — le périmètre P0 du Bloc 1.
    static let readOnlyCapabilities = FinanceCapabilities(
        viewFinancialCards: true,
        context: FinanceCapabilityContext(channel: "test", appVersion: "1.0")
    )

    static let testContext = FinanceCapabilityContext(channel: "test", appVersion: "1.0")
}
