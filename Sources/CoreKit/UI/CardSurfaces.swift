//
//  CardSurfaces.swift
//  CoreKit
//
//  RULE: Payment/QR/Merchant/Copilot/Operator cards sont des surfaces
//  Backend-driven card surfaces without local business logic

import Foundation

/// Payment card surface
/// RULE: Backend-driven, no local payment logic
public struct PaymentCardSurface: Sendable {
    public let cardId: String
    public let transactionId: String
    public let amount: Decimal
    public let currency: String
    public let recipientName: String

    /// Statut canonique — `CoreKit.PaymentStatus` (voir `PaymentEnvelope.swift`).
    ///
    /// Cette surface portait auparavant son propre enum à 4 cas
    /// (pending/completed/failed/cancelled). Il obligeait à réduire les 21 statuts
    /// backend à 4, et n'avait pas d'`unknown` : un timeout devait s'afficher comme
    /// `failed`. La surface consomme désormais le statut tel quel et choisit
    /// seulement comment le *présenter*.
    public let status: PaymentStatus
    public let timestamp: Date
    public let actions: [SurfaceAction]
    public let signature: String
    
    public init(
        cardId: String,
        transactionId: String,
        amount: Decimal,
        currency: String,
        recipientName: String,
        status: PaymentStatus,
        timestamp: Date,
        actions: [SurfaceAction],
        signature: String
    ) {
        self.cardId = cardId
        self.transactionId = transactionId
        self.amount = amount
        self.currency = currency
        self.recipientName = recipientName
        self.status = status
        self.timestamp = timestamp
        self.actions = actions
        self.signature = signature
    }
    
}

/// QR code card surface
/// RULE: Backend-driven, QR data from backend
public struct QRCardSurface: Sendable {
    public let cardId: String
    public let qrId: String
    public let qrData: String
    public let purpose: QRPurpose
    public let expiresAt: Date
    public let metadata: [String: String]
    public let signature: String
    
    public init(
        cardId: String,
        qrId: String,
        qrData: String,
        purpose: QRPurpose,
        expiresAt: Date,
        metadata: [String: String],
        signature: String
    ) {
        self.cardId = cardId
        self.qrId = qrId
        self.qrData = qrData
        self.purpose = purpose
        self.expiresAt = expiresAt
        self.metadata = metadata
        self.signature = signature
    }
    
    public enum QRPurpose: String, Sendable {
        case payment = "PAYMENT"
        case identification = "IDENTIFICATION"
        case merchantScan = "MERCHANT_SCAN"
        case transfer = "TRANSFER"
    }
}

/// Merchant card surface
/// RULE: Backend-driven merchant interactions
public struct MerchantCardSurface: Sendable {
    public let cardId: String
    public let merchantId: String
    public let merchantName: String
    public let merchantLogo: String?
    public let action: MerchantAction
    public let details: [String: String]
    public let timestamp: Date
    public let signature: String
    
    public init(
        cardId: String,
        merchantId: String,
        merchantName: String,
        merchantLogo: String?,
        action: MerchantAction,
        details: [String: String],
        timestamp: Date,
        signature: String
    ) {
        self.cardId = cardId
        self.merchantId = merchantId
        self.merchantName = merchantName
        self.merchantLogo = merchantLogo
        self.action = action
        self.details = details
        self.timestamp = timestamp
        self.signature = signature
    }
    
    public enum MerchantAction: String, Sendable {
        case paymentRequest = "PAYMENT_REQUEST"
        case refund = "REFUND"
        case promotion = "PROMOTION"
        case notification = "NOTIFICATION"
    }
}

/// Copilot card surface
/// RULE: Backend-driven AI suggestions
public struct CopilotCardSurface: Sendable {
    public let cardId: String
    public let copilotId: String
    public let suggestion: String
    public let confidence: Double
    public let reasoning: String?
    public let actions: [SurfaceAction]
    public let timestamp: Date
    public let signature: String
    
    public init(
        cardId: String,
        copilotId: String,
        suggestion: String,
        confidence: Double,
        reasoning: String?,
        actions: [SurfaceAction],
        timestamp: Date,
        signature: String
    ) {
        self.cardId = cardId
        self.copilotId = copilotId
        self.suggestion = suggestion
        self.confidence = confidence
        self.reasoning = reasoning
        self.actions = actions
        self.timestamp = timestamp
        self.signature = signature
    }
}

/// Operator card surface
/// RULE: Backend-driven operator messages
public struct OperatorCardSurface: Sendable {
    public let cardId: String
    public let operatorId: String
    public let operatorName: String
    public let message: String
    public let priority: OperatorPriority
    public let category: String
    public let actions: [SurfaceAction]
    public let timestamp: Date
    public let signature: String
    
