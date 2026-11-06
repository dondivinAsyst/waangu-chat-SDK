//
//  MultiTenantGuard.swift
//  CoreKit
//
//  Prevents tenant data leakage and cross-tenant access

import Foundation
import WaanguCoreKit

public actor MultiTenantGuard {
    
    public static let shared = MultiTenantGuard()
    
    private var currentTenantId: String?
    private var tenantViolations: [TenantViolation] = []
    private let enforceIsolation = true
    
    private init() {}
    
    // MARK: - Tenant Context
    
    public func setCurrentTenant(_ tenantId: String) {
        currentTenantId = tenantId
    }
    
    public func getCurrentTenant() -> String? {
        currentTenantId
    }
    
    public func clearTenant() {
        currentTenantId = nil
    }
    
    // MARK: - Access Validation
    
    public func validateAccess(
        resourceTenantId: String,
        operation: TenantOperation
    ) async throws {
        guard enforceIsolation else { return }
        
        guard let currentTenant = currentTenantId else {
            throw TenantError.noTenantContext
        }
        
        // Tenant cannot access another tenant's data
        guard currentTenant == resourceTenantId else {
            let violation = TenantViolation(
                attemptedTenant: currentTenant,
                targetTenant: resourceTenantId,
                operation: operation,
                timestamp: Date()
            )
            
            tenantViolations.append(violation)
            await logViolation(violation)
            
            throw TenantError.crossTenantAccessDenied(
                from: currentTenant,
                to: resourceTenantId,
                operation: operation.rawValue
            )
        }
    }
    
    public func validateBulkAccess(
        resources: [(id: String, tenantId: String)],
        operation: TenantOperation
    ) async throws {
        guard let currentTenant = currentTenantId else {
            throw TenantError.noTenantContext
        }
        
        // Check all resources belong to current tenant
        let foreignResources = resources.filter { $0.tenantId != currentTenant }
        
        if !foreignResources.isEmpty {
            throw TenantError.bulkCrossTenantAccessDenied(
                tenant: currentTenant,
                foreignCount: foreignResources.count
            )
        }
    }
    
    // MARK: - Query Validation
    
    public func validateQuery(_ query: TenantQuery) throws {
        guard enforceIsolation else { return }
        
        guard let currentTenant = currentTenantId else {
            throw TenantError.noTenantContext
        }
        
        // Query must include tenant filter
        guard query.tenantFilter == currentTenant else {
            throw TenantError.queryMissingTenantFilter(
                query: query.name,
                expectedTenant: currentTenant
            )
        }
    }
    
    // MARK: - Data Isolation
    
    public func isolateData<T: TenantScoped>(_ data: [T]) async throws -> [T] {
        guard let currentTenant = currentTenantId else {
            throw TenantError.noTenantContext
        }
        
        // Filter out data from other tenants
        let isolated = data.filter { $0.tenantId == currentTenant }
        
        // Log if data was filtered
        if isolated.count < data.count {
            await logDataFiltering(
                total: data.count,
                filtered: isolated.count,
                tenant: currentTenant
            )
        }
        
        return isolated
    }
    
    // MARK: - Cache Isolation
    
    public func getCacheKey(baseKey: String) throws -> String {
        guard let currentTenant = currentTenantId else {
            throw TenantError.noTenantContext
        }
        
        // Prefix cache keys with tenant ID
        return "\(currentTenant):\(baseKey)"
    }
    
    // MARK: - Reporting
    
    public func getViolations(limit: Int = 100) -> [TenantViolation] {
        Array(tenantViolations.prefix(limit))
    }
    
    public func getTenantReport() -> TenantReport {
        let uniqueViolators = Set(tenantViolations.map { $0.attemptedTenant })
        let uniqueTargets = Set(tenantViolations.map { $0.targetTenant })
        
        return TenantReport(
            currentTenant: currentTenantId,
            totalViolations: tenantViolations.count,
            uniqueViolators: uniqueViolators.count,
            uniqueTargets: uniqueTargets.count,
            violations: Array(tenantViolations.prefix(10)),
            generatedAt: Date()
        )
    }
    
    public func clearViolations() {
        tenantViolations.removeAll()
    }
    
    // MARK: - Logging
    
    private func logViolation(_ violation: TenantViolation) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "cross_tenant_access",
                "attempted_tenant": violation.attemptedTenant,
                "target_tenant": violation.targetTenant,
                "operation": violation.operation.rawValue
            ]
        )
    }
    
    private func logDataFiltering(total: Int, filtered: Int, tenant: String) async {
        await AuditBreadcrumb.shared.record(
            action: .dataViewed,
            category: .security,
            metadata: [
                "action": "tenant_data_filtering",
                "total_records": String(total),
                "filtered_records": String(filtered),
                "removed_records": String(total - filtered),
                "tenant": tenant
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public enum TenantOperation: String, Codable {
        case read
        case write
        case delete
        case query
        case cache
    }
    
    public struct TenantViolation: Codable {
        public let attemptedTenant: String
        public let targetTenant: String
        public let operation: TenantOperation
        public let timestamp: Date
    }
    
    public struct TenantQuery {
        public let name: String
        public let tenantFilter: String?
        
        public init(name: String, tenantFilter: String?) {
            self.name = name
            self.tenantFilter = tenantFilter
        }
    }
    
    public struct TenantReport {
        public let currentTenant: String?
        public let totalViolations: Int
        public let uniqueViolators: Int
        public let uniqueTargets: Int
        public let violations: [TenantViolation]
        public let generatedAt: Date
    }
    
    public enum TenantError: Error, LocalizedError {
        case noTenantContext
        case crossTenantAccessDenied(from: String, to: String, operation: String)
        case bulkCrossTenantAccessDenied(tenant: String, foreignCount: Int)
        case queryMissingTenantFilter(query: String, expectedTenant: String)
        
        public var errorDescription: String? {
            switch self {
            case .noTenantContext:
                return "No tenant context set. Cannot perform operation."
            case .crossTenantAccessDenied(let from, let to, let operation):
                return "Cross-tenant access denied: Tenant '\(from)' cannot \(operation) data from tenant '\(to)'"
            case .bulkCrossTenantAccessDenied(let tenant, let count):
                return "Bulk cross-tenant access denied: Tenant '\(tenant)' attempted to access \(count) foreign resources"
            case .queryMissingTenantFilter(let query, let tenant):
                return "Query '\(query)' missing tenant filter. Expected tenant: \(tenant)"
            }
        }
    }
}

// MARK: - Protocol

public protocol TenantScoped {
    var tenantId: String { get }
}
