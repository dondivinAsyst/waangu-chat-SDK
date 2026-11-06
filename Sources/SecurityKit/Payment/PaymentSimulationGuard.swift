//
//  PaymentSimulationGuard.swift
//  CoreKit
//
//  Prevents local simulation of BRB/telco/card/SWIFT payment operations

import Foundation
import WaanguCoreKit

public actor PaymentSimulationGuard {
    
    public static let shared = PaymentSimulationGuard()
    
    private var paymentServiceURLs: [PaymentProvider: URL] = [:]
    private var simulationAttempts: [SimulationAttempt] = []
    private let enforceRemoteOnly = true
    
    private init() {}
    
    // MARK: - Configuration
    
    public func configurePaymentService(provider: PaymentProvider, serviceURL: URL) {
        paymentServiceURLs[provider] = serviceURL
    }
    
    // MARK: - Payment Validation
    
    public func validatePaymentOperation(_ operation: PaymentOperation) async throws {
        guard enforceRemoteOnly else { return }
        
        // Check if operation is local simulation
        if operation.isLocalSimulation {
            let attempt = SimulationAttempt(
                provider: operation.provider,
                operation: operation.type,
                amount: operation.amount,
                timestamp: Date()
            )
            
            simulationAttempts.append(attempt)
            await logSimulationAttempt(attempt)
            
            throw PaymentError.localSimulationForbidden(
                provider: operation.provider,
                operation: operation.type.rawValue
            )
        }
        
        // Validate operation goes through real payment service
        guard let serviceURL = paymentServiceURLs[operation.provider] else {
            throw PaymentError.paymentServiceNotConfigured(provider: operation.provider)
        }
        
        guard operation.endpoint.contains(serviceURL.host ?? "") else {
            throw PaymentError.invalidPaymentEndpoint(
                provider: operation.provider,
                endpoint: operation.endpoint
            )
        }
        
        // Validate operation has required headers
        try validatePaymentHeaders(operation)
    }
    
    private func validatePaymentHeaders(_ operation: PaymentOperation) throws {
        // Must have authentication
        guard operation.headers.contains(where: { $0.key == "Authorization" }) else {
            throw PaymentError.missingAuthHeader
        }
        
        // Must have idempotency key
        guard operation.headers.contains(where: { $0.key == "Idempotency-Key" }) else {
            throw PaymentError.missingIdempotencyKey
        }
        
        // Must have payment gateway signature
        let signatureHeader = "\(operation.provider.rawValue)-Signature"
        guard operation.headers.contains(where: { $0.key == signatureHeader }) else {
            throw PaymentError.missingPaymentSignature(provider: operation.provider)
        }
    }
    
    // MARK: - Success Validation
    
    public func validatePaymentSuccess(_ result: PaymentResult) throws {
        // Payment success cannot be determined locally
        // Must come from payment service
        
        guard result.source == .paymentService else {
            throw PaymentError.localSuccessForbidden(
                provider: result.provider,
                transactionId: result.transactionId
            )
        }
        
        // Validate result has payment service signature
        guard result.signature != nil else {
            throw PaymentError.unsignedPaymentResult
        }
        
        // Validate timestamp is recent (within 5 minutes)
        let age = Date().timeIntervalSince(result.timestamp)
        guard age < 300 else {
            throw PaymentError.stalePaymentResult(age: age)
        }
    }
    
    // MARK: - Forbidden Local Operations
    
    private let forbiddenLocalOperations: Set<PaymentOperationType> = [
        .moneyTransfer,
        .cardCharge,
        .swiftTransfer,
        .telcoPayment,
        .brbTransaction,
        .refund,
        .chargeback
    ]
    
    public func checkLocalOperation(_ operationType: PaymentOperationType) throws {
        if forbiddenLocalOperations.contains(operationType) {
            throw PaymentError.operationMustBeRemote(operation: operationType)
        }
    }
    
    // MARK: - Mock Detection
    
    public func detectMockPayment(_ operation: PaymentOperation) -> Bool {
        // Detect common mock patterns
        let mockPatterns = [
            "localhost",
            "127.0.0.1",
            "mock",
            "test",
            "sandbox",
            "simulator",
            "fake"
        ]
        
        for pattern in mockPatterns {
            if operation.endpoint.lowercased().contains(pattern) {
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Reporting
    
    public func getSimulationAttempts(limit: Int = 100) -> [SimulationAttempt] {
        Array(simulationAttempts.prefix(limit))
    }
    
    public func getPaymentReport() -> PaymentSecurityReport {
        let byProvider = Dictionary(grouping: simulationAttempts) { $0.provider }
        
        return PaymentSecurityReport(
            totalAttempts: simulationAttempts.count,
            attemptsByProvider: byProvider.mapValues { $0.count },
            configuredProviders: Array(paymentServiceURLs.keys),
            generatedAt: Date()
        )
    }
    
    public func clearAttempts() {
        simulationAttempts.removeAll()
    }
    
    // MARK: - Logging
    
    private func logSimulationAttempt(_ attempt: SimulationAttempt) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: [
                "violation": "payment_simulation_attempt",
                "provider": attempt.provider.rawValue,
                "operation": attempt.operation.rawValue,
                "amount": attempt.amount?.description ?? "unknown"
            ]
        )
    }
    
    // MARK: - Types
    
    public enum PaymentProvider: String, Codable {
        case brb = "BRB"
        case telco = "TELCO"
        case card = "CARD"
        case swift = "SWIFT"
        case mobileMoney = "MOBILE_MONEY"
    }
    
    public enum PaymentOperationType: String, Codable {
        case moneyTransfer
        case cardCharge
        case swiftTransfer
        case telcoPayment
        case brbTransaction
        case refund
        case chargeback
        case balanceCheck
    }
    
    public enum PaymentResultSource: String, Codable {
        case paymentService
        case local
        case cache
        case unknown
    }
    
    public struct PaymentOperation {
        public let provider: PaymentProvider
        public let type: PaymentOperationType
        public let endpoint: String
        public let headers: [String: String]
        public let amount: Decimal?
        public let isLocalSimulation: Bool
        
        public init(provider: PaymentProvider, type: PaymentOperationType, endpoint: String, headers: [String: String], amount: Decimal?, isLocalSimulation: Bool) {
            self.provider = provider
            self.type = type
            self.endpoint = endpoint
            self.headers = headers
            self.amount = amount
            self.isLocalSimulation = isLocalSimulation
        }
    }
    
    public struct PaymentResult {
        public let provider: PaymentProvider
        public let transactionId: String
        public let source: PaymentResultSource
        public let signature: String?
        public let timestamp: Date
        
        public init(provider: PaymentProvider, transactionId: String, source: PaymentResultSource, signature: String?, timestamp: Date) {
            self.provider = provider
            self.transactionId = transactionId
            self.source = source
            self.signature = signature
            self.timestamp = timestamp
        }
    }
    
    public struct SimulationAttempt {
        public let provider: PaymentProvider
        public let operation: PaymentOperationType
        public let amount: Decimal?
        public let timestamp: Date
    }
    
    public struct PaymentSecurityReport {
        public let totalAttempts: Int
        public let attemptsByProvider: [PaymentProvider: Int]
        public let configuredProviders: [PaymentProvider]
        public let generatedAt: Date
    }
    
    public enum PaymentError: Error, LocalizedError {
        case localSimulationForbidden(provider: PaymentProvider, operation: String)
        case paymentServiceNotConfigured(provider: PaymentProvider)
        case invalidPaymentEndpoint(provider: PaymentProvider, endpoint: String)
        case missingAuthHeader
        case missingIdempotencyKey
        case missingPaymentSignature(provider: PaymentProvider)
        case localSuccessForbidden(provider: PaymentProvider, transactionId: String)
        case unsignedPaymentResult
        case stalePaymentResult(age: TimeInterval)
        case operationMustBeRemote(operation: PaymentOperationType)
        
        public var errorDescription: String? {
            switch self {
            case .localSimulationForbidden(let provider, let operation):
                return "Local simulation forbidden: \(provider.rawValue) \(operation). Must use real payment service."
            case .paymentServiceNotConfigured(let provider):
                return "Payment service not configured: \(provider.rawValue)"
            case .invalidPaymentEndpoint(let provider, let endpoint):
                return "Invalid payment endpoint for \(provider.rawValue): \(endpoint)"
            case .missingAuthHeader:
                return "Missing Authorization header for payment operation"
            case .missingIdempotencyKey:
                return "Missing Idempotency-Key header for payment operation"
            case .missingPaymentSignature(let provider):
                return "Missing payment signature for \(provider.rawValue)"
            case .localSuccessForbidden(let provider, let transactionId):
                return "Local payment success forbidden: \(provider.rawValue) transaction \(transactionId). Success must come from payment service."
            case .unsignedPaymentResult:
                return "Payment result missing signature"
            case .stalePaymentResult(let age):
                return "Payment result is stale: \(Int(age)) seconds old"
            case .operationMustBeRemote(let operation):
                return "Operation must be remote: \(operation.rawValue). Local execution forbidden."
            }
        }
    }
}