    public init(
        cardId: String,
        operatorId: String,
        operatorName: String,
        message: String,
        priority: OperatorPriority,
        category: String,
        actions: [SurfaceAction],
        timestamp: Date,
        signature: String
    ) {
        self.cardId = cardId
        self.operatorId = operatorId
        self.operatorName = operatorName
        self.message = message
        self.priority = priority
        self.category = category
        self.actions = actions
        self.timestamp = timestamp
        self.signature = signature
    }
    
    public enum OperatorPriority: String, Sendable {
        case low = "LOW"
        case normal = "NORMAL"
        case high = "HIGH"
        case urgent = "URGENT"
    }
}

/// Surface action (backend-driven)
public struct SurfaceAction: Sendable {
    public let actionId: String
    public let label: String
    public let actionType: ActionType
    public let parameters: [String: String]
    
    public init(
        actionId: String,
        label: String,
        actionType: ActionType,
        parameters: [String: String] = [:]
    ) {
        self.actionId = actionId
        self.label = label
        self.actionType = actionType
        self.parameters = parameters
    }
    
    public enum ActionType: String, Sendable {
        case navigate = "NAVIGATE"
        case apiCall = "API_CALL"
        case dismiss = "DISMISS"
        case confirm = "CONFIRM"
        case cancel = "CANCEL"
    }
}

/// Card surface manager
/// RULE: Validates and manages card surfaces
public actor CardSurfaceManager {
    
    public static let shared = CardSurfaceManager()
    
    private var paymentCards: [String: PaymentCardSurface] = [:]
    private var qrCards: [String: QRCardSurface] = [:]
    private var merchantCards: [String: MerchantCardSurface] = [:]
    private var copilotCards: [String: CopilotCardSurface] = [:]
    private var operatorCards: [String: OperatorCardSurface] = [:]
    
    private init() {}
    
    // MARK: - Payment Cards
    
    public func registerPaymentCard(_ card: PaymentCardSurface) async throws {
        // Validate signature
        guard try await validateSignature(cardId: card.cardId, signature: card.signature) else {
            throw CardSurfaceError.invalidSignature
        }
        
        paymentCards[card.cardId] = card
    }
    
    public func getPaymentCard(cardId: String) -> PaymentCardSurface? {
        return paymentCards[cardId]
    }
    
    // MARK: - QR Cards
    
    public func registerQRCard(_ card: QRCardSurface) async throws {
        guard try await validateSignature(cardId: card.cardId, signature: card.signature) else {
            throw CardSurfaceError.invalidSignature
        }
        
        // Check expiration
        guard card.expiresAt > Date() else {
            throw CardSurfaceError.expired
        }
        
        qrCards[card.cardId] = card
    }
    
    public func getQRCard(cardId: String) -> QRCardSurface? {
        return qrCards[cardId]
    }
    
    // MARK: - Merchant Cards
    
    public func registerMerchantCard(_ card: MerchantCardSurface) async throws {
        guard try await validateSignature(cardId: card.cardId, signature: card.signature) else {
            throw CardSurfaceError.invalidSignature
        }
        
        merchantCards[card.cardId] = card
    }
    
    public func getMerchantCard(cardId: String) -> MerchantCardSurface? {
        return merchantCards[cardId]
    }
    
    // MARK: - Copilot Cards
    
    public func registerCopilotCard(_ card: CopilotCardSurface) async throws {
        guard try await validateSignature(cardId: card.cardId, signature: card.signature) else {
            throw CardSurfaceError.invalidSignature
        }
        
        copilotCards[card.cardId] = card
    }
    
    public func getCopilotCard(cardId: String) -> CopilotCardSurface? {
        return copilotCards[cardId]
    }
    
    // MARK: - Operator Cards
    
    public func registerOperatorCard(_ card: OperatorCardSurface) async throws {
        guard try await validateSignature(cardId: card.cardId, signature: card.signature) else {
            throw CardSurfaceError.invalidSignature
        }
        
        operatorCards[card.cardId] = card
    }
    
    public func getOperatorCard(cardId: String) -> OperatorCardSurface? {
        return operatorCards[cardId]
    }
    
    // MARK: - Validation
    
    private func validateSignature(cardId: String, signature: String) async throws -> Bool {
        // In production: Verify with backend public key
        guard !signature.isEmpty && signature.count >= 64 else {
            return false
        }
        
        guard Data(base64Encoded: signature) != nil else {
            return false
        }
        
        return true
    }
}

public enum CardSurfaceError: Error, LocalizedError {
    case invalidSignature
    case expired
    case notFound
    
    public var errorDescription: String? {
        switch self {
        case .invalidSignature:
            return "Card surface signature is invalid"
        case .expired:
            return "Card surface has expired"
        case .notFound:
            return "Card surface not found"
        }
    }
}
