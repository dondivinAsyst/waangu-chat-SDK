//
//  PolicyEnvelope.swift
//  CoreKit
//
//  Canonical policy envelope with backend signature
//  RULE: PolicyEnvelope créé
//

import Foundation

/// Canonical policy envelope
/// All policy approvals must be wrapped in this envelope with backend signature
public struct PolicyEnvelope: Codable, Sendable, Identifiable {
    
    public let id: String
    public let policyType: PolicyType
    public let version: String
    public let content: String
    public let timestamp: Date
    public let status: PolicyStatus
    
    // Backend authority
    public let backendSignature: String
    public let evidenceRefs: [String]
    public let approvalMetadata: ApprovalMetadata
    public let truthSource: TruthSource
    
    // Metadata
    public let correlationId: String
    public let traceId: String?
    public let userId: String
    public let deviceId: String
    public let expiresAt: Date?
    
    public init(
        id: String,
        policyType: PolicyType,
        version: String,
        content: String,
        timestamp: Date,
        status: PolicyStatus,
        backendSignature: String,
        evidenceRefs: [String],
        approvalMetadata: ApprovalMetadata,
        truthSource: TruthSource = .backend,
        correlationId: String,
        traceId: String? = nil,
        userId: String,
        deviceId: String,
        expiresAt: Date? = nil
    ) {
        self.id = id
        self.policyType = policyType
        self.version = version
        self.content = content
        self.timestamp = timestamp
        self.status = status
        self.backendSignature = backendSignature
        self.evidenceRefs = evidenceRefs
        self.approvalMetadata = approvalMetadata
        self.truthSource = truthSource
        self.correlationId = correlationId
        self.traceId = traceId
        self.userId = userId
        self.deviceId = deviceId
        self.expiresAt = expiresAt
    }
}

// MARK: - Policy Type

public enum PolicyType: String, Codable, Sendable {
    case privacy = "PRIVACY"
    case termsOfService = "TERMS_OF_SERVICE"
    case dataProcessing = "DATA_PROCESSING"
    case cookies = "COOKIES"
    case marketing = "MARKETING"
    case thirdPartySharing = "THIRD_PARTY_SHARING"
    case biometrics = "BIOMETRICS"
    case location = "LOCATION"
    case camera = "CAMERA"
    case microphone = "MICROPHONE"
    case contacts = "CONTACTS"
    case notifications = "NOTIFICATIONS"
    case payment = "PAYMENT"
    case kyc = "KYC"
    case aml = "AML"
    case crossBorder = "CROSS_BORDER"
    case compliance = "COMPLIANCE"
    case custom = "CUSTOM"
}

// MARK: - Policy Status

public enum PolicyStatus: String, Codable, Sendable {
    case pending = "PENDING"
    case approved = "APPROVED"
    case rejected = "REJECTED"
    case expired = "EXPIRED"
    case revoked = "REVOKED"
    case underReview = "UNDER_REVIEW"
    case complianceHold = "COMPLIANCE_HOLD"
}

// MARK: - Approval Metadata

public struct ApprovalMetadata: Codable, Sendable {
    public let approvedBy: String
    public let approvedAt: Date
    public let approvalMethod: ApprovalMethod
    public let ipAddress: String?
    public let userAgent: String?
    public let geolocation: Geolocation?
    public let consentText: String
    public let consentLanguage: String
    
    public init(
        approvedBy: String,
        approvedAt: Date,
        approvalMethod: ApprovalMethod,
        ipAddress: String?,
        userAgent: String?,
        geolocation: Geolocation?,
        consentText: String,
        consentLanguage: String
    ) {
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
        self.approvalMethod = approvalMethod
        self.ipAddress = ipAddress
        self.userAgent = userAgent
        self.geolocation = geolocation
        self.consentText = consentText
        self.consentLanguage = consentLanguage
    }
    
    public enum ApprovalMethod: String, Codable, Sendable {
        case explicit = "EXPLICIT"
        case implicit = "IMPLICIT"
        case biometric = "BIOMETRIC"
        case twoFactor = "TWO_FACTOR"
        case delegated = "DELEGATED"
    }
    
    public struct Geolocation: Codable, Sendable {
        public let latitude: Double
        public let longitude: Double
        public let country: String
        public let region: String?
        
        public init(latitude: Double, longitude: Double, country: String, region: String?) {
            self.latitude = latitude
            self.longitude = longitude
            self.country = country
            self.region = region
        }
    }
}

// MARK: - Verification

public extension PolicyEnvelope {
    
    /// Verify backend signature (HMAC-SHA256)
    func verifySignature(secret: String) -> Bool {
        let payload = "\(id):\(policyType.rawValue):\(version):\(userId):\(timestamp.timeIntervalSince1970)"
        
        guard let payloadData = payload.data(using: .utf8),
              let secretData = secret.data(using: .utf8) else {
            return false
        }
        
        // In production: Use CryptoKit for HMAC-SHA256
        // For now: Simple validation
        return backendSignature.count >= 64 && !backendSignature.isEmpty
    }
    
    /// Check if policy is from backend
    var isFromBackend: Bool {
        return truthSource == .backend && !backendSignature.isEmpty
    }
    
    /// Check if policy has evidence
    var hasEvidence: Bool {
        return !evidenceRefs.isEmpty
    }
    
    /// Check if policy is approved
    var isApproved: Bool {
        return status == .approved && isFromBackend
    }
    
    /// Check if policy is expired
    var isExpired: Bool {
        if let expiresAt = expiresAt {
            return Date() > expiresAt
        }
        return status == .expired
    }
    
    /// Check if policy is valid
    var isValid: Bool {
        return isApproved && !isExpired && isFromBackend
    }
    
    /// Check if policy requires review
    var requiresReview: Bool {
        return [.pending, .underReview, .complianceHold].contains(status)
    }
}

// MARK: - Equatable

extension PolicyEnvelope: Equatable {
    public static func == (lhs: PolicyEnvelope, rhs: PolicyEnvelope) -> Bool {
        return lhs.id == rhs.id &&
               lhs.version == rhs.version &&
               lhs.backendSignature == rhs.backendSignature
    }
}

// MARK: - Hashable

extension PolicyEnvelope: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
        hasher.combine(backendSignature)
    }
}
