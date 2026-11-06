//
//  FinanceAPIClient.swift
//  DomainKit
//
//  Implémentation de `FinanceAPIClientProtocol` sur le pipeline transactionnel
//  existant — tâche 3.2.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §6.

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

/// Accès aux objets financiers, adossé au pipeline `TransactionStep`.
///
/// **Aucun second pipeline.** `check → request → confirm → verify` est déjà en
/// production côté Wallet ; le Chat consomme le même. Un pipeline parallèle
/// dériverait au premier changement de contrat backend, et il y aurait deux
/// endroits où l'idempotence pourrait se perdre.
///
/// Placé dans DomainKit et non SecurityKit : `TransactionGatewayProtocol` y vit,
/// et SecurityKit ne dépend pas de DomainKit.
public final class FinanceAPIClient: FinanceAPIClientProtocol {

    private let gateway: any TransactionGatewayProtocol
    private let capabilityResolver: any FinanceCapabilityProviding
    private let logger: AppLogger

    public init(
        gateway: any TransactionGatewayProtocol,
        capabilityResolver: any FinanceCapabilityProviding,
        logger: AppLogger
    ) {
        self.gateway = gateway
        self.capabilityResolver = capabilityResolver
        self.logger = logger
    }

    // MARK: - Capacités

    public func capabilities() async throws -> FinanceCapabilities {
        await capabilityResolver.capabilities()
    }

    // MARK: - Lecture

    public func financialObject(for reference: FinancialReference) async throws -> PaymentEnvelope {
        try await fetch(reference, step: .check, operation: "financial_object")
    }

    public func refresh(_ reference: FinancialReference) async throws -> PaymentEnvelope {
        // Même étape, sémantique différente : `verify` est l'étape que le backend
        // expose pour donner l'état courant sans effet de bord. C'est celle de la
        // réconciliation.
        try await fetch(reference, step: .verify, operation: "refresh")
    }

    private func fetch(
        _ reference: FinancialReference,
        step: TransactionStep,
        operation: String
    ) async throws -> PaymentEnvelope {
        let request = FinancialObjectRequestDTO(
            objectType: reference.type.rawValue,
            objectId: reference.id,
            knownVersion: reference.version,
            correlationId: reference.correlationID.value
        )

        let result: Result<PaymentEnvelope, AppError> = await gateway.execute(
            step: step,
            request: request,
            policy: .critical
        ) { (data: FinancialObjectDataDTO) in
            try data.toEnvelope()
        }

        switch result {
        case .success(let envelope):
            return envelope
        case .failure(let error):
            // Lecture : aucune écriture n'a eu lieu, donc aucune ambiguïté
            // financière. `afterSubmission: false` évite de transformer un simple
            // échec réseau de lecture en `timeoutUnknown`, qui déclencherait une
            // réconciliation sans objet.
            await log(reference, operation, error)
            throw FinanceError.from(error, afterSubmission: false)
        }
    }

    // MARK: - Écriture

    public func createPaymentIntent(
        _ request: CreatePaymentIntentRequest,
        idempotency: IdempotencyContext
    ) async throws -> PaymentEnvelope {

        // Refus en amont : une capacité fermée ne doit pas atteindre le réseau.
        // La vraie décision reste backend — ceci évite seulement d'exposer une
        // opération que l'utilisateur n'aurait pas dû pouvoir déclencher.
        let caps = await capabilityResolver.capabilities()
        guard caps.allowsAnyOutgoingOperation else {
            throw FinanceError.capabilityUnavailable
        }

        let dto = CreatePaymentIntentRequestDTO(
            objectType: request.type.rawValue,
            amount: NSDecimalNumber(decimal: request.amount).description,
            currency: request.currency,
            recipientId: request.recipientID,
            conversationId: request.conversationID,
            note: request.note,
            idempotencyKey: idempotency.key,
            clientRequestId: idempotency.clientRequestID.uuidString,
            correlationId: idempotency.correlationID.value,
            deviceId: idempotency.deviceID
        )

        let result: Result<PaymentEnvelope, AppError> = await gateway.execute(
            step: .request,
            request: dto,
            policy: .critical
        ) { (data: FinancialObjectDataDTO) in
            try data.toEnvelope()
        }

        switch result {
        case .success(let envelope):
            return envelope
        case .failure(let error):
            // `request` crée un objet côté backend : la requête est partie, donc
            // un échec est ambigu.
            throw FinanceError.from(error, afterSubmission: true)
        }
    }

    public func confirmPaymentIntent(
        reference: FinancialReference,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async throws -> PaymentEnvelope {

        let dto = ConfirmPaymentIntentRequestDTO(
            objectType: reference.type.rawValue,
            objectId: reference.id,
            knownVersion: reference.version,
            idempotencyKey: idempotency.key,
            clientRequestId: idempotency.clientRequestID.uuidString,
            correlationId: idempotency.correlationID.value,
            deviceId: idempotency.deviceID,
            stepUpLevel: stepUp.map { String($0.level.rawValue) },
            stepUpToken: stepUp?.evidenceToken
        )

        let result: Result<PaymentEnvelope, AppError> = await gateway.execute(
            step: .confirm,
            request: dto,
            policy: .critical
        ) { (data: FinancialObjectDataDTO) in
            try data.toEnvelope()
        }

        switch result {
        case .success(let envelope):
            return envelope
        case .failure(let error):
            // L'étape décisive. Tout échec après émission est ambigu : l'argent a
            // pu bouger. `from(_:afterSubmission: true)` transforme le timeout en
            // `timeoutUnknown`, jamais en `failed`.
            await log(reference, "confirm", error)
            throw FinanceError.from(error, afterSubmission: true)
        }
    }

    // MARK: - Journalisation

    private func log(_ reference: FinancialReference, _ operation: String, _ error: AppError) async {
        let context = FinanceLogContext(reference: reference, operation: operation)
        await logger.log("Échec finance — \(context) error=\(error)", level: .warning)
    }
}
