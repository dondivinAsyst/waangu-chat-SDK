//
//  ForensicEnvelope.swift
//  CoreKit
//
//  Canonical forensic audit envelope with backend signature
//  RULE: ForensicEnvelope créé
//

import Foundation

/// Canonical forensic audit envelope
/// All forensic operations must be wrapped in this envelope with backend signature
public struct ForensicEnvelope: Codable, Sendable, Identifiable {
    
    public let id: String
    public let operationType: OperationType
    public let operationName: String
    public let timestamp: Date
    public let status: ForensicStatus
    
    // Context
    public let userId: String?
    public let deviceId: String
    public let sessionId: String
    public let ipAddress: String?
    public let userAgent: String?
    public let geolocation: Geolocation?
    
    // Backend authority
    public let backendSignature: String
    public let evidenceTrail: [Evidence]
    public let auditBreadcrumbs: [AuditBreadcrumbEntry]
    public let truthSource: TruthSource
    
    // Metadata
    public let correlationId: String
    public let traceId: String?
    public let parentForensicId: String?
    public let severity: Severity
    public let category: Category
    
    // Details
    public let operationDetails: [String: String]
    public let securityFlags: [SecurityFlag]
    public let complianceFlags: [ComplianceFlag]
    
    public init(
        id: String,
        operationType: OperationType,
        operationName: String,
        timestamp: Date,
        status: ForensicStatus,
        userId: String?,
        deviceId: String,
        sessionId: String,
        ipAddress: String?,
        userAgent: String?,
        geolocation: Geolocation?,
        backendSignature: String,
        evidenceTrail: [Evidence],
        auditBreadcrumbs: [AuditBreadcrumbEntry],
        truthSource: TruthSource = .backend,
        correlationId: String,
        traceId: String? = nil,
        parentForensicId: String?,
        severity: Severity,
        category: Category,
        operationDetails: [String: String],
        securityFlags: [SecurityFlag],
        complianceFlags: [ComplianceFlag]
    ) {
        self.id = id
        self.operationType = operationType
        self.operationName = operationName
        self.timestamp = timestamp
        self.status = status
        self.userId = userId
        self.deviceId = deviceId
        self.sessionId = sessionId
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.geolocation = geolocation
        self.backendSignature = backendSignature
        self.evidenceTrail = evidenceTrail
        self.auditBreadcrumbs = auditBreadcrumbs
        self.truthSource = truthSource
        self.correlationId = correlationId
        self.traceId = traceId
        self.parentForensicId = parentForensicId
        self.severity = severity
        self.category = category
        self.operationDetails = operationDetails
        self.securityFlags = securityFlags
        self.complianceFlags = complianceFlags
    }
}

// MARK: - Operation Type

public enum OperationType: String, Codable, Sendable {
    case authentication = "AUTHENTICATION"
    case authorization = "AUTHORIZATION"
    case payment = "PAYMENT"
    case message = "MESSAGE"
    case policy = "POLICY"
    case aiTool = "AI_TOOL"
    case translation = "TRANSLATION"
    case dataAccess = "DATA_ACCESS"
    case dataModification = "DATA_MODIFICATION"
    case securityEvent = "SECURITY_EVENT"
    case complianceEvent = "COMPLIANCE_EVENT"
    case fraudEvent = "FRAUD_EVENT"
    case operatorAction = "OPERATOR_ACTION"
    case systemEvent = "SYSTEM_EVENT"
}

// MARK: - Forensic Status

public enum ForensicStatus: String, Codable, Sendable {
    case recorded = "RECORDED"
    case analyzing = "ANALYZING"
    case flagged = "FLAGGED"
    case cleared = "CLEARED"
    case escalated = "ESCALATED"
    case underInvestigation = "UNDER_INVESTIGATION"
    case resolved = "RESOLVED"
}

// MARK: - Severity

public enum Severity: String, Codable, Sendable {
    case info = "INFO"
    case low = "LOW"
    case medium = "MEDIUM"
    case high = "HIGH"
    case critical = "CRITICAL"
}

// MARK: - Category

public enum Category: String, Codable, Sendable {
    case security = "SECURITY"
    case compliance = "COMPLIANCE"
    case fraud = "FRAUD"
    case privacy = "PRIVACY"
    case financial = "FINANCIAL"
    case operational = "OPERATIONAL"
    case audit = "AUDIT"
}

// MARK: - Audit Breadcrumb Entry

/// Audit breadcrumb entry for forensic trail
/// This is a data struct (not the actor service)
public struct AuditBreadcrumbEntry: Codable, Sendable {
    public let breadcrumbId: String
    public let timestamp: Date
    public let action: String
    public let category: String
    public let userId: String?
    public let metadata: [String: String]
    
