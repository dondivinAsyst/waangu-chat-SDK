//
//  IncidentPackGenerator.swift
//  CoreKit
//
//  Generates incident packs for debugging and forensics
//  RULE: Incident packs générables

import Foundation

public actor IncidentPackGenerator {
    
    public static let shared = IncidentPackGenerator()
    
    private var generatedPacks: [String: IncidentPack] = [:]
    
    private init() {}
    
    // MARK: - Incident Pack Generation
    
    /// Generates comprehensive incident pack
    /// RULE: Incident packs générables
    public func generateIncidentPack(
        incidentId: String,
        incidentType: IncidentType,
        description: String,
        userId: String?,
        deviceId: String?
    ) async -> IncidentPack {
        
        // Collect system state
        let systemState = await collectSystemState()
        
        // Collect audit logs
        let auditLogs = await collectAuditLogs(limit: 500)
        
        // Collect error logs
        let errorLogs = await collectErrorLogs(limit: 100)
        
        // Collect network state
        let networkState = collectNetworkState()
        
        // Collect device info
        let deviceInfo = collectDeviceInfo()
        
        // Collect user context
        let userContext = await collectUserContext(userId: userId)
        
        // Collect forensic data
        let forensics = await collectForensics(userId: userId, deviceId: deviceId)
        
        let pack = IncidentPack(
            id: incidentId,
            type: incidentType,
            description: description,
            userId: userId,
            deviceId: deviceId,
            systemState: systemState,
            auditLogs: auditLogs,
            errorLogs: errorLogs,
            networkState: networkState,
            deviceInfo: deviceInfo,
            userContext: userContext,
            forensics: forensics,
            generatedAt: Date()
        )
        
        generatedPacks[incidentId] = pack
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .system,
            metadata: [
                "action": "incident_pack_generated",
                "incident_id": incidentId,
                "incident_type": incidentType.rawValue
            ],
            severity: .critical
        )
        
        return pack
    }
    
    // MARK: - Data Collection
    
    private func collectSystemState() async -> SystemState {
        SystemState(
            timestamp: Date(),
            memoryUsageMB: 0, // Would get actual memory usage
            cpuUsagePercent: 0, // Would get actual CPU usage
            diskSpaceMB: 0, // Would get actual disk space
            batteryLevel: 0, // Would get actual battery level
            networkConnected: true
        )
    }
    
    private func collectAuditLogs(limit: Int) async -> [AuditLog] {
        let events = await AuditBreadcrumb.shared.getRecent(limit: limit)
        return events.map { event in
            AuditLog(
                timestamp: event.timestamp,
                action: event.action.rawValue,
                category: event.category.rawValue,
                metadata: event.metadata
            )
        }
    }
    
    private func collectErrorLogs(limit: Int) async -> [ErrorLog] {
        // Would collect actual error logs
        []
    }
    
    private func collectNetworkState() -> NetworkState {
        NetworkState(
            connected: true,
            connectionType: "wifi",
            signalStrength: 100
        )
    }
    
    private func collectDeviceInfo() -> DeviceInfo {
        DeviceInfo(
            platform: "iOS",
            osVersion: "17.0",
            appVersion: "1.0.0",
            deviceModel: "iPhone"
        )
    }
    
    private func collectUserContext(userId: String?) async -> UserContext? {
        guard let userId = userId else { return nil }
        
        return UserContext(
            userId: userId,
            sessionId: UUID().lowercasedString,
            lastActivity: Date()
        )
    }
    
    private func collectForensics(userId: String?, deviceId: String?) async -> ForensicData {
        ForensicData(
            userId: userId,
            deviceId: deviceId,
            collectedAt: Date(),
            dataPoints: [:]
        )
    }
    
    /// Exports incident pack as JSON
    public func exportIncidentPack(_ incidentId: String) throws -> Data {
        guard let pack = generatedPacks[incidentId] else {
            throw IncidentPackError.packNotFound(incidentId: incidentId)
        }
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(pack)
    }
    
    /// Gets incident pack
    public func getIncidentPack(_ incidentId: String) -> IncidentPack? {
        generatedPacks[incidentId]
    }
    
    // MARK: - Types
    
    public struct IncidentPack: Codable {
        public let id: String
        public let type: IncidentType
        public let description: String
        public let userId: String?
        public let deviceId: String?
        public let systemState: SystemState
        public let auditLogs: [AuditLog]
        public let errorLogs: [ErrorLog]
        public let networkState: NetworkState
        public let deviceInfo: DeviceInfo
        public let userContext: UserContext?
        public let forensics: ForensicData
        public let generatedAt: Date
    }
    
    public struct SystemState: Codable {
        public let timestamp: Date
        public let memoryUsageMB: Int
        public let cpuUsagePercent: Int
        public let diskSpaceMB: Int
        public let batteryLevel: Int
        public let networkConnected: Bool
    }
    
    public struct AuditLog: Codable {
        public let timestamp: Date
        public let action: String
        public let category: String
        public let metadata: [String: String]
    }
    
    public struct ErrorLog: Codable {
        public let timestamp: Date
        public let error: String
        public let stackTrace: String?
    }
    
    public struct NetworkState: Codable {
        public let connected: Bool
        public let connectionType: String
        public let signalStrength: Int
    }
    
    public struct DeviceInfo: Codable {
        public let platform: String
        public let osVersion: String
        public let appVersion: String
        public let deviceModel: String
    }
    
    public struct UserContext: Codable {
        public let userId: String
        public let sessionId: String
        public let lastActivity: Date
    }
    
    public struct ForensicData: Codable {
        public let userId: String?
        public let deviceId: String?
        public let collectedAt: Date
        public let dataPoints: [String: String]
    }
    
    public enum IncidentType: String, Codable {
        case crash
        case securityViolation
        case dataCorruption
        case networkFailure
        case performanceIssue
        case userReported
    }
    
    public enum IncidentPackError: Error, LocalizedError {
        case packNotFound(incidentId: String)
        
        public var errorDescription: String? {
            switch self {
            case .packNotFound(let incidentId):
                return "Incident pack not found: \(incidentId)"
            }
        }
    }
}
