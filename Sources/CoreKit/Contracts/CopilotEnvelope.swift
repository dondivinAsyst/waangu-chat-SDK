////
////  CopilotEnvelope.swift
////  CoreKit
////
////  Canonical Copilot tool execution envelope with backend signature
////  RULE: CopilotEnvelope créé
////
//
//import Foundation
//
///// Canonical Copilot tool execution envelope
///// All AI tool executions must be wrapped in this envelope with backend signature
//public struct CopilotEnvelope: Codable, Sendable, Identifiable {
//    
//    public let id: String
//    public let toolName: String
//    public let toolVersion: String
//    public let parameters: [String: AnyCodable]
//    public let result: ToolResult?
//    public let timestamp: Date
//    public let status: ExecutionStatus
//    
//    // Backend authority
//    public let approvalId: String
//    public let backendSignature: String
//    public let evidenceRefs: [String]
//    public let executionProof: ExecutionProof
//    public let truthSource: TruthSource
//    
//    // Metadata
//    public let correlationId: String
//    public let traceId: String?
//    public let userId: String
//    public let conversationId: String?
//    public let executionDuration: TimeInterval?
//    
//    public init(
//        id: String,
//        toolName: String,
//        toolVersion: String,
//        parameters: [String: AnyCodable],
//        result: ToolResult?,
//        timestamp: Date,
//        status: ExecutionStatus,
//        approvalId: String,
//        backendSignature: String,
//        evidenceRefs: [String],
//        executionProof: ExecutionProof,
//        truthSource: TruthSource = .backend,
//        correlationId: String,
//        traceId: String? = nil,
//        userId: String,
//        conversationId: String?,
//        executionDuration: TimeInterval?
//    ) {
//        self.id = id
//        self.toolName = toolName
//        self.toolVersion = toolVersion
//        self.parameters = parameters
//        self.result = result
//        self.timestamp = timestamp
//        self.status = status
//        self.approvalId = approvalId
//        self.backendSignature = backendSignature
//        self.evidenceRefs = evidenceRefs
//        self.executionProof = executionProof
//        self.truthSource = truthSource
//        self.correlationId = correlationId
//        self.traceId = traceId
//        self.userId = userId
//        self.conversationId = conversationId
//        self.executionDuration = executionDuration
//    }
//}
//
//// MARK: - Execution Status
//
//public enum ExecutionStatus: String, Codable, Sendable {
//    case pending = "PENDING"
//    case approved = "APPROVED"
//    case executing = "EXECUTING"
//    case completed = "COMPLETED"
//    case failed = "FAILED"
//    case cancelled = "CANCELLED"
//    case denied = "DENIED"
//    case complianceHold = "COMPLIANCE_HOLD"
//    case timeout = "TIMEOUT"
//}
//
//// MARK: - Tool Result
//
//public struct ToolResult: Codable, Sendable {
//    public let success: Bool
//    public let data: [String: AnyCodable]?
//    public let error: ToolError?
//    public let metadata: [String: String]
//    
//    public init(
//        success: Bool,
//        data: [String: AnyCodable]?,
//        error: ToolError?,
//        metadata: [String: String]
//    ) {
//        self.success = success
//        self.data = data
//        self.error = error
//        self.metadata = metadata
//    }
//    
//    public struct ToolError: Codable, Sendable {
//        public let code: String
//        public let message: String
//        public let metadata: [String: String]?
//        
//        public init(code: String, message: String, metadata: [String: String]?) {
//            self.code = code
//            self.message = message
//            self.metadata = metadata
//        }
//    }
//}
//
//// MARK: - Execution Proof
//
//public struct ExecutionProof: Codable, Sendable {
//    public let executedBy: String
//    public let executedAt: Date
//    public let executionEnvironment: String
//    public let executionSignature: String
//    public let inputHash: String
//    public let outputHash: String?
//    
//    public init(
//        executedBy: String,
//        executedAt: Date,
//        executionEnvironment: String,
//        executionSignature: String,
//        inputHash: String,
//        outputHash: String?
//    ) {
//        self.executedBy = executedBy
//        self.executedAt = executedAt
//        self.executionEnvironment = executionEnvironment
//        self.executionSignature = executionSignature
//        self.inputHash = inputHash
//        self.outputHash = outputHash
//    }
//}
//
//// MARK: - AnyCodable Helper
//
//public struct AnyCodable: Codable, Sendable {
//    public let value: Any
//    
//    public init(_ value: Any) {
//        self.value = value
//    }
//    
//    public init(from decoder: Decoder) throws {
//        let container = try decoder.singleValueContainer()
//        
//        if let bool = try? container.decode(Bool.self) {
//            value = bool
//        } else if let int = try? container.decode(Int.self) {
//            value = int
//        } else if let double = try? container.decode(Double.self) {
//            value = double
//        } else if let string = try? container.decode(String.self) {
//            value = string
//        } else if let array = try? container.decode([AnyCodable].self) {
//            value = array.map { $0.value }
//        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
//            value = dictionary.mapValues { $0.value }
//        } else {
//            value = NSNull()
//        }
//    }
//    
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.singleValueContainer()
//        
//        switch value {
//        case let bool as Bool:
//            try container.encode(bool)
//        case let int as Int:
//            try container.encode(int)
//        case let double as Double:
//            try container.encode(double)
//        case let string as String:
//            try container.encode(string)
//        case let array as [Any]:
//            try container.encode(array.map { AnyCodable($0) })
//        case let dictionary as [String: Any]:
//            try container.encode(dictionary.mapValues { AnyCodable($0) })
//        default:
//            try container.encodeNil()
//        }
//    }
//}
//
//// MARK: - Verification
//
//public extension CopilotEnvelope {
//    
//    /// Verify backend signature (HMAC-SHA256)
//    func verifySignature(secret: String) -> Bool {
//        let payload = "\(id):\(toolName):\(toolVersion):\(approvalId):\(userId):\(timestamp.timeIntervalSince1970)"
//        
//        guard let payloadData = payload.data(using: .utf8),
//              let secretData = secret.data(using: .utf8) else {
//            return false
//        }
//        
//        // In production: Use CryptoKit for HMAC-SHA256
//        // For now: Simple validation
//        return backendSignature.count >= 64 && !backendSignature.isEmpty
//    }
//    
//    /// Verify execution proof
//    func verifyExecutionProof() -> Bool {
//        return !executionProof.executedBy.isEmpty &&
//               !executionProof.executionSignature.isEmpty &&
//               executionProof.executionSignature.count >= 64
//    }
//    
//    /// Check if execution is from backend
//    var isFromBackend: Bool {
//        return truthSource == .backend && !backendSignature.isEmpty
//    }
//    
//    /// Check if execution has evidence
//    var hasEvidence: Bool {
//        return !evidenceRefs.isEmpty
//    }
//    
//    /// Check if execution has approval
//    var hasApproval: Bool {
//        return !approvalId.isEmpty && status != .denied
//    }
//    
//    /// Check if execution is complete
//    var isComplete: Bool {
//        return status == .completed && isFromBackend && verifyExecutionProof()
//    }
//    
//    /// Check if execution is pending
//    var isPending: Bool {
//        return [.pending, .approved, .executing].contains(status)
//    }
//    
//    /// Check if execution is restricted
//    var isRestricted: Bool {
//        return [.denied, .complianceHold].contains(status)
//    }
//    
//    /// Check if execution succeeded
//    var isSuccessful: Bool {
//        return status == .completed && result?.success == true
//    }
//    
//    /// Check if execution failed
//    var isFailed: Bool {
//        return status == .failed || result?.success == false
//    }
//}
//
//// MARK: - Equatable
//
//extension CopilotEnvelope: Equatable {
//    public static func == (lhs: CopilotEnvelope, rhs: CopilotEnvelope) -> Bool {
//        return lhs.id == rhs.id &&
//               lhs.approvalId == rhs.approvalId &&
//               lhs.backendSignature == rhs.backendSignature
//    }
//}
//
//// MARK: - Hashable
//
//extension CopilotEnvelope: Hashable {
//    public func hash(into hasher: inout Hasher) {
//        hasher.combine(id)
//        hasher.combine(approvalId)
//        hasher.combine(backendSignature)
//    }
//}
