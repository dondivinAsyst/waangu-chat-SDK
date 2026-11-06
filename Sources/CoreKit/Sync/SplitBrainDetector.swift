//
//  SplitBrainDetector.swift
//  CoreKit
//
//  Detects split-brain scenarios in distributed system
//  RULE: Split-brain détectable

import Foundation

public actor SplitBrainDetector {
    
    public static let shared = SplitBrainDetector()
    
    private var partitions: [String: Partition] = [:]
    private var detectedSplits: [SplitBrainIncident] = []
    
    private init() {}
    
    // MARK: - Split-Brain Detection
    
    /// Reports partition state from a device
    public func reportPartitionState(
        deviceId: String,
        partitionId: String,
        members: Set<String>,
        timestamp: Date
    ) async {
        
        let partition = Partition(
            id: partitionId,
            deviceId: deviceId,
            members: members,
            timestamp: timestamp
        )
        
        partitions[deviceId] = partition
        
        // Check for split-brain
        await detectSplitBrain()
    }
    
    /// Detects split-brain scenarios
    /// RULE: Split-brain détectable
    private func detectSplitBrain() async {
        
        let partitionGroups = Dictionary(grouping: partitions.values) { $0.partitionId }
        
        // Split-brain occurs when multiple partitions exist
        if partitionGroups.count > 1 {
            
            let incident = SplitBrainIncident(
                id: UUID().uuidString,
                detectedAt: Date(),
                partitions: Array(partitionGroups.values.map { partitions in
                    PartitionInfo(
                        id: partitions.first!.partitionId,
                        members: partitions.flatMap { $0.members }
                    )
                }),
                severity: calculateSeverity(partitionGroups)
            )
            
            detectedSplits.append(incident)
            
            await logSplitBrain(incident)
        }
    }
    
    private func calculateSeverity(_ partitionGroups: [String: [Partition]]) -> SplitBrainSeverity {
        let partitionCount = partitionGroups.count
        
        if partitionCount >= 3 {
            return .critical
        } else if partitionCount == 2 {
            // Check if partitions are roughly equal size
            let sizes = partitionGroups.values.map { $0.count }
            let maxSize = sizes.max() ?? 0
            let minSize = sizes.min() ?? 0
            
            if maxSize > minSize * 2 {
                return .medium
            } else {
                return .high
            }
        }
        
        return .low
    }
    
    /// Checks if system is in split-brain state
    public func isSplitBrain() -> Bool {
        let partitionGroups = Dictionary(grouping: partitions.values) { $0.partitionId }
        return partitionGroups.count > 1
    }
    
    /// Gets current split-brain incidents
    public func getSplitBrainIncidents() -> [SplitBrainIncident] {
        detectedSplits
    }
    
    /// Resolves split-brain by selecting primary partition
    public func resolveSplitBrain(primaryPartitionId: String) async {
        
        // Remove devices not in primary partition
        partitions = partitions.filter { $0.value.partitionId == primaryPartitionId }
        
        await AuditBreadcrumb.shared.record(
            action: .settingsChanged,
            category: .system,
            metadata: [
                "action": "split_brain_resolved",
                "primary_partition": primaryPartitionId
            ],
            severity: .warning
        )
    }
    
    // MARK: - Logging
    
    private func logSplitBrain(_ incident: SplitBrainIncident) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .system,
            metadata: [
                "action": "split_brain_detected",
                "incident_id": incident.id,
                "partition_count": String(incident.partitions.count),
                "severity": incident.severity.rawValue
            ],
            severity: .critical
        )
    }
    
    // MARK: - Types
    
    public struct Partition {
        public let id: String
        public let deviceId: String
        public let members: Set<String>
        public let timestamp: Date
        
        public var partitionId: String { id }
    }
    
    public struct SplitBrainIncident {
        public let id: String
        public let detectedAt: Date
        public let partitions: [PartitionInfo]
        public let severity: SplitBrainSeverity
    }
    
    public struct PartitionInfo {
        public let id: String
        public let members: [String]
    }
    
    public enum SplitBrainSeverity: String {
        case low
        case medium
        case high
        case critical
    }
}
