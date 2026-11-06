//
//  ProactiveMessageConsent.swift
//  CoreKit
//
//  Manages consent for proactive messages
//  RULE: Consentement obligatoire pour messages proactifs

import Foundation
import WaanguCoreKit

public actor ProactiveMessageConsent {
    
    public static let shared = ProactiveMessageConsent()
    
    private var consents: [String: ConsentRecord] = [:]
    private var blockedMessages: [BlockedMessage] = []
    
    private init() {}
    
    // MARK: - Consent Management
    
    /// Grants consent for proactive messages
    public func grantConsent(
        userId: String,
        messageType: MessageType,
        expiresIn: TimeInterval = 31536000 // 1 year default
    ) async {
        
        let consent = ConsentRecord(
            userId: userId,
            messageType: messageType,
            granted: true,
            grantedAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
        
        let key = consentKey(userId: userId, messageType: messageType)
        consents[key] = consent
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "consent_granted",
                "user_id": userId,
                "message_type": messageType.rawValue
            ],
            severity: .info
        )
    }
    
    /// Revokes consent for proactive messages
    public func revokeConsent(userId: String, messageType: MessageType) async {
        let key = consentKey(userId: userId, messageType: messageType)
        consents[key]?.granted = false
        
        // Audit
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "consent_revoked",
                "user_id": userId,
                "message_type": messageType.rawValue
            ],
            severity: .info
        )
    }
    
    // MARK: - Consent Validation
    
    /// Validates consent before sending proactive message
    /// RULE: Consentement obligatoire pour messages proactifs
    public func validateConsent(
        userId: String,
        messageType: MessageType
    ) async throws {
        
        let key = consentKey(userId: userId, messageType: messageType)
        
        guard let consent = consents[key] else {
            let blocked = BlockedMessage(
                userId: userId,
                messageType: messageType,
                reason: "No consent record found",
                timestamp: Date()
            )
            blockedMessages.append(blocked)
            
            await logBlockedMessage(blocked)
            
            throw ConsentError.noConsent(userId: userId, messageType: messageType)
        }
        
        guard consent.granted else {
            let blocked = BlockedMessage(
                userId: userId,
                messageType: messageType,
                reason: "Consent was revoked",
                timestamp: Date()
            )
            blockedMessages.append(blocked)
            
            await logBlockedMessage(blocked)
            
            throw ConsentError.consentRevoked(userId: userId, messageType: messageType)
        }
        
        guard consent.expiresAt > Date() else {
            let blocked = BlockedMessage(
                userId: userId,
                messageType: messageType,
                reason: "Consent expired",
                timestamp: Date()
            )
            blockedMessages.append(blocked)
            
            await logBlockedMessage(blocked)
            
            throw ConsentError.consentExpired(userId: userId, messageType: messageType, expiresAt: consent.expiresAt)
        }
    }
    
    /// Checks if consent is granted (non-throwing)
    public func hasConsent(userId: String, messageType: MessageType) -> Bool {
        let key = consentKey(userId: userId, messageType: messageType)
        
        guard let consent = consents[key] else {
            return false
        }
        
        return consent.granted && consent.expiresAt > Date()
    }
    
    // MARK: - Consent Queries
    
    public func getConsent(userId: String, messageType: MessageType) -> ConsentRecord? {
        let key = consentKey(userId: userId, messageType: messageType)
        return consents[key]
    }
    
    public func getAllConsents(userId: String) -> [ConsentRecord] {
        consents.values.filter { $0.userId == userId }
    }
    
    public func getBlockedMessages(limit: Int = 100) -> [BlockedMessage] {
        Array(blockedMessages.prefix(limit))
    }
    
    // MARK: - Helpers
    
    private func consentKey(userId: String, messageType: MessageType) -> String {
        "\(userId):\(messageType.rawValue)"
    }
    
    private func logBlockedMessage(_ blocked: BlockedMessage) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .security,
            metadata: [
                "action": "proactive_message_blocked",
                "user_id": blocked.userId,
                "message_type": blocked.messageType.rawValue,
                "reason": blocked.reason
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public struct ConsentRecord {
        public let userId: String
        public let messageType: MessageType
        public var granted: Bool
        public let grantedAt: Date
        public let expiresAt: Date
    }
    
    public struct BlockedMessage {
        public let userId: String
        public let messageType: MessageType
        public let reason: String
        public let timestamp: Date
    }
    
    public enum MessageType: String, Codable {
        case marketing
        case promotional
        case newsletter
        case productUpdates
        case recommendations
        case surveys
        case notifications
    }
    
    public enum ConsentError: Error, LocalizedError {
        case noConsent(userId: String, messageType: MessageType)
        case consentRevoked(userId: String, messageType: MessageType)
        case consentExpired(userId: String, messageType: MessageType, expiresAt: Date)
        
        public var errorDescription: String? {
            switch self {
            case .noConsent(let userId, let messageType):
                return "No consent for user \(userId) to receive \(messageType.rawValue) messages"
            case .consentRevoked(let userId, let messageType):
                return "Consent revoked for user \(userId) to receive \(messageType.rawValue) messages"
            case .consentExpired(let userId, let messageType, let expiresAt):
                return "Consent expired for user \(userId) to receive \(messageType.rawValue) messages (expired at \(expiresAt))"
            }
        }
    }
}
