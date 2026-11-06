import Foundation
import WaanguCoreKit
import CryptoKit

/// Verifies signed push notifications to prevent spoofing
/// Uses HMAC-SHA256 for signature verification
public actor SignedPushVerifier: SignedPushVerifierProtocol {
    
    public static let shared = SignedPushVerifier()
    
    private var signingKey: SymmetricKey?
    private let signatureHeader = "X-Push-Signature"
    private let timestampHeader = "X-Push-Timestamp"
    private let maxAge: TimeInterval = 300 // 5 minutes
    
    private init() {}
    
    // MARK: - Configuration
    
    /// Set the signing key for verification
    public func setSigningKey(_ key: Data) async {
        self.signingKey = SymmetricKey(data: key)
    }
    
    /// Set signing key from base64 string
    public func setSigningKey(base64: String) async throws {
        guard let data = Data(base64Encoded: base64) else {
            throw PushVerificationError.invalidSigningKey
        }
        self.signingKey = SymmetricKey(data: data)
    }
    
    // MARK: - Verification
    
    /// Verify push notification payload
    public func verify(
        payload: [String: Any],
        signature: String,
        timestamp: String
    ) async throws -> VerifiedPush {
        // Check if signing key is configured
        guard let key = signingKey else {
            throw PushVerificationError.signingKeyNotConfigured
        }
        
        // Verify timestamp freshness
        guard let timestampValue = TimeInterval(timestamp) else {
            throw PushVerificationError.invalidTimestamp
        }
        
        let pushTime = Date(timeIntervalSince1970: timestampValue)
        let age = Date().timeIntervalSince(pushTime)
        
        guard age >= 0 && age <= maxAge else {
            throw PushVerificationError.timestampExpired(age: age)
        }
        
        // Serialize payload for signing
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        
        // Create message to verify: timestamp + payload
        var message = Data()
        message.append(timestamp.data(using: .utf8)!)
        message.append(payloadData)
        
        // Compute expected signature
        let expectedSignature = HMAC<SHA256>.authenticationCode(for: message, using: key)
        let expectedSignatureHex = Data(expectedSignature).map { String(format: "%02x", $0) }.joined()
        
        // Compare signatures (constant-time comparison)
        guard constantTimeCompare(signature, expectedSignatureHex) else {
            throw PushVerificationError.signatureMismatch
        }
        
        return VerifiedPush(
            payload: payload,
            timestamp: pushTime,
            verified: true
        )
    }
    
    /// Verify push notification from UserInfo dictionary
    public func verify(userInfo: [AnyHashable: Any]) async throws -> VerifiedPush {
        // Extract signature and timestamp
        guard let signature = userInfo[signatureHeader] as? String else {
            throw PushVerificationError.missingSignature
        }
        
        guard let timestamp = userInfo[timestampHeader] as? String else {
            throw PushVerificationError.missingTimestamp
        }
        
        // Remove signature and timestamp from payload
        var payload = userInfo.filter { key, _ in
            key as? String != signatureHeader && key as? String != timestampHeader
        }
        
        // Convert to [String: Any]
        let stringPayload = payload.reduce(into: [String: Any]()) { result, pair in
            if let key = pair.key as? String {
                result[key] = pair.value
            }
        }
        
        return try await verify(payload: stringPayload, signature: signature, timestamp: timestamp)
    }
    
    // MARK: - Signing (for testing)
    
    /// Sign a push payload (for testing/development)
    public func sign(payload: [String: Any]) async throws -> SignedPush {
        guard let key = signingKey else {
            throw PushVerificationError.signingKeyNotConfigured
        }
        
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let payloadData = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
        
        var message = Data()
        message.append(timestamp.data(using: .utf8)!)
        message.append(payloadData)
        
        let signature = HMAC<SHA256>.authenticationCode(for: message, using: key)
        let signatureHex = Data(signature).map { String(format: "%02x", $0) }.joined()
        
        var signedPayload = payload
        signedPayload[signatureHeader] = signatureHex
        signedPayload[timestampHeader] = timestamp
        
        return SignedPush(
            payload: signedPayload,
            signature: signatureHex,
            timestamp: timestamp
        )
    }
    
    // MARK: - Private Helpers
    
    /// Constant-time string comparison to prevent timing attacks
    private func constantTimeCompare(_ a: String, _ b: String) -> Bool {
        guard a.count == b.count else { return false }
        
        let aBytes = Array(a.utf8)
        let bBytes = Array(b.utf8)
        
        var result: UInt8 = 0
        for i in 0..<aBytes.count {
            result |= aBytes[i] ^ bBytes[i]
        }
        
        return result == 0
    }
}
