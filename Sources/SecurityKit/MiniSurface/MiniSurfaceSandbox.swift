//
//  MiniSurfaceSandbox.swift
//  CoreKit
//
//  Sandboxed execution environment for mini-surfaces
//  RULE: Mini-surfaces sandboxées

import Foundation
import WaanguCoreKit

public actor MiniSurfaceSandbox {
    
    public static let shared = MiniSurfaceSandbox()
    
    private var sandboxedSurfaces: [String: SandboxedSurface] = [:]
    private var blockedOperations: [BlockedOperation] = []
    
    private init() {}
    
    // MARK: - Sandbox Execution
    
    /// Executes mini-surface in sandbox
    /// RULE: Mini-surfaces sandboxées
    public func executeSandboxed(
        surfaceId: String,
        operation: SandboxOperation
    ) async throws -> SandboxResult {
        
        // Validate operation is allowed
        try validateOperation(operation)
        
        // Create sandbox environment
        let sandbox = SandboxEnvironment(
            surfaceId: surfaceId,
            allowedAPIs: getAllowedAPIs(),
            resourceLimits: getResourceLimits()
        )
        
        // Execute in sandbox
        let result = try await executeInSandbox(operation, environment: sandbox)
        
        // Record execution
        let sandboxedSurface = SandboxedSurface(
            surfaceId: surfaceId,
            executedAt: Date(),
            operation: operation.name,
            result: result
        )
        
        sandboxedSurfaces[surfaceId] = sandboxedSurface
        
        return result
    }
    
    // MARK: - Operation Validation
    
    private func validateOperation(_ operation: SandboxOperation) throws {
        
        // RULE: Mini-surfaces sandboxées - Block dangerous operations
        let forbiddenOperations = [
            "fileSystem.write",
            "fileSystem.delete",
            "network.request",
            "storage.write",
            "keychain.access",
            "camera.access",
            "location.access",
            "contacts.access",
            "eval",
            "exec"
        ]
        
        if forbiddenOperations.contains(operation.name) {
            let blocked = BlockedOperation(
                operation: operation.name,
                surfaceId: operation.surfaceId,
                reason: "Operation not allowed in sandbox",
                timestamp: Date()
            )
            
            blockedOperations.append(blocked)
            
            Task {
                await logBlockedOperation(blocked)
            }
            
            throw SandboxError.operationNotAllowed(operation: operation.name)
        }
    }
    
    private func getAllowedAPIs() -> Set<String> {
        [
            "ui.render",
            "ui.update",
            "data.read",
            "analytics.track",
            "navigation.navigate"
        ]
    }
    
    private func getResourceLimits() -> ResourceLimits {
        ResourceLimits(
            maxMemoryMB: 50,
            maxExecutionTimeSeconds: 5,
            maxNetworkRequests: 0 // No network allowed
        )
    }
    
    // MARK: - Sandbox Execution
    
    private func executeInSandbox(
        _ operation: SandboxOperation,
        environment: SandboxEnvironment
    ) async throws -> SandboxResult {
        
        let startTime = Date()
        
        // Check if API is allowed
        guard environment.allowedAPIs.contains(operation.name) else {
            throw SandboxError.apiNotAllowed(api: operation.name)
        }
        
        // Simulate execution with timeout
        let executionTime = Date().timeIntervalSince(startTime)
        
        if executionTime > environment.resourceLimits.maxExecutionTimeSeconds {
            throw SandboxError.executionTimeout(
                limit: environment.resourceLimits.maxExecutionTimeSeconds
            )
        }
        
        return SandboxResult(
            success: true,
            output: operation.parameters,
            executionTime: executionTime
        )
    }
    
    /// Gets blocked operations
    public func getBlockedOperations() -> [BlockedOperation] {
        blockedOperations
    }
    
    // MARK: - Logging
    
    private func logBlockedOperation(_ blocked: BlockedOperation) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .security,
            metadata: [
                "action": "sandbox_operation_blocked",
                "operation": blocked.operation,
                "surface_id": blocked.surfaceId,
                "reason": blocked.reason
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public struct SandboxOperation {
        public let surfaceId: String
        public let name: String
        public let parameters: [String: String]
        
        public init(surfaceId: String, name: String, parameters: [String: String]) {
            self.surfaceId = surfaceId
            self.name = name
            self.parameters = parameters
        }
    }
    
    public struct SandboxEnvironment {
        public let surfaceId: String
        public let allowedAPIs: Set<String>
        public let resourceLimits: ResourceLimits
    }
    
    public struct ResourceLimits {
        public let maxMemoryMB: Int
        public let maxExecutionTimeSeconds: TimeInterval
        public let maxNetworkRequests: Int
    }
    
    public struct SandboxResult {
        public let success: Bool
        public let output: [String: String]
        public let executionTime: TimeInterval
    }
    
    public struct SandboxedSurface {
        public let surfaceId: String
        public let executedAt: Date
        public let operation: String
        public let result: SandboxResult
    }
    
    public struct BlockedOperation {
        public let operation: String
        public let surfaceId: String
        public let reason: String
        public let timestamp: Date
    }
    
    public enum SandboxError: Error, LocalizedError {
        case operationNotAllowed(operation: String)
        case apiNotAllowed(api: String)
        case executionTimeout(limit: TimeInterval)
        case resourceLimitExceeded(resource: String)
        
        public var errorDescription: String? {
            switch self {
            case .operationNotAllowed(let operation):
                return "Operation '\(operation)' not allowed in sandbox"
            case .apiNotAllowed(let api):
                return "API '\(api)' not allowed in sandbox"
            case .executionTimeout(let limit):
                return "Execution timeout: exceeded \(limit) seconds"
            case .resourceLimitExceeded(let resource):
                return "Resource limit exceeded: \(resource)"
            }
        }
    }
}
