//
//  PlatformParityValidator.swift
//  CoreKit
//
//  Ensures iOS cannot diverge from Jetpack/Web implementations

import Foundation
import CryptoKit

public actor PlatformParityValidator {
    
    public static let shared = PlatformParityValidator()
    
    private var contractHashes: [String: PlatformHashes] = [:]
    private var parityViolations: [ParityViolation] = []
    
    private init() {}
    
    // MARK: - Contract Registration
    
    public func registerContract(
        name: String,
        iosHash: String,
        jetpackHash: String,
        webHash: String
    ) {
        contractHashes[name] = PlatformHashes(
            ios: iosHash,
            jetpack: jetpackHash,
            web: webHash,
            registeredAt: Date()
        )
    }
    
    // MARK: - Parity Validation
    
    public func validateParity(contractName: String) async throws {
        guard let hashes = contractHashes[contractName] else {
            throw ParityError.contractNotRegistered(name: contractName)
        }
        
        // iOS must match Jetpack and Web
        let violations = checkDivergence(hashes: hashes, contractName: contractName)
        
        if !violations.isEmpty {
            let violation = ParityViolation(
                contractName: contractName,
                platform: .ios,
                divergences: violations,
                timestamp: Date()
            )
            
            parityViolations.append(violation)
            
            await logViolation(violation)
            
            throw ParityError.platformDivergence(
                contract: contractName,
                divergences: violations
            )
        }
    }
    
    private func checkDivergence(hashes: PlatformHashes, contractName: String) -> [String] {
        var divergences: [String] = []
        
        if hashes.ios != hashes.jetpack {
            divergences.append("iOS diverges from Jetpack")
        }
        
        if hashes.ios != hashes.web {
            divergences.append("iOS diverges from Web")
        }
        
        return divergences
    }
    
    // MARK: - Feature Parity
    
    public func validateFeatureParity(
        feature: String,
        iosImplemented: Bool,
        jetpackImplemented: Bool,
        webImplemented: Bool
    ) async throws {
        
        // If Jetpack or Web has it, iOS must have it
        if (jetpackImplemented || webImplemented) && !iosImplemented {
            throw ParityError.featureMissing(
                feature: feature,
                platform: .ios,
                availableOn: jetpackImplemented ? "Jetpack" : "Web"
            )
        }
        
        // If iOS has it, others must have it (or be in progress)
        if iosImplemented && !jetpackImplemented && !webImplemented {
            await logWarning(
                feature: feature,
                message: "iOS has feature but Jetpack/Web don't"
            )
        }
    }
    
    // MARK: - API Contract Validation
    
    public func validateAPIContract(
        endpoint: String,
        iosVersion: String,
        jetpackVersion: String,
        webVersion: String
    ) throws {
        
        guard iosVersion == jetpackVersion && iosVersion == webVersion else {
            throw ParityError.apiVersionMismatch(
                endpoint: endpoint,
                ios: iosVersion,
                jetpack: jetpackVersion,
                web: webVersion
            )
        }
    }
    
    // MARK: - Data Model Validation
    
    public func validateDataModel<T: Codable>(
        modelName: String,
        iosModel: T.Type,
        expectedHash: String
    ) throws {
        
        // Generate hash of iOS model structure
        let modelDescription = String(describing: iosModel)
        let data = Data(modelDescription.utf8)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        guard hashString == expectedHash else {
            throw ParityError.dataModelDivergence(
                model: modelName,
                platform: .ios,
                expectedHash: expectedHash,
                actualHash: String(hashString.prefix(16))
            )
        }
    }
    
    // MARK: - Reporting
    
    public func getParityReport() -> ParityReport {
        let totalContracts = contractHashes.count
        let violatedContracts = Set(parityViolations.map { $0.contractName }).count
        let parityScore = totalContracts > 0 ? Double(totalContracts - violatedContracts) / Double(totalContracts) * 100 : 100
        
        return ParityReport(
            totalContracts: totalContracts,
            violatedContracts: violatedContracts,
            parityScore: parityScore,
            violations: parityViolations,
            generatedAt: Date()
        )
    }
    
    public func getViolations(limit: Int = 100) -> [ParityViolation] {
        Array(parityViolations.prefix(limit))
    }
    
    public func clearViolations() {
        parityViolations.removeAll()
    }
    
    // MARK: - Logging
    
    private func logViolation(_ violation: ParityViolation) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "platform_parity_divergence",
                "contract": violation.contractName,
                "platform": violation.platform.rawValue,
                "divergences": violation.divergences.joined(separator: ", ")
            ]
        )
    }
    
    private func logWarning(feature: String, message: String) async {
        await AuditBreadcrumb.shared.record(
            action: .errorOccurred,
            category: .system,
            metadata: [
                "warning": "platform_parity_warning",
                "feature": feature,
                "message": message
            ],
            severity: .warning
        )
    }
    
    // MARK: - Types
    
    public enum Platform: String, Codable {
        case ios = "iOS"
        case jetpack = "Jetpack"
        case web = "Web"
    }
    
    public struct PlatformHashes {
        let ios: String
        let jetpack: String
        let web: String
        let registeredAt: Date
    }
    
    public struct ParityViolation: Codable {
        let contractName: String
        let platform: Platform
        let divergences: [String]
        let timestamp: Date
    }
    
    public struct ParityReport {
        public let totalContracts: Int
        public let violatedContracts: Int
        public let parityScore: Double
        public let violations: [ParityViolation]
        public let generatedAt: Date
    }
    
    public enum ParityError: Error, LocalizedError {
        case contractNotRegistered(name: String)
        case platformDivergence(contract: String, divergences: [String])
        case featureMissing(feature: String, platform: Platform, availableOn: String)
        case apiVersionMismatch(endpoint: String, ios: String, jetpack: String, web: String)
        case dataModelDivergence(model: String, platform: Platform, expectedHash: String, actualHash: String)
        
        public var errorDescription: String? {
            switch self {
            case .contractNotRegistered(let name):
                return "Contract not registered: \(name)"
            case .platformDivergence(let contract, let divergences):
                return "Platform divergence in \(contract): \(divergences.joined(separator: ", "))"
            case .featureMissing(let feature, let platform, let availableOn):
                return "Feature '\(feature)' missing on \(platform.rawValue) but available on \(availableOn)"
            case .apiVersionMismatch(let endpoint, let ios, let jetpack, let web):
                return "API version mismatch for \(endpoint): iOS=\(ios), Jetpack=\(jetpack), Web=\(web)"
            case .dataModelDivergence(let model, let platform, let expected, let actual):
                return "Data model '\(model)' diverged on \(platform.rawValue): expected=\(expected), actual=\(actual)"
            }
        }
    }
}
