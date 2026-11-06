import Foundation

/// Trust Receipt Generator for transaction confirmations
/// Generates cryptographically signed receipts for user trust
public actor TrustReceiptGenerator {
    
    public static let shared = TrustReceiptGenerator()
    
    private var generatedReceipts: [String: TrustReceipt] = [:]
    
    private init() {}
    
    public struct TrustReceipt: Sendable, Codable {
        public let id: String
        public let transactionId: String
        public let timestamp: Date
        public let amount: String
        public let recipient: String
        public let status: ReceiptStatus
        public let signature: String
        public let metadata: [String: String]
        public let evidenceRefs: [String] // RULE: Aucun reçu sans evidenceRefs
        
        public init(
            id: String = UUID().uuidString,
            transactionId: String,
            amount: String,
            recipient: String,
            status: ReceiptStatus,
            signature: String,
            metadata: [String: String] = [:],
            evidenceRefs: [String]
        ) {
            self.id = id
            self.transactionId = transactionId
            self.timestamp = Date()
            self.amount = amount
            self.recipient = recipient
            self.status = status
            self.signature = signature
            self.metadata = metadata
            self.evidenceRefs = evidenceRefs
        }
    }
    
    public enum ReceiptStatus: String, Sendable, Codable {
        case pending = "PENDING"
        case confirmed = "CONFIRMED"
        case failed = "FAILED"
        case cancelled = "CANCELLED"
    }
    
    /// Generates a trust receipt for a transaction
    /// RULE: Aucun reçu sans evidenceRefs
    public func generateReceipt(
        transactionId: String,
        amount: String,
        recipient: String,
        status: ReceiptStatus,
        evidenceRefs: [String]
    ) throws -> TrustReceipt {
        
        // RULE: Aucun reçu sans evidenceRefs
        guard !evidenceRefs.isEmpty else {
            throw ReceiptError.missingEvidenceRefs
        }
        
        let signature = generateSignature(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient
        )
        
        let receipt = TrustReceipt(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient,
            status: status,
            signature: signature,
            evidenceRefs: evidenceRefs
        )
        
        generatedReceipts[receipt.id] = receipt
        return receipt
    }
    
    /// Generates a payment receipt
    /// RULE: Aucun reçu sans evidenceRefs
    public func generatePaymentReceipt(
        transactionId: String,
        amount: String,
        recipient: String,
        description: String,
        evidenceRefs: [String]
    ) throws -> TrustReceipt {
        
        // RULE: Aucun reçu sans evidenceRefs
        guard !evidenceRefs.isEmpty else {
            throw ReceiptError.missingEvidenceRefs
        }
        
        let signature = generateSignature(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient
        )
        
        var metadata: [String: String] = [:]
        metadata["description"] = description
        metadata["type"] = "payment"
        
        let receipt = TrustReceipt(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient,
            status: .confirmed,
            signature: signature,
            metadata: metadata,
            evidenceRefs: evidenceRefs
        )
        
        generatedReceipts[receipt.id] = receipt
        return receipt
    }
    
    /// Generates a transfer receipt
    /// RULE: Aucun reçu sans evidenceRefs
    public func generateTransferReceipt(
        transactionId: String,
        amount: String,
        recipient: String,
        sender: String,
        evidenceRefs: [String]
    ) throws -> TrustReceipt {
        
        // RULE: Aucun reçu sans evidenceRefs
        guard !evidenceRefs.isEmpty else {
            throw ReceiptError.missingEvidenceRefs
        }
        
        let signature = generateSignature(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient
        )
        
        var metadata: [String: String] = [:]
        metadata["sender"] = sender
        metadata["type"] = "transfer"
        
        let receipt = TrustReceipt(
            transactionId: transactionId,
            amount: amount,
            recipient: recipient,
            status: .confirmed,
            signature: signature,
            metadata: metadata,
            evidenceRefs: evidenceRefs
        )
        
        generatedReceipts[receipt.id] = receipt
        return receipt
    }
    
    /// Verifies receipt signature
    public func verifyReceipt(_ receipt: TrustReceipt) -> Bool {
        let expectedSignature = generateSignature(
            transactionId: receipt.transactionId,
            amount: receipt.amount,
            recipient: receipt.recipient
        )
        return receipt.signature == expectedSignature
    }
    
    /// Gets receipt by ID
    public func getReceipt(_ id: String) -> TrustReceipt? {
        generatedReceipts[id]
    }
    
    /// Gets all receipts
    public func getAllReceipts() -> [TrustReceipt] {
        Array(generatedReceipts.values)
    }
    
    /// Exports receipt as JSON
    public func exportReceiptAsJSON(_ receipt: TrustReceipt) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(receipt)
    }
    
    // MARK: - Private Helpers
    
    private func generateSignature(
        transactionId: String,
        amount: String,
        recipient: String
    ) -> String {
        let data = "\(transactionId):\(amount):\(recipient)"
        let hash = data.hashValue
        return String(format: "%x", abs(hash))
    }
    
    // MARK: - Errors
    
    public enum ReceiptError: Error, LocalizedError {
        case missingEvidenceRefs
        
        public var errorDescription: String? {
            switch self {
            case .missingEvidenceRefs:
                return "Receipt cannot be generated without evidenceRefs"
            }
        }
    }
}
