//
//  OfflineTruthfulness.swift
//  CoreKit
//
//  Visible offline truthfulness tracking
//  RULE: Offline truthfulness visible

import Foundation
import WaanguCoreKit

public actor OfflineTruthfulness {
    
    public static let shared = OfflineTruthfulness()
    
    private var offlineData: [String: OfflineDataRecord] = [:]
    private var truthfulnessReports: [TruthfulnessReport] = []
    
    private init() {}
    
    // MARK: - Offline Data Tracking
    
    /// Records offline data with truthfulness metadata
    /// RULE: Offline truthfulness visible
    public func recordOfflineData(
        dataId: String,
        dataType: DataType,
        content: String,
        source: DataSource,
        lastVerifiedOnline: Date?,
        confidence: TruthfulnessConfidence
    ) async {
        
        let record = OfflineDataRecord(
            dataId: dataId,
            dataType: dataType,
            content: content,
            source: source,
            lastVerifiedOnline: lastVerifiedOnline,
            confidence: confidence,
            createdOffline: Date(),
            syncStatus: .pending
        )
        
        offlineData[dataId] = record
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .dataAccess,
            metadata: [
                "action": "offline_data_recorded",
                "data_id": dataId,
                "data_type": dataType.rawValue,
                "source": source.rawValue,
                "confidence": confidence.rawValue
            ],
            severity: .info
        )
    }
    
    /// Gets truthfulness status for offline data
    /// RULE: Offline truthfulness visible
    public func getTruthfulnessStatus(dataId: String) -> TruthfulnessStatus? {
        
        guard let record = offlineData[dataId] else {
            return nil
        }
        
        let staleness = calculateStaleness(record)
        let reliability = calculateReliability(record)
        
        return TruthfulnessStatus(
            dataId: dataId,
            source: record.source,
            lastVerifiedOnline: record.lastVerifiedOnline,
            confidence: record.confidence,
            staleness: staleness,
            reliability: reliability,
            syncStatus: record.syncStatus,
            visible: true // RULE: Offline truthfulness visible
        )
    }
    
    /// Calculates data staleness
    private func calculateStaleness(_ record: OfflineDataRecord) -> Staleness {
        
        guard let lastVerified = record.lastVerifiedOnline else {
            return .unknown
        }
        
        let age = Date().timeIntervalSince(lastVerified)
        
        if age < 3600 { // 1 hour
            return .fresh
        } else if age < 86400 { // 1 day
            return .recent
        } else if age < 604800 { // 1 week
            return .stale
        } else {
            return .veryStale
        }
    }
    
    /// Calculates data reliability
    private func calculateReliability(_ record: OfflineDataRecord) -> Reliability {
        
        switch record.source {
        case .backend:
            return record.lastVerifiedOnline != nil ? .high : .medium
            
        case .localCache:
            return record.lastVerifiedOnline != nil ? .medium : .low
            
        case .userInput:
            return .medium
            
        case .derived:
            return .low
        }
    }
    
    /// Marks data as synced with backend
    public func markSynced(dataId: String, verifiedAt: Date) async {
        
        guard var record = offlineData[dataId] else { return }
        
        record.lastVerifiedOnline = verifiedAt
        record.syncStatus = .synced
        record.confidence = .high
        
        offlineData[dataId] = record
    }
    
    /// Generates truthfulness report
    public func generateTruthfulnessReport() -> TruthfulnessReport {
        
        let totalRecords = offlineData.count
        let syncedRecords = offlineData.values.filter { $0.syncStatus == .synced }.count
        let pendingRecords = offlineData.values.filter { $0.syncStatus == .pending }.count
        let failedRecords = offlineData.values.filter { $0.syncStatus == .failed }.count
        
        let confidenceDistribution = Dictionary(grouping: offlineData.values) { $0.confidence }
            .mapValues { $0.count }
        
        let report = TruthfulnessReport(
            totalRecords: totalRecords,
            syncedRecords: syncedRecords,
            pendingRecords: pendingRecords,
            failedRecords: failedRecords,
            confidenceDistribution: confidenceDistribution,
            generatedAt: Date()
        )
        
        truthfulnessReports.append(report)
        
        return report
    }
    
    /// Gets all offline data with low truthfulness
    public func getLowTruthfulnessData() -> [OfflineDataRecord] {
        offlineData.values.filter { record in
            record.confidence == .low || record.confidence == .unknown
        }
    }
    
    // MARK: - Types
    
    public struct OfflineDataRecord {
        public let dataId: String
        public let dataType: DataType
        public let content: String
        public let source: DataSource
        public var lastVerifiedOnline: Date?
        public var confidence: TruthfulnessConfidence
        public let createdOffline: Date
        public var syncStatus: SyncStatus
    }
    
    public struct TruthfulnessStatus {
        public let dataId: String
        public let source: DataSource
        public let lastVerifiedOnline: Date?
        public let confidence: TruthfulnessConfidence
        public let staleness: Staleness
        public let reliability: Reliability
        public let syncStatus: SyncStatus
        public let visible: Bool // RULE: Offline truthfulness visible
    }
    
    public struct TruthfulnessReport {
        public let totalRecords: Int
        public let syncedRecords: Int
        public let pendingRecords: Int
        public let failedRecords: Int
        public let confidenceDistribution: [TruthfulnessConfidence: Int]
        public let generatedAt: Date
    }
    
    public enum DataType: String {
        case message
        case transaction
        case userProfile
        case configuration
        case cache
    }
    
    public enum DataSource: String {
        case backend
        case localCache
        case userInput
        case derived
    }
    
    public enum TruthfulnessConfidence: String {
        case high
        case medium
        case low
        case unknown
    }
    
    public enum Staleness: String {
        case fresh
        case recent
        case stale
        case veryStale
        case unknown
    }
    
    public enum Reliability: String {
        case high
        case medium
        case low
    }
    
    public enum SyncStatus: String {
        case pending
        case synced
        case failed
    }
}
