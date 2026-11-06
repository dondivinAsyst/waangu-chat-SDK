//
//  ChaosPushTests.swift
//  WaanguTests
//
//  Chaos engineering tests for push notification security

import XCTest
@testable import WaanguCoreKit
@testable import WaanguSecurityKit
import CryptoKit

final class ChaosPushTests: XCTestCase {
    
    var pushVerifier: SignedPushVerifier!
    let testKey = "dGVzdF9rZXlfZm9yX3B1c2hfdmVyaWZpY2F0aW9uXzEyMzQ1Njc4OTA=" // base64 test key
    
    override func setUp() async throws {
        pushVerifier = SignedPushVerifier.shared
        try await pushVerifier.setSigningKey(base64: testKey)
    }
    
    // MARK: - Fake Push Tests
    
    func testFakePush_NoSignature() async throws {
        let userInfo: [AnyHashable: Any] = ["aps": ["alert": "Test message"], "messageId": "123", "senderId": "user456"]
        await assertRejected(userInfo) { if case .missingSignature = $0 { return true }; return false }
    }
    
    func testFakePush_InvalidSignature() async throws {
        // Fresh timestamp, signature header present but forged.
        var userInfo = try signedUserInfo(samplePayload, timestamp: now(), keyBase64: testKey)
        userInfo["X-Push-Signature"] = String(repeating: "0", count: 64)
        await assertRejected(userInfo) { if case .signatureMismatch = $0 { return true }; return false }
    }
    
    func testFakePush_TamperedPayload() async throws {
        let signed = try await pushVerifier.sign(payload: samplePayload)
        var tampered = signed.payload
        tampered["text"] = "Tampered message"
        await assertRejected(tampered) { if case .signatureMismatch = $0 { return true }; return false }
    }
    
    func testFakePush_ExpiredTimestamp() async throws {
        // Correctly signed, 10 minutes old: the verifier accepts at most 5.
        let userInfo = try signedUserInfo(samplePayload, timestamp: now() - 600, keyBase64: testKey)
        await assertRejected(userInfo) { if case .timestampExpired = $0 { return true }; return false }
    }
    
    func testFakePush_FutureTimestamp() async throws {
        // Correctly signed, 10 minutes in the future.
        let userInfo = try signedUserInfo(samplePayload, timestamp: now() + 600, keyBase64: testKey)
        await assertRejected(userInfo) { if case .timestampExpired = $0 { return true }; return false }
    }
    
    
    func testFakePush_SignatureStripping() async throws {
        // Signed by the verifier itself, then the signature header removed.
        let signed = try await pushVerifier.sign(payload: samplePayload)
        var stripped = signed.payload
        stripped.removeValue(forKey: "X-Push-Signature")
        await assertRejected(stripped) { if case .missingSignature = $0 { return true }; return false }
    }
    
    func testFakePush_WrongKey() async throws {
        // Fresh and well-formed, but signed with another valid key.
        let otherKey = Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
        let userInfo = try signedUserInfo(samplePayload, timestamp: now(), keyBase64: otherKey)
        await assertRejected(userInfo) { if case .signatureMismatch = $0 { return true }; return false }
    }
    
    // MARK: - Timing Attack Tests
    
    func testFakePush_TimingAttack() async throws {
        let validPayload: [String: Any] = [
            "messageId": "123",
            "senderId": "user456",
            "text": "Test message"
        ]
        
        let signed = try await pushVerifier.sign(payload: validPayload)
        
        // Measure verification time for valid signature
        let validStart = Date()
        _ = try? await pushVerifier.verify(userInfo: signed.payload)
        let validDuration = Date().timeIntervalSince(validStart)
        
        // Measure verification time for invalid signature
        var invalidPayload = signed.payload
        invalidPayload["X-Push-Signature"] = String(repeating: "0", count: 64)
        
        let invalidStart = Date()
        _ = try? await pushVerifier.verify(userInfo: invalidPayload)
        let invalidDuration = Date().timeIntervalSince(invalidStart)
        
        // Wall-clock comparison: a smoke check, not a proof of constant time.
        let timingDifference = abs(validDuration - invalidDuration)
        XCTAssertLessThan(timingDifference, 0.01, "Verification should be constant-time")
    }
    
    // MARK: - Payload Injection Tests
    
