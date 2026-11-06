//
//  MultiDeviceDriftDetector.swift
//  CoreKit
//
//  Detects drift between multiple devices
//  RULE: Drift multi-device détectable

import Foundation
import CryptoKit

public actor MultiDeviceDriftDetector {
    
    public static let shared = MultiDeviceDriftDetector()
    
    private var deviceStates: [String: DeviceState] = [:]
    private var detectedDrifts: [DriftIncident] = []
    
    private init() {}
    
    // MARK: - Drift Detection
    
    /// Reports device state for drift detection
    public func reportDeviceState(
        deviceId: String,
        stateHash: String,
        lastSyncTimestamp: Date,
        dataVersion: Int
    ) async {
        
        let state = DeviceState(
            deviceId: deviceId,
            stateHash: stateHash,
            lastSyncTimestamp: lastSyncTimestamp,
            dataVersion: dataVersion,
            reportedAt: Date()
        )
        
        deviceStates[deviceId] = state
        
        // Check for drift
        await detectDrift()
    }
    
    /// Detects drift between devices
    /// RULE: Drift multi-device détectable
    private func detectDrift() async {
        
        guard deviceStates.count >= 2 else { return }
        
        let states = Array(deviceStates.values)
        let referenceState = states.first!
        
        for state in states.dropFirst() {
            
            // Check state hash mismatch
            if state.stateHash != referenceState.stateHash {
                
                let drift = DriftIncident(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    deviceA: referenceState.deviceId,
                    deviceB: state.deviceId,
                    driftType: .stateHashMismatch,
                    severity: .high,
                    metadata: [
                        "hash_a": referenceState.stateHash,
                        "hash_b": state.stateHash
                    ]
                )
                
                detectedDrifts.append(drift)
                await logDrift(drift)
            }
            
            // Check version drift
            let versionDiff = abs(state.dataVersion - referenceState.dataVersion)
            if versionDiff > 10 {
                
                let drift = DriftIncident(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    deviceA: referenceState.deviceId,
                    deviceB: state.deviceId,
                    driftType: .versionDrift,
                    severity: versionDiff > 50 ? .critical : .medium,
                    metadata: [
                        "version_a": "\(referenceState.dataVersion)",
                        "version_b": "\(state.dataVersion)",
                        "diff": "\(versionDiff)"
                    ]
                )
                
                detectedDrifts.append(drift)
                await logDrift(drift)
            }
            
            // Check sync timestamp drift
            let timeDiff = abs(state.lastSyncTimestamp.timeIntervalSince(referenceState.lastSyncTimestamp))
            if timeDiff > 3600 { // 1 hour
                
                let drift = DriftIncident(
                    id: UUID().uuidString,
                    detectedAt: Date(),
                    deviceA: referenceState.deviceId,
                    deviceB: state.deviceId,
                    driftType: .syncTimeDrift,
                    severity: timeDiff > 86400 ? .high : .low,
                    metadata: [
                        "time_diff_seconds": "\(Int(timeDiff))"
                    ]
                )
                
                detectedDrifts.append(drift)
                await logDrift(drift)
            }
        }
    }
    
    /// Computes state hash for drift detection
    public func computeStateHash(data: Data) -> String {
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// Gets detected drift incidents
    public func getDriftIncidents() -> [DriftIncident] {
        detectedDrifts
    }
    
    /// Checks if drift exists
    public func hasDrift() -> Bool {
        !detectedDrifts.isEmpty
    }
    
    /// Clears old drift incidents
    public func clearOldDrifts(olderThan: TimeInterval = 86400) {
        let cutoff = Date().addingTimeInterval(-olderThan)
        detectedDrifts = detectedDrifts.filter { $0.detectedAt > cutoff }
    }
    
    // MARK: - Logging
    
    private func logDrift(_ drift: DriftIncident) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .system,
            metadata: [
                "action": "multi_device_drift_detected",
                "drift_id": drift.id,
                "device_a": drift.deviceA,
                "device_b": drift.deviceB,
                "drift_type": drift.driftType.rawValue,
                "severity": drift.severity.rawValue
            ],
            severity: drift.severity == .critical ? .critical : .warning
        )
    }
    
    // MARK: - Types
    
    public struct DeviceState {
        public let deviceId: String
        public let stateHash: String
        public let lastSyncTimestamp: Date
        public let dataVersion: Int
        public let reportedAt: Date
    }
    
    public struct DriftIncident {
        public let id: String
        public let detectedAt: Date
        public let deviceA: String
        public let deviceB: String
        public let driftType: DriftType
        public let severity: DriftSeverity
        public let metadata: [String: String]
    }
    
    public enum DriftType: String {
        case stateHashMismatch
        case versionDrift
        case syncTimeDrift
        case dataInconsistency
    }
    
    public enum DriftSeverity: String {
        case low
        case medium
        case high
        case critical
    }
}
