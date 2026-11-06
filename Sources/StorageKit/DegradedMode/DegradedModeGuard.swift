//
//  DegradedModeGuard.swift
//  CoreKit
//
//  Blocks critical write operations in degraded mode

import Foundation
import WaanguCoreKit

public actor DegradedModeGuard {
    
    public static let shared = DegradedModeGuard()
    
    private var currentMode: SystemMode = .normal
    private var degradedServices: Set<String> = []
    private var blockedOperations: [BlockedOperation] = []
    
    private init() {}
    
    // MARK: - Mode Management
    
    public func setMode(_ mode: SystemMode) {
        currentMode = mode
        
        if mode == .degraded {
            logModeChange(to: mode)
        }
    }
    
    public func getCurrentMode() -> SystemMode {
        currentMode
    }
    
    public func markServiceDegraded(_ service: String) {
        degradedServices.insert(service)
        
        if !degradedServices.isEmpty && currentMode == .normal {
            setMode(.degraded)
        }
    }
    
    public func markServiceHealthy(_ service: String) {
        degradedServices.remove(service)
        
        if degradedServices.isEmpty && currentMode == .degraded {
            setMode(.normal)
        }
    }
    
    // MARK: - Write Operation Validation
    
    public func validateWrite(operation: WriteOperation) async throws {
        guard currentMode != .readOnly else {
            throw DegradedError.systemReadOnly
        }
        
        if currentMode == .degraded {
            // Check if operation is critical
            if operation.isCritical {
                let blocked = BlockedOperation(
                    operation: operation,
                    reason: "System in degraded mode",
                    timestamp: Date()
                )
                blockedOperations.append(blocked)
                
                await logBlockedOperation(blocked)
                
                throw DegradedError.criticalWriteBlocked(
                    operation: operation.name,
                    reason: "System in degraded mode - critical writes are blocked"
                )
            }
        }
    }
    
    public func canWrite(operation: WriteOperation) -> Bool {
        if currentMode == .readOnly {
            return false
        }
        
        if currentMode == .degraded && operation.isCritical {
            return false
        }
        
        return true
    }
    
    // MARK: - Critical Operations
    
    private let criticalOperations: Set<String> = [
        "payment_transaction",
        "money_transfer",
        "account_deletion",
        "user_ban",
        "security_key_rotation",
        "compliance_decision",
        "regulatory_action",
        "card_operation",      // RULE: Degraded bloque paiement/carte/NFC
        "nfc_operation",       // RULE: Degraded bloque paiement/carte/NFC
        "payment_initiation"   // RULE: Degraded bloque paiement/carte/NFC
    ]
    
    public func isCriticalOperation(_ operationName: String) -> Bool {
        criticalOperations.contains(operationName)
    }
    
    // MARK: - Payment/Card/NFC Blocking
    
    /// Validates payment operation (blocked in degraded mode)
    /// RULE: Degraded bloque paiement/carte/NFC
    public func validatePaymentOperation() throws {
        if currentMode == .degraded || currentMode == .readOnly {
            throw DegradedError.paymentBlockedInDegradedMode
        }
    }
    
    /// Validates card operation (blocked in degraded mode)
    /// RULE: Degraded bloque paiement/carte/NFC
    public func validateCardOperation() throws {
        if currentMode == .degraded || currentMode == .readOnly {
            throw DegradedError.cardBlockedInDegradedMode
        }
    }
    
    /// Validates NFC operation (blocked in degraded mode)
    /// RULE: Degraded bloque paiement/carte/NFC
    public func validateNFCOperation() throws {
        if currentMode == .degraded || currentMode == .readOnly {
            throw DegradedError.nfcBlockedInDegradedMode
        }
    }
    
    /// Validates QR operation (blocked in degraded mode)
    /// RULE: Degraded bloque QR/payment/card/NFC
    public func validateQROperation() throws {
        if currentMode == .degraded || currentMode == .readOnly {
            throw DegradedError.qrBlockedInDegradedMode
        }
    }
    
    /// Validates fintech write operation (blocked in degraded mode)
    /// RULE: Degraded bloque fintech writes
    public func validateFintechWrite() throws {
        if currentMode == .degraded || currentMode == .readOnly {
            throw DegradedError.fintechWriteBlockedInDegradedMode
        }
    }
    
    // MARK: - Service Health
    
    public func getServiceHealth() -> ServiceHealthReport {
        ServiceHealthReport(
            mode: currentMode,
            degradedServices: Array(degradedServices),
            blockedOperationsCount: blockedOperations.count,
            timestamp: Date()
        )
    }
    
    public func getBlockedOperations(limit: Int = 100) -> [BlockedOperation] {
        Array(blockedOperations.prefix(limit))
    }
    
    public func clearBlockedOperations() {
        blockedOperations.removeAll()
    }
    
    // MARK: - Logging
    
    private func logModeChange(to mode: SystemMode) {
        Task {
            await AuditBreadcrumb.shared.record(
                action: .errorOccurred,
                category: .system,
                metadata: [
                    "action": "system_mode_change",
                    "mode": mode.rawValue,
                    "degraded_services": degradedServices.joined(separator: ", ")
                ],
                severity: mode == .degraded ? .warning : .critical
            )
        }
    }
    
    private func logBlockedOperation(_ blocked: BlockedOperation) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .system,
            metadata: [
                "action": "write_operation_blocked",
                "operation": blocked.operation.name,
                "reason": blocked.reason,
                "is_critical": String(blocked.operation.isCritical)
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public enum SystemMode: String, Codable {
        case normal = "NORMAL"
        case degraded = "DEGRADED"
        case readOnly = "READ_ONLY"
        case maintenance = "MAINTENANCE"
    }
    
    public struct WriteOperation {
        public let name: String
        public let isCritical: Bool
        public let service: String
        public let userId: String?
        
        public init(name: String, isCritical: Bool, service: String, userId: String? = nil) {
            self.name = name
            self.isCritical = isCritical
            self.service = service
            self.userId = userId
        }
    }
    
    public struct BlockedOperation {
        public let operation: WriteOperation
        public let reason: String
        public let timestamp: Date
    }
    
    public struct ServiceHealthReport {
        public let mode: SystemMode
        public let degradedServices: [String]
        public let blockedOperationsCount: Int
        public let timestamp: Date
    }
    
    public enum DegradedError: Error, LocalizedError {
        case systemReadOnly
        case criticalWriteBlocked(operation: String, reason: String)
        case serviceUnavailable(service: String)
        case paymentBlockedInDegradedMode  // RULE: Degraded bloque paiement/carte/NFC
        case cardBlockedInDegradedMode     // RULE: Degraded bloque paiement/carte/NFC
        case nfcBlockedInDegradedMode      // RULE: Degraded bloque paiement/carte/NFC
        case qrBlockedInDegradedMode       // RULE: Degraded bloque QR
        case fintechWriteBlockedInDegradedMode  // RULE: Degraded bloque fintech writes
        
        public var errorDescription: String? {
            switch self {
            case .systemReadOnly:
                return "System is in read-only mode. Write operations are not allowed."
            case .criticalWriteBlocked(let operation, let reason):
                return "Critical write operation '\(operation)' blocked: \(reason)"
            case .serviceUnavailable(let service):
                return "Service '\(service)' is unavailable"
            case .paymentBlockedInDegradedMode:
                return "Payment operations are blocked in degraded mode"
            case .cardBlockedInDegradedMode:
                return "Card operations are blocked in degraded mode"
            case .nfcBlockedInDegradedMode:
                return "NFC operations are blocked in degraded mode"
            case .qrBlockedInDegradedMode:
                return "QR operations are blocked in degraded mode"
            case .fintechWriteBlockedInDegradedMode:
                return "Fintech write operations are blocked in degraded mode"
            }
        }
    }
}
