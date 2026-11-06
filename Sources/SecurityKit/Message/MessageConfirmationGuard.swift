//
//  MessageConfirmationGuard.swift
//  SecurityKit
//
//  RULE: Le mobile ne peut confirmer aucun message
//  All message confirmations MUST come from backend
//

import Foundation
import WaanguCoreKit

/// Prevents client-side message confirmation
/// RULE: Mobile cannot confirm any message
public struct MessageConfirmationGuard: MessageConfirmationGuardProtocol {
    
    private let logger: AppLogger
    
    public init(logger: AppLogger) {
        self.logger = logger
    }
    
    /// Validate message confirmation from server
    public func validate(
        messageId: String,
        serverSignature: String,
        timestamp: Date
    ) async -> MessageConfirmationValidationResult {
        // Check timestamp freshness (within 5 minutes)
        let age = Date().timeIntervalSince(timestamp)
        guard age >= 0 && age <= 300 else {
            await logger.log("Message confirmation expired: \(messageId), age: \(age)s", level: .warning)
            return .invalid(reason: "Confirmation expired")
        }
        
        // Verify signature exists and has minimum length
        guard !serverSignature.isEmpty && serverSignature.count >= 64 else {
            await logger.log("Invalid message confirmation signature: \(messageId)", level: .warning)
            return .invalid(reason: "Invalid signature")
        }
        
        await logger.log("Message confirmation validated: \(messageId)", level: .info)
        return .valid
    }
}
