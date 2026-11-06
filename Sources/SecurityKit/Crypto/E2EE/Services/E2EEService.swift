import Foundation
import CryptoKit
import WaanguStorageKit
import WaanguCoreKit

public final class E2EEService: E2EEServiceProtocol {

    private let keyStore: E2EEKeyStore

    public init(keyStore: E2EEKeyStore = E2EEKeyStore.shared) {
        self.keyStore = keyStore
    }

    // MARK: - Key Registration (call once at signup / app launch)

    /// Generates identity key, signed pre-key, and one-time pre-keys,
    /// then returns a PublicKeyBundle to upload to the server.
    public func generateKeyBundle(userId: String) async throws -> PublicKeyBundle {
        let identityKey = try await keyStore.getOrCreateIdentityKeyPair()
        let signedPreKey = try await keyStore.getOrCreateSignedPreKey()
        let signature = try await keyStore.getSignedPreKeySignature()
        let oneTimePreKeys = try await keyStore.generateOneTimePreKeys(count: 100)

        return PublicKeyBundle(
            userId: userId,
            identityKey: identityKey.publicKey.rawRepresentation,
            signedPreKey: signedPreKey.publicKey.rawRepresentation,
            signedPreKeySignature: signature,
            oneTimePreKeys: oneTimePreKeys.map { $0.publicKey.rawRepresentation }
        )
    }

    // MARK: - Session Setup (X3DH)

    /// Initiates a new E2EE session with a recipient.
    /// Call this before sending the first message in a new conversation.
    /// Returns the ephemeral public key that must be sent with the first message.
    /// Stores a pending session setup payload so the next `encrypt` call attaches it.
    public func initiateSession(
        conversationId: String,
        theirBundle: PublicKeyBundle
    ) async throws -> Data {
        let myIdentityKey = try await keyStore.getOrCreateIdentityKeyPair()
        let (session, ephemeralPubKey) = try X3DHService.initiateSession(
            myIdentityKey: myIdentityKey,
            theirBundle: theirBundle
        )
        try await keyStore.saveSession(session, for: conversationId)

        let setup = SessionSetupPayload(
            senderIdentityKey: myIdentityKey.publicKey.rawRepresentation,
            senderEphemeralKey: ephemeralPubKey,
            usedOneTimePreKeyId: theirBundle.oneTimePreKeys.isEmpty ? nil : 0
        )
        pendingSessionSetups[conversationId] = setup

        return ephemeralPubKey
    }

    private var pendingSessionSetups: [String: SessionSetupPayload] = [:]

    /// Accepts an incoming session from a sender (first message received).
    public func acceptSession(
        conversationId: String,
        theirIdentityKey: Data,
        theirEphemeralKey: Data,
        oneTimePreKeyId: Int?
    ) async throws {
        let myIdentityKey = try await keyStore.getOrCreateIdentityKeyPair()
        let mySignedPreKey = try await keyStore.getOrCreateSignedPreKey()

        var myOneTimePreKey: Curve25519.KeyAgreement.PrivateKey?
        if let otpkId = oneTimePreKeyId {
            myOneTimePreKey = try await keyStore.consumeOneTimePreKey(id: otpkId)
        }

        let session = try X3DHService.acceptSession(
            myIdentityKey: myIdentityKey,
            mySignedPreKey: mySignedPreKey,
            myOneTimePreKey: myOneTimePreKey,
            theirIdentityKey: theirIdentityKey,
            theirEphemeralKey: theirEphemeralKey
        )
        try await keyStore.saveSession(session, for: conversationId)
    }

    // MARK: - Encrypt

    /// Encrypts a plaintext message for a conversation.
    /// Returns base64-encoded EncryptedEnvelope ready for transport.
    /// If this is the first message after session initiation, the envelope
    /// includes a `sessionSetup` payload so the recipient can run X3DH.
    public func encrypt(
        _ text: String,
        conversationId: String
    ) async throws -> String {
        guard var session = try await keyStore.loadSession(for: conversationId) else {
            throw E2EEError.noSessionFound
        }

        var envelope = try DoubleRatchet.encrypt(plaintext: text, state: &session)
        try await keyStore.saveSession(session, for: conversationId)

        if let setup = pendingSessionSetups.removeValue(forKey: conversationId) {
            envelope.sessionSetup = setup
        }

        let data = try JSONEncoder().encode(envelope)
        return data.base64EncodedString()
    }

    /// Encrypts raw data (for media, documents, etc.).
    public func encryptData(
        _ plainData: Data,
        conversationId: String
    ) async throws -> String {
        guard var session = try await keyStore.loadSession(for: conversationId) else {
            throw E2EEError.noSessionFound
        }

        let plaintext = plainData.base64EncodedString()
        let envelope = try DoubleRatchet.encrypt(plaintext: plaintext, state: &session)
        try await keyStore.saveSession(session, for: conversationId)

        let data = try JSONEncoder().encode(envelope)
        return data.base64EncodedString()
    }

    // MARK: - Decrypt

    /// Decrypts a base64-encoded EncryptedEnvelope back to plaintext.
    public func decrypt(
        _ encryptedBase64: String,
        conversationId: String
    ) async throws -> String {
        guard let envelopeData = Data(base64Encoded: encryptedBase64) else {
            throw E2EEError.decryptionFailed
        }

        let envelope = try JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData)

        guard var session = try await keyStore.loadSession(for: conversationId) else {
            throw E2EEError.noSessionFound
        }

        let plaintext = try DoubleRatchet.decrypt(envelope: envelope, state: &session)
        try await keyStore.saveSession(session, for: conversationId)

        return plaintext
    }

    /// Decrypts a base64-encoded envelope back to raw Data (for media).
    public func decryptData(
        _ encryptedBase64: String,
        conversationId: String
    ) async throws -> Data {
        let plaintext = try await decrypt(encryptedBase64, conversationId: conversationId)
        guard let data = Data(base64Encoded: plaintext) else {
            throw E2EEError.decryptionFailed
        }
        return data
    }

    // MARK: - Session Management

    public func hasSession(for conversationId: String) async throws -> Bool {
        return try await keyStore.loadSession(for: conversationId) != nil
    }

    public func deleteSession(for conversationId: String) async throws {
        try await keyStore.deleteSession(for: conversationId)
    }
}