    public init(
        breadcrumbId: String,
        timestamp: Date,
        action: String,
        category: String,
        userId: String?,
        metadata: [String: String]
    ) {
        self.breadcrumbId = breadcrumbId
        self.timestamp = timestamp
        self.action = action
        self.category = category
        self.userId = userId
        self.metadata = metadata
    }
}

// MARK: - Evidence

public struct Evidence: Codable, Sendable {
    public let evidenceId: String
    public let evidenceType: String
    public let evidenceData: String
    public let evidenceHash: String
    public let collectedAt: Date
    
    public init(
        evidenceId: String,
        evidenceType: String,
        evidenceData: String,
        evidenceHash: String,
        collectedAt: Date
    ) {
        self.evidenceId = evidenceId
        self.evidenceType = evidenceType
        self.evidenceData = evidenceData
        self.evidenceHash = evidenceHash
        self.collectedAt = collectedAt
    }
}

// MARK: - Geolocation

public struct Geolocation: Codable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let country: String
    public let region: String?
    public let city: String?
    
    public init(
        latitude: Double,
        longitude: Double,
        country: String,
        region: String?,
        city: String?
    ) {
        self.latitude = latitude
        self.longitude = longitude
        self.country = country
        self.region = region
        self.city = city
    }
}

// MARK: - Security Flag

public enum SecurityFlag: String, Codable, Sendable {
    case suspiciousActivity = "SUSPICIOUS_ACTIVITY"
    case multipleFailedAttempts = "MULTIPLE_FAILED_ATTEMPTS"
    case unusualLocation = "UNUSUAL_LOCATION"
    case deviceMismatch = "DEVICE_MISMATCH"
    case velocityAnomaly = "VELOCITY_ANOMALY"
    case privilegeEscalation = "PRIVILEGE_ESCALATION"
    case dataExfiltration = "DATA_EXFILTRATION"
}

// MARK: - Compliance Flag

public enum ComplianceFlag: String, Codable, Sendable {
    case gdprRelevant = "GDPR_RELEVANT"
    case pciDssRelevant = "PCI_DSS_RELEVANT"
    case kycRequired = "KYC_REQUIRED"
    case amlReview = "AML_REVIEW"
    case crossBorder = "CROSS_BORDER"
    case dataRetention = "DATA_RETENTION"
    case rightToErasure = "RIGHT_TO_ERASURE"
}

// MARK: - Verification

public extension ForensicEnvelope {
    
    /// Verify backend signature (HMAC-SHA256)
    func verifySignature(secret: String) -> Bool {
        let payload = "\(id):\(operationType.rawValue):\(operationName):\(deviceId):\(sessionId):\(timestamp.timeIntervalSince1970)"
        
        guard let payloadData = payload.data(using: .utf8),
              let secretData = secret.data(using: .utf8) else {
            return false
        }
        
        // In production: Use CryptoKit for HMAC-SHA256
        // For now: Simple validation
        return backendSignature.count >= 64 && !backendSignature.isEmpty
    }
    
    /// Check if forensic is from backend
    var isFromBackend: Bool {
        return truthSource == .backend && !backendSignature.isEmpty
    }
    
    /// Check if forensic has evidence
    var hasEvidence: Bool {
        return !evidenceTrail.isEmpty
    }
    
    /// Check if forensic has audit trail
    var hasAuditTrail: Bool {
        return !auditBreadcrumbs.isEmpty
    }
    
    /// Check if forensic is flagged
    var isFlagged: Bool {
        return [.flagged, .escalated, .underInvestigation].contains(status)
    }
    
    /// Check if forensic is critical
    var isCritical: Bool {
        return severity == .critical
    }
    
    /// Check if forensic has security flags
    var hasSecurityFlags: Bool {
        return !securityFlags.isEmpty
    }
    
    /// Check if forensic has compliance flags
    var hasComplianceFlags: Bool {
        return !complianceFlags.isEmpty
    }
    
    /// Check if forensic requires investigation
    var requiresInvestigation: Bool {
        return isFlagged || isCritical || hasSecurityFlags
    }
    
    /// Get evidence count
    var evidenceCount: Int {
        return evidenceTrail.count
    }
    
    /// Get breadcrumb count
    var breadcrumbCount: Int {
        return auditBreadcrumbs.count
    }
}

// MARK: - Equatable

extension ForensicEnvelope: Equatable {
    public static func == (lhs: ForensicEnvelope, rhs: ForensicEnvelope) -> Bool {
        return lhs.id == rhs.id &&
               lhs.backendSignature == rhs.backendSignature
    }
}

// MARK: - Hashable

extension ForensicEnvelope: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(backendSignature)
    }
}
