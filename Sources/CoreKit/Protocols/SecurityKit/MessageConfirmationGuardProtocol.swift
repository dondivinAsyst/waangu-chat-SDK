//
//  MessageConfirmationGuardProtocol.swift
//  CoreKit
//
//  Protocol abstraction for MessageConfirmationGuard

import Foundation

/// Validation result for message confirmation
public enum MessageConfirmationValidationResult: Sendable {
    case valid
    case invalid(reason: String)
}

public protocol MessageConfirmationGuardProtocol: Sendable {
    /// Validate message confirmation from server
    func validate(
        messageId: String,
        serverSignature: String,
        timestamp: Date
    ) async -> MessageConfirmationValidationResult
}