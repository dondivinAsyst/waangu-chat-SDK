//
//  QRReusePreventionGuard.swift
//  SecurityKit
//
//  Prevents QR code reuse
//  Each QR can only be used once
//

import Foundation
import WaanguCoreKit

/// QR reuse prevention guard
/// Ensures QR codes are single-use only
public actor QRReusePreventionGuard {
    
    public static let shared = QRReusePreventionGuard()
    
    private var usedQRCodes: Set<String> = []
    private var qrUsageHistory: [String: QRUsage] = [:]
    
    private init() {}
    
    public struct QRUsage: Sendable {
        public let qrId: String
        public let usedAt: Date
        public let userId: String?
        
        public init(qrId: String, usedAt: Date, userId: String?) {
            self.qrId = qrId
            self.usedAt = usedAt
            self.userId = userId
        }
    }
    
    public enum QRReuseError: Error, Sendable {
        case alreadyUsed
        case reuseAttempt
    }
    
    // MARK: - Public API
    
    /// Mark QR as used (can only be done once)
    public func markAsUsed(qrId: String, userId: String?) throws {
        // Check if already used
        guard !usedQRCodes.contains(qrId) else {
            Task {
                await AuditBreadcrumb.shared.recordSecurity(
                    action: .securityViolation,
                    userId: userId,
                    metadata: ["violation": "qr_reuse_attempt", "qrId": qrId]
                )
            }
            throw QRReuseError.reuseAttempt
        }
        
        // Mark as used
        usedQRCodes.insert(qrId)
        
        let usage = QRUsage(
            qrId: qrId,
            usedAt: Date(),
            userId: userId
        )
        qrUsageHistory[qrId] = usage
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .security,
                metadata: ["operation": "qr_used", "qrId": qrId]
            )
        }
    }
    
    /// Check if QR has been used
    public func isUsed(qrId: String) -> Bool {
        return usedQRCodes.contains(qrId)
    }
    
    /// Validate QR can be used
    public func validateCanUse(qrId: String) throws {
        guard !usedQRCodes.contains(qrId) else {
            throw QRReuseError.alreadyUsed
        }
    }
    
    /// Get usage history
    public func getUsage(qrId: String) -> QRUsage? {
        return qrUsageHistory[qrId]
    }
}
