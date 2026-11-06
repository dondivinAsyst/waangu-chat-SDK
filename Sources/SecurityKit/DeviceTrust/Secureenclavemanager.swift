// MARK: - SecureEnclaveManager.swift
// Module: SecurityKit
// Implements DeviceBindingProviding from CoreKit.
// Manages a P-256 key pair inside the Secure Enclave,
// scoped per account via a unique tag.

import Foundation
import WaanguCoreKit
import LocalAuthentication

// MARK: - Errors

enum SecureEnclaveError: Error, Sendable {
    case enclaveNotAvailable
    case keyGenerationFailed(status: OSStatus)
    case keyNotFound
    case signingFailed(status: OSStatus)
    case publicKeyExportFailed
    case deletionFailed(status: OSStatus)
    case accessControlCreationFailed
}
// MARK: - SecureEnclaveManager

/// Thread-safe manager for a Secure Enclave key pair bound to a single account.
///
/// Usage:
/// ```swift
/// let manager = SecureEnclaveManager(
///     accountId: "user_roland",
///     analytics: analytics,
///     crashReporter: crashReporter
/// )
/// let publicKey = try await manager.bind()
/// let signature = try await manager.sign(challenge: serverChallenge)
/// ```
public actor SecureEnclaveManager: DeviceBindingProviding {

    // MARK: - Properties

    private let keyTag: Data
    private let accountId: String
    private let analytics: any AnalyticsProtocol
    private let crashReporter: any CrashReporterProtocol

    // MARK: - Init

    /// - Parameters:
    ///   - accountId: Unique account identifier. Each account gets its own
    ///     Secure Enclave key pair, allowing multi-account support on one device.
    ///   - analytics: Analytics tracker for device binding events.
    ///   - crashReporter: Crash reporter for breadcrumbs and error capture.
    public init(
        accountId: String,
        analytics: any AnalyticsProtocol,
        crashReporter: any CrashReporterProtocol
    ) {
        self.accountId = accountId
        self.analytics = analytics
        self.crashReporter = crashReporter

        let tag = "com.waangu.devicebinding.\(accountId)"
        self.keyTag = Data(tag.utf8)
    }

    // MARK: - DeviceBindingProviding

    public var isBound: Bool {
        get async {
            loadPrivateKey() != nil
        }
    }

    public func bind() async throws -> Data {
        // If a key already exists for this account, return its public key
        if let existingPrivateKey = loadPrivateKey() {
            return try exportPublicKey(from: existingPrivateKey)
        }

        // Verify Secure Enclave availability
        guard SecureEnclave.isAvailable else {
            let error = SecureEnclaveError.enclaveNotAvailable
            reportFailure(error, reason: "secure_enclave_not_available")
            throw error
        }

        // Create access control: private key usable only after biometric auth
        let accessControl: SecAccessControl
        do {
            accessControl = try createAccessControl()
        } catch {
            reportFailure(error, reason: "access_control_creation_failed")
            throw error
        }

        // Key generation attributes
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag,
                kSecAttrAccessControl as String: accessControl
            ]
        ]

        // Generate key pair
        var cfError: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &cfError) else {
            let status = (cfError?.takeRetainedValue() as? NSError)?.code ?? -1
            let error = SecureEnclaveError.keyGenerationFailed(status: OSStatus(status))
            reportFailure(error, reason: "key_generation_failed_\(status)")
            throw error
        }

        // Export the public key
        let publicKeyData: Data
        do {
            publicKeyData = try exportPublicKey(from: privateKey)
        } catch {
            reportFailure(error, reason: "public_key_export_failed")
            throw error
        }

        // Success
        analytics.log(DeviceTrustAnalyticsEvent.deviceBound(accountId: accountId))
        DeviceTrustBreadcrumbs.bindingPerformed(crashReporter, accountId: accountId)

        return publicKeyData
    }

    public func sign(challenge: Data) async throws -> Data {
        guard let privateKey = loadPrivateKey() else {
            let error = SecureEnclaveError.keyNotFound
            reportFailure(error, reason: "key_not_found_for_signing")
            throw error
        }

        // Sign with ECDSA using SHA-256
        var cfError: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            .ecdsaSignatureMessageX962SHA256,
            challenge as CFData,
            &cfError
        ) else {
            let status = (cfError?.takeRetainedValue() as? NSError)?.code ?? -1
            let error = SecureEnclaveError.signingFailed(status: OSStatus(status))
            reportFailure(error, reason: "signing_failed_\(status)")
            throw error
        }

        analytics.log(DeviceTrustAnalyticsEvent.challengeSigned(accountId: accountId))

        return signature as Data
    }

    public func unbind() async throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            let error = SecureEnclaveError.deletionFailed(status: status)
            reportFailure(error, reason: "deletion_failed_\(status)")
            throw error
        }

        analytics.log(DeviceTrustAnalyticsEvent.deviceUnbound(accountId: accountId))

        crashReporter.addBreadcrumb(
            category: "device_trust",
            message: "Device unbound for \(accountId)",
            level: .info,
            data: nil
        )
    }

    // MARK: - Private Helpers

    private func loadPrivateKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess, let key = item else {
            return nil
        }

        return (key as! SecKey)
    }

    private func exportPublicKey(from privateKey: SecKey) throws -> Data {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw SecureEnclaveError.publicKeyExportFailed
        }

        var error: Unmanaged<CFError>?
        guard let data = SecKeyCopyExternalRepresentation(publicKey, &error) else {
            throw SecureEnclaveError.publicKeyExportFailed
        }

        return data as Data
    }

    private func createAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        guard let accessControl = SecAccessControlCreateWithFlags(
            kCFAllocatorDefault,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            [.privateKeyUsage, .biometryCurrentSet],
            &error
        ) else {
            throw SecureEnclaveError.accessControlCreationFailed
        }

        return accessControl
    }

    /// Centralized failure reporting: analytics event + crash reporter capture.
    private func reportFailure(_ error: Error, reason: String) {
        analytics.log(DeviceTrustAnalyticsEvent.bindingFailed(
            accountId: accountId,
            reason: reason
        ))
        crashReporter.capture(error, context: [
            "component": "SecureEnclaveManager",
            "account_id": accountId,
            "reason": reason
        ])
    }
}

// MARK: - Secure Enclave Availability Check

private enum SecureEnclave {
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        if let error, error.code == LAError.biometryNotAvailable.rawValue {
            return false
        }

        return true
        #endif
    }
}