    func testFakePush_SQLInjection() async throws {
        let maliciousPayload: [String: Any] = [
            "messageId": "123'; DROP TABLE messages; --",
            "senderId": "user456",
            "text": "Test message"
        ]
        
        let signed = try await pushVerifier.sign(payload: maliciousPayload)
        
        // Should verify signature but payload should be sanitized before use
        let verified = try await pushVerifier.verify(userInfo: signed.payload)
        XCTAssertNotNil(verified)
        
        // Application should sanitize the messageId before database use
    }
    
    func testFakePush_XSSInjection() async throws {
        let maliciousPayload: [String: Any] = [
            "messageId": "123",
            "senderId": "user456",
            "text": "<script>alert('XSS')</script>"
        ]
        
        let signed = try await pushVerifier.sign(payload: maliciousPayload)
        
        // Should verify signature but payload should be sanitized before display
        let verified = try await pushVerifier.verify(userInfo: signed.payload)
        XCTAssertNotNil(verified)
        
        // Application should sanitize text before display
    }
    
    // MARK: - Performance Tests
    
    func testFakePush_PerformanceUnderLoad() async throws {
        let startTime = Date()
        let count = 100
        
        for i in 0..<count {
            let payload: [String: Any] = [
                "messageId": "\(i)",
                "senderId": "user456",
                "text": "Test message \(i)"
            ]
            
            let signed = try await pushVerifier.sign(payload: payload)
            _ = try await pushVerifier.verify(userInfo: signed.payload)
        }
        
        let duration = Date().timeIntervalSince(startTime)
        
        // Should complete in reasonable time
        XCTAssertLessThan(duration, 5.0, "Push verification should be fast")
    }
    
    func testFakePush_ConcurrentVerification() async throws {
        let payload: [String: Any] = [
            "messageId": "123",
            "senderId": "user456",
            "text": "Test message"
        ]
        
        let signed = try await pushVerifier.sign(payload: payload)
        
        // Verify concurrently
        await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    do {
                        _ = try await self.pushVerifier.verify(userInfo: signed.payload)
                        return true
                    } catch {
                        return false
                    }
                }
            }
            
            var successCount = 0
            for await success in group {
                if success {
                    successCount += 1
                }
            }
            
            // All should succeed
            XCTAssertEqual(successCount, 50, "All concurrent verifications should succeed")
        }
    }


    // MARK: - Signing in the verifier's format
    //
    // The first version of these tests signed with keys ("signature", "timestamp")
    // and an encoding (base64, integer timestamp) the verifier does not read, so
    // every push was rejected as unsigned and the timestamp checks were never
    // reached. These helpers follow SignedPushVerifier.sign exactly.

    private let samplePayload: [String: Any] = ["messageId": "123", "senderId": "user456", "text": "Test message"]

    private func now() -> Int { Int(Date().timeIntervalSince1970) }

    private func signedUserInfo(_ payload: [String: Any], timestamp: Int, keyBase64: String) throws -> [AnyHashable: Any] {
        let stamp = String(timestamp)
        var message = Data(stamp.utf8)
        message.append(try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]))
        let key = SymmetricKey(data: try XCTUnwrap(Data(base64Encoded: keyBase64)))
        let mac = HMAC<SHA256>.authenticationCode(for: message, using: key)
        var userInfo: [AnyHashable: Any] = [:]
        for (field, value) in payload { userInfo[field] = value }
        userInfo["X-Push-Signature"] = Data(mac).map { String(format: "%02x", $0) }.joined()
        userInfo["X-Push-Timestamp"] = stamp
        return userInfo
    }

    private func assertRejected(_ userInfo: [AnyHashable: Any],
                                file: StaticString = #filePath, line: UInt = #line,
                                because expected: (PushVerificationError) -> Bool) async {
        do {
            _ = try await pushVerifier.verify(userInfo: userInfo)
            XCTFail("Push was accepted", file: file, line: line)
        } catch let error as PushVerificationError {
            XCTAssertTrue(expected(error), "Rejected for another reason: \(error)", file: file, line: line)
        } catch {
            XCTFail("Unexpected error type: \(error)", file: file, line: line)
        }
    }

    /// Control: without it, the rejection tests above would also pass if the
    /// helper signed wrongly.
    func testHelperSignedPush_isAcceptedWhenFreshAndCorrectlySigned() async throws {
        let userInfo = try signedUserInfo(samplePayload, timestamp: now(), keyBase64: testKey)
        _ = try await pushVerifier.verify(userInfo: userInfo)
    }
}
