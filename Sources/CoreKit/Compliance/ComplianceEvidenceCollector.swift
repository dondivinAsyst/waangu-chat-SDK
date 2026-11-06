import Foundation

/// Collects compliance evidence for ISO/NIST standards
/// Generates audit trails and compliance reports
public actor ComplianceEvidenceCollector {
    
    public static let shared = ComplianceEvidenceCollector()
    
    private var evidenceRecords: [ComplianceEvidence] = []
    private let maxRecords = 10000
    
    private init() {}
    
    public struct ComplianceEvidence: Sendable, Codable {
        public let id: String
        public let standard: ComplianceStandard
        public let requirement: String
        public let evidence: String
        public let timestamp: Date
        public let verified: Bool
    }
    
    public enum ComplianceStandard: String, Sendable, Codable {
        case iso27001 = "ISO27001"
        case iso27002 = "ISO27002"
        case nist_csf = "NIST_CSF"
        case nist_sp800_53 = "NIST_SP800_53"
        case gdpr = "GDPR"
        case hipaa = "HIPAA"
    }
    
    /// Records compliance evidence
    public func recordEvidence(
        standard: ComplianceStandard,
        requirement: String,
        evidence: String,
        verified: Bool = true
    ) {
        let record = ComplianceEvidence(
            id: UUID().uuidString,
            standard: standard,
            requirement: requirement,
            evidence: evidence,
            timestamp: Date(),
            verified: verified
        )
        
        evidenceRecords.append(record)
        
        // Keep only recent records
        if evidenceRecords.count > maxRecords {
            evidenceRecords.removeFirst()
        }
    }
    
    /// Gets all evidence for a standard
    public func getEvidenceFor(_ standard: ComplianceStandard) -> [ComplianceEvidence] {
        evidenceRecords.filter { $0.standard == standard }
    }
    
    /// Generates compliance report
    public func generateReport(for standard: ComplianceStandard) -> ComplianceReport {
        let evidence = getEvidenceFor(standard)
        let verified = evidence.filter { $0.verified }.count
        let total = evidence.count
        
        return ComplianceReport(
            standard: standard,
            totalRequirements: total,
            verifiedRequirements: verified,
            compliancePercentage: total > 0 ? Double(verified) / Double(total) * 100 : 0,
            evidence: evidence,
            generatedAt: Date()
        )
    }
    
    /// Exports evidence as JSON
    public func exportAsJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(evidenceRecords)
    }
    
    /// Clears all evidence
    public func clearEvidence() {
        evidenceRecords.removeAll()
    }
}

public struct ComplianceReport: Sendable {
    public let standard: ComplianceEvidenceCollector.ComplianceStandard
    public let totalRequirements: Int
    public let verifiedRequirements: Int
    public let compliancePercentage: Double
    public let evidence: [ComplianceEvidenceCollector.ComplianceEvidence]
    public let generatedAt: Date
}
