//
//  FinanceDTOs.swift
//  DomainKit
//
//  Contrats de transport des objets financiers — tâche 3.2 / 4.6.
//
//  **BACKEND CONTRACT REQUIRED** — contrats #2, #3, #6 du §15. La forme exacte
//  des champs doit être confirmée avec Samuel et les backends financiers ; les
//  noms ci-dessous suivent la convention des DTO existants du pipeline.

import Foundation
import WaanguCoreKit

// MARK: - Requêtes

/// Lecture d'un objet financier par référence.
///
/// Ne porte ni montant ni contrepartie : c'est une lecture par identité. Filtrer
/// côté client sur des critères métier permettrait d'énumérer les objets d'autrui.
public struct FinancialObjectRequestDTO: Encodable, Sendable {
    public let objectType: String
    public let objectId: String

    /// Révision connue localement. Indication pour le backend, qui peut répondre
    /// « inchangé » — jamais un filtre : il répond toujours l'état courant.
    public let knownVersion: Int

    public let correlationId: String

    public init(objectType: String, objectId: String, knownVersion: Int, correlationId: String) {
        self.objectType = objectType
        self.objectId = objectId
        self.knownVersion = knownVersion
        self.correlationId = correlationId
    }
}

public struct CreatePaymentIntentRequestDTO: Encodable, Sendable {
    public let objectType: String

    /// Montant en chaîne, pas en `Double`.
    ///
    /// Un `Double` sérialisé perd des centimes sur des valeurs pourtant banales
    /// (`0.1 + 0.2`), et le JSON ne distingue pas entier et flottant. La chaîne
    /// traverse sans réinterprétation.
    public let amount: String

    public let currency: String
    public let recipientId: String
    public let conversationId: String?
    public let note: String?

    public let idempotencyKey: String
    public let clientRequestId: String
    public let correlationId: String
    public let deviceId: String

    public init(
        objectType: String, amount: String, currency: String, recipientId: String,
        conversationId: String?, note: String?, idempotencyKey: String,
        clientRequestId: String, correlationId: String, deviceId: String
    ) {
        self.objectType = objectType
        self.amount = amount
        self.currency = currency
        self.recipientId = recipientId
        self.conversationId = conversationId
        self.note = note
        self.idempotencyKey = idempotencyKey
        self.clientRequestId = clientRequestId
        self.correlationId = correlationId
        self.deviceId = deviceId
    }
}

public struct ConfirmPaymentIntentRequestDTO: Encodable, Sendable {
    public let objectType: String
    public let objectId: String
    public let knownVersion: Int
    public let idempotencyKey: String
    public let clientRequestId: String
    public let correlationId: String
    public let deviceId: String
    public let stepUpLevel: String?
    public let stepUpToken: String?

    public init(
        objectType: String, objectId: String, knownVersion: Int,
        idempotencyKey: String, clientRequestId: String, correlationId: String,
        deviceId: String, stepUpLevel: String?, stepUpToken: String?
    ) {
        self.objectType = objectType
        self.objectId = objectId
        self.knownVersion = knownVersion
        self.idempotencyKey = idempotencyKey
        self.clientRequestId = clientRequestId
        self.correlationId = correlationId
        self.deviceId = deviceId
        self.stepUpLevel = stepUpLevel
        self.stepUpToken = stepUpToken
    }
}

// MARK: - Réponse

/// Objet financier tel que le backend le rend.
public struct FinancialObjectDataDTO: Codable, Sendable {

    public let objectType: String
    public let objectId: String

    /// Révision monotone. **Obligatoire** — contrat backend #2.
    /// Sans elle, aucun ordre n'est établissable entre deux réponses.
    public let version: Int

    public let amount: String
    public let currency: String
    public let status: String

    public let senderId: String
    public let recipientId: String
    public let merchantId: String?

    public let backendSignature: String
    public let idempotencyKey: String
    public let correlationId: String
    public let traceId: String?

    public let railProvider: String?
    public let railTransactionId: String?
    public let railSignature: String?
    public let railStatus: String?
    public let railTimestamp: Date?

    public let feeAmount: String?
    public let feeCurrency: String?
    public let exchangeRate: String?
    public let crossBorder: Bool?
    public let description: String?
    public let timestamp: Date?
}

// MARK: - Mapping

public extension FinancialObjectDataDTO {

    /// Référence versionnée de cet objet.
    func toReference() throws -> FinancialReference {
        guard let type = FinancialObjectType(rawValue: objectType) else {
            throw FinanceError.validation(field: "objectType")
        }
        return FinancialReference(
            type: type,
            id: objectId,
            version: version,
            correlationID: CorrelationId(value: correlationId)
        )
    }

    /// Enveloppe canonique.
    ///
    /// Le statut passe par le décodage défensif de `PaymentStatus` : un statut
    /// que ce client ne connaît pas devient `.unknown`, jamais `.failed`.
    func toEnvelope() throws -> PaymentEnvelope {
        guard let type = FinancialObjectType(rawValue: objectType) else {
            throw FinanceError.validation(field: "objectType")
        }
        guard let parsedAmount = Decimal(string: amount) else {
            throw FinanceError.validation(field: "amount")
        }

        let proof = RailProof(
            railProvider: railProvider ?? "",
            railTransactionId: railTransactionId ?? "",
            railSignature: railSignature ?? "",
            railTimestamp: railTimestamp ?? Date(),
            railStatus: railStatus ?? "",
            railMetadata: [:]
        )

        return PaymentEnvelope(
            id: objectId,
            paymentType: Self.paymentType(for: type),
            amount: parsedAmount,
            currency: currency,
            timestamp: timestamp ?? Date(),
            status: PaymentStatus(rawValue: status) ?? .unknown,
            senderId: senderId,
            recipientId: recipientId,
            merchantId: merchantId,
            backendSignature: backendSignature,
            railProof: proof,
            evidenceRefs: [],
            version: String(version),
            truthSource: .backend,
            idempotencyKey: idempotencyKey,
            correlationId: correlationId,
            traceId: traceId,
            description: description,
            metadata: [:],
            feeAmount: feeAmount.flatMap { Decimal(string: $0) },
            feeCurrency: feeCurrency,
            exchangeRate: exchangeRate.flatMap { Decimal(string: $0) },
            crossBorder: crossBorder ?? false
        )
    }

    /// Correspondance entre nature d'objet et type de paiement de l'enveloppe.
    ///
    /// Les deux taxonomies coexistent dans le dépôt : `PaymentType` décrit le
    /// *rail* (carte, virement, QR), `FinancialObjectType` décrit l'*objet*
    /// (paiement, demande, litige). Les fusionner demanderait de toucher
    /// `PaymentEnvelope`, hors périmètre du Bloc 1.
    static func paymentType(for type: FinancialObjectType) -> PaymentType {
        switch type {
        case .payment, .remittance, .payout:          return .p2p
        case .merchantPayment, .settlement:           return .merchant
        case .moneyRequest:                           return .requestToPay
        case .splitBill:                              return .splitBill
        case .refund:                                 return .refund
        case .bill, .airtime, .dataBundle,
             .cashIn, .cashOut:                       return .mobileWallet
        case .card:                                   return .card
        case .fxQuote, .dispute, .credit, .investment,
             .savings, .unknown:                      return .p2p
        }
    }
}
