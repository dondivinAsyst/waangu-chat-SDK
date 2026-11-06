//
//  CardNFCDisplayGuard.swift
//  CoreKit
//
//  Enforces card/NFC display-only mode
//  RULE: Card/NFC affichage seulement

import Foundation
import WaanguCoreKit

public actor CardNFCDisplayGuard {
    
    public static let shared = CardNFCDisplayGuard()
    
    private var blockedOperations: [BlockedOperation] = []
    
    private init() {}
    
    // MARK: - Card/NFC Validation
    
    /// Validates card operation is display-only
    /// RULE: Card/NFC affichage seulement
    public func validateCardOperation(_ operation: CardOperation) throws {
        
        // Only display operations are allowed
        guard operation.type == .display else {
            let blocked = BlockedOperation(
                operation: operation,
                reason: "Card operations limited to display only",
                timestamp: Date()
            )
            blockedOperations.append(blocked)
            
            Task {
                await logBlockedOperation(blocked)
            }
            
            throw CardNFCError.operationNotAllowed(
                operation: operation.type,
                reason: "Card/NFC operations are display-only"
            )
        }
    }
    
    /// Validates NFC operation is display-only
    /// RULE: Card/NFC affichage seulement
    public func validateNFCOperation(_ operation: NFCOperation) throws {
        
        // Only display operations are allowed
        guard operation.type == .display else {
            let blocked = BlockedOperation(
                operation: operation,
                reason: "NFC operations limited to display only",
                timestamp: Date()
            )
            blockedOperations.append(blocked)
            
            Task {
                await logBlockedOperation(blocked)
            }
            
            throw CardNFCError.operationNotAllowed(
                operation: operation.type,
                reason: "Card/NFC operations are display-only"
            )
        }
    }
    
    /// Checks if operation is allowed
    public func isOperationAllowed(_ operationType: OperationType) -> Bool {
        operationType == .display
    }
    
    /// Gets blocked operations
    public func getBlockedOperations(limit: Int = 100) -> [BlockedOperation] {
        Array(blockedOperations.prefix(limit))
    }
    
    // MARK: - Logging
    
    private func logBlockedOperation(_ blocked: BlockedOperation) async {
        let operationType: String
        if let cardOp = blocked.operation as? CardOperation {
            operationType = cardOp.type.rawValue
        } else if let nfcOp = blocked.operation as? NFCOperation {
            operationType = nfcOp.type.rawValue
        } else {
            operationType = "unknown"
        }
        
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .security,
            metadata: [
                "action": "card_nfc_operation_blocked",
                "operation_type": operationType,
                "reason": blocked.reason
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public struct CardOperation {
        public let type: OperationType
        public let cardId: String
        public let timestamp: Date
        
        public init(type: OperationType, cardId: String, timestamp: Date = Date()) {
            self.type = type
            self.cardId = cardId
            self.timestamp = timestamp
        }
    }
    
    public struct NFCOperation {
        public let type: OperationType
        public let nfcId: String
        public let timestamp: Date
        
        public init(type: OperationType, nfcId: String, timestamp: Date = Date()) {
            self.type = type
            self.nfcId = nfcId
            self.timestamp = timestamp
        }
    }
    
    public enum OperationType: String {
        case display
        case write
        case transaction
        case authentication
    }
    
    public struct BlockedOperation {
        public let operation: Any
        public let reason: String
        public let timestamp: Date
    }
    
    public enum CardNFCError: Error, LocalizedError {
        case operationNotAllowed(operation: OperationType, reason: String)
        
        public var errorDescription: String? {
            switch self {
            case .operationNotAllowed(let operation, let reason):
                return "Operation '\(operation.rawValue)' not allowed: \(reason)"
            }
        }
    }
}
