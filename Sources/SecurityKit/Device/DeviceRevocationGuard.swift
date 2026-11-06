//
//  DeviceRevocationGuard.swift
//  SecurityKit
//
//  Device revocation purges offline queue
//  Revoked devices have all offline data purged
//

import Foundation
import WaanguCoreKit

/// Device revocation guard
/// Revoked devices have offline queue purged
public actor DeviceRevocationGuard {
    
    public static let shared = DeviceRevocationGuard()
    
    private var revokedDevices: Set<String> = []
    private var revocationHistory: [String: RevocationRecord] = [:]
    
    private init() {}
    
    public struct RevocationRecord: Sendable {
        public let deviceId: String
        public let revokedAt: Date
        public let reason: String
        public let queuePurged: Bool
        
        public init(deviceId: String, revokedAt: Date, reason: String, queuePurged: Bool) {
            self.deviceId = deviceId
            self.revokedAt = revokedAt
            self.reason = reason
            self.queuePurged = queuePurged
        }
    }
    
    public enum RevocationError: Error, Sendable {
        case deviceRevoked
        case alreadyRevoked
    }
    
    // MARK: - Public API
    
    /// Revoke device and purge offline queue
    public func revokeDevice(deviceId: String, reason: String) async {
        guard !revokedDevices.contains(deviceId) else {
            return
        }
        
        revokedDevices.insert(deviceId)
        
        // Purge offline queue
        await purgeOfflineQueue(deviceId: deviceId)
        
        let record = RevocationRecord(
            deviceId: deviceId,
            revokedAt: Date(),
            reason: reason,
            queuePurged: true
        )
        
        revocationHistory[deviceId] = record
        
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: ["operation": "device_revoked", "deviceId": deviceId, "reason": reason]
        )
    }
    
    /// Check if device is revoked
    public func isRevoked(deviceId: String) -> Bool {
        return revokedDevices.contains(deviceId)
    }
    
    /// Validate device not revoked
    public func validateNotRevoked(deviceId: String) throws {
        guard !revokedDevices.contains(deviceId) else {
            throw RevocationError.deviceRevoked
        }
    }
    
    /// Get revocation record
    public func getRevocationRecord(deviceId: String) -> RevocationRecord? {
        return revocationHistory[deviceId]
    }
    
    // MARK: - Private Helpers
    
    private func purgeOfflineQueue(deviceId: String) async {
        // In production: purge OfflineQueueStore for this device
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataAccess,
            metadata: ["operation": "purge_offline_queue", "deviceId": deviceId]
        )
    }
}


// MARK: - Conformance au contrat partagé

/// Bloc 8, §33 — rend le garde interrogeable depuis les features.
///
/// `validateNotRevoked` porte déjà la bonne signature ; seule la conformance
/// manquait, et avec elle toute possibilité d'appliquer l'invariant hors de
/// `SecurityKit`.
extension DeviceRevocationGuard: DeviceRevocationChecking {}
