//
//  LandryGateway.swift
//  SecurityKit
//
//  Gateway for Landry service (Compliance/Regulatory)
//  Enforces all compliance checks through Landry backend
//

import Foundation
import WaanguCoreKit

/// Landry Gateway - Compliance and Regulatory Service
/// All compliance operations must go through Landry
public actor LandryGateway {
    
    public static let shared = LandryGateway()
    
    private var landryServiceURL: URL?
    private var isConfigured = false
    
    private init() {}
    
    public struct ComplianceCheck: Sendable {
        public let checkId: String
        public let checkType: CheckType
        public let userId: String
        public let jurisdiction: String
        public let timestamp: Date
        public let data: [String: String]
        
        public init(checkId: String, checkType: CheckType, userId: String, jurisdiction: String, timestamp: Date, data: [String: String]) {
            self.checkId = checkId
            self.checkType = checkType
            self.userId = userId
            self.jurisdiction = jurisdiction
            self.timestamp = timestamp
            self.data = data
        }
    }
    
    public struct ComplianceResult: Sendable {
        public let checkId: String
        public let compliant: Bool
        public let violations: [String]
        public let recommendations: [String]
        
        public init(checkId: String, compliant: Bool, violations: [String], recommendations: [String]) {
            self.checkId = checkId
            self.compliant = compliant
            self.violations = violations
            self.recommendations = recommendations
        }
    }
    
    public enum CheckType: String, Sendable {
        case kyc
        case aml
        case gdpr
        case dataRetention
        case crossBorder
        case contentModeration
    }
    
    public enum LandryError: Error, Sendable {
        case notConfigured
        case invalidURL
        case complianceViolation
        case networkError
    }
    
    // MARK: - Configuration
    
    public func configure(serviceURL: URL) {
        self.landryServiceURL = serviceURL
        self.isConfigured = true
        
        Task {
            await AuditBreadcrumb.shared.record(
                action: .dataViewed,
                category: .system,
                metadata: ["operation": "configure_landry_gateway", "url": serviceURL.absoluteString]
            )
        }
    }
    
    // MARK: - Compliance Operations
    
    public func checkCompliance(
        checkType: CheckType,
        userId: String,
        jurisdiction: String,
        data: [String: String] = [:]
    ) async throws -> ComplianceResult {
        guard isConfigured, let serviceURL = landryServiceURL else {
            throw LandryError.notConfigured
        }
        
        let check = ComplianceCheck(
            checkId: UUID().uuidString,
            checkType: checkType,
            userId: userId,
            jurisdiction: jurisdiction,
            timestamp: Date(),
            data: data
        )
        
        let result = try await performComplianceCheck(check: check, serviceURL: serviceURL)
        
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "operation": "compliance_check",
                "checkId": check.checkId,
                "type": checkType.rawValue,
                "compliant": "\(result.compliant)"
            ]
        )
        
        return result
    }
    
    // MARK: - Private Helpers
    
    private func performComplianceCheck(check: ComplianceCheck, serviceURL: URL) async throws -> ComplianceResult {
        // In production: actual HTTP request to Landry service
        // For now: mock result
        return ComplianceResult(
            checkId: check.checkId,
            compliant: true,
            violations: [],
            recommendations: []
        )
    }
}
