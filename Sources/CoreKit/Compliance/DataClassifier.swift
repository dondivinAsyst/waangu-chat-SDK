import Foundation

/// Classifies data as PII, Financial, Regulated, or Public
/// Ensures proper handling and encryption of sensitive data
public actor DataClassifier {
    
    public static let shared = DataClassifier()

    // Pas de cache : il gardait en mémoire, comme clé, chaque chaîne classée —
    // PII et données financières comprises, pour la vie du processus (Harness
    // §22, B05). Le classement n'est que quelques recherches de sous-chaîne.

    private init() {}
    
    public enum DataClassification: String, Sendable {
        case pii = "PII"
        case financial = "FINANCIAL"
        case regulated = "REGULATED"
        case public_data = "PUBLIC"
    }
    
    public func classify(_ data: String) -> DataClassification {
        performClassification(data)
    }
    
    private func performClassification(_ data: String) -> DataClassification {
        let lowerData = data.lowercased()
        
        // PII patterns
        if isPII(lowerData) {
            return .pii
        }
        
        // Financial patterns
        if isFinancial(lowerData) {
            return .financial
        }
        
        // Regulated patterns
        if isRegulated(lowerData) {
            return .regulated
        }
        
        return .public_data
    }
    
    private func isPII(_ data: String) -> Bool {
        let piiPatterns = [
            "email", "phone", "ssn", "passport", "license",
            "address", "dob", "date of birth", "name",
            "user_id", "account_id", "customer_id"
        ]
        return piiPatterns.contains { data.contains($0) }
    }
    
    private func isFinancial(_ data: String) -> Bool {
        let financialPatterns = [
            "card", "account", "balance", "transaction",
            "payment", "invoice", "credit", "debit",
            "amount", "currency", "bank", "routing"
        ]
        return financialPatterns.contains { data.contains($0) }
    }
    
    private func isRegulated(_ data: String) -> Bool {
        let regulatedPatterns = [
            "health", "medical", "prescription", "diagnosis",
            "treatment", "insurance", "claim", "policy",
            "compliance", "audit", "regulatory"
        ]
        return regulatedPatterns.contains { data.contains($0) }
    }
    
    public func requiresEncryption(_ classification: DataClassification) -> Bool {
        classification != .public_data
    }
    
    public func requiresAudit(_ classification: DataClassification) -> Bool {
        classification == .financial || classification == .regulated
    }
}
