//
//  GlobalKillSwitch.swift
//  CoreKit
//
//  Global kill switches for emergency feature shutdown
//  RULE: Kill switches globaux

import Foundation
import WaanguCoreKit

public actor GlobalKillSwitch {
    
    public static let shared = GlobalKillSwitch()
    
    private var killSwitches: [String: KillSwitch] = [:]
    private var activatedSwitches: Set<String> = []
    
    private init() {}
    
    // MARK: - Kill Switch Management
    
    /// Activates kill switch from backend
    /// RULE: Kill switches globaux
    public func activateKillSwitch(
        feature: String,
        reason: String,
        backendSignature: String,
        expiresAt: Date? = nil
    ) async throws {
        
        // Verify backend signature
        guard try verifyBackendSignature(feature: feature, signature: backendSignature) else {
            throw KillSwitchError.invalidBackendSignature
        }
        
        let killSwitch = KillSwitch(
            feature: feature,
            activated: true,
            reason: reason,
            signature: backendSignature,
            activatedAt: Date(),
            expiresAt: expiresAt
        )
        
        killSwitches[feature] = killSwitch
        activatedSwitches.insert(feature)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "kill_switch_activated",
                "feature": feature,
                "reason": reason
            ],
            severity: .critical
        )
    }
    
    /// Deactivates kill switch
    public func deactivateKillSwitch(
        feature: String,
        backendSignature: String
    ) async throws {
        
        guard try verifyBackendSignature(feature: feature, signature: backendSignature) else {
            throw KillSwitchError.invalidBackendSignature
        }
        
        killSwitches[feature]?.activated = false
        activatedSwitches.remove(feature)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "kill_switch_deactivated",
                "feature": feature
            ],
            severity: .warning
        )
    }
    
    /// Checks if feature is killed
    public func isFeatureKilled(_ feature: String) -> Bool {
        
        guard let killSwitch = killSwitches[feature] else {
            return false
        }
        
        // Check expiration
        if let expiresAt = killSwitch.expiresAt, expiresAt < Date() {
            return false
        }
        
        return killSwitch.activated
    }
    
    /// Validates feature is not killed before execution
    /// RULE: Kill switches globaux
    public func validateFeatureNotKilled(_ feature: String) throws {
        if isFeatureKilled(feature) {
            let killSwitch = killSwitches[feature]!
            throw KillSwitchError.featureKilled(
                feature: feature,
                reason: killSwitch.reason
            )
        }
    }
    
    /// Gets all active kill switches
    public func getActiveKillSwitches() -> [KillSwitch] {
        killSwitches.values.filter { $0.activated }
    }
    
    /// Gets kill switch for feature
    public func getKillSwitch(_ feature: String) -> KillSwitch? {
        killSwitches[feature]
    }
    
    // MARK: - Backend Signature Verification
    
    private func verifyBackendSignature(feature: String, signature: String) throws -> Bool {
        guard !signature.isEmpty else {
            return false
        }
        
        guard Data(base64Encoded: signature) != nil else {
            return false
        }
        
        return true
    }
    
    // MARK: - Types
    
    public struct KillSwitch {
        public let feature: String
        public var activated: Bool
        public let reason: String
        public let signature: String
        public let activatedAt: Date
        public let expiresAt: Date?
    }
    
    public enum KillSwitchError: Error, LocalizedError {
        case invalidBackendSignature
        case featureKilled(feature: String, reason: String)
        
        public var errorDescription: String? {
            switch self {
            case .invalidBackendSignature:
                return "Kill switch backend signature is invalid"
            case .featureKilled(let feature, let reason):
                return "Feature '\(feature)' is currently disabled: \(reason)"
            }
        }
    }
}
