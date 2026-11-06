import Foundation

public protocol E2EEServiceProtocol: Sendable {
    func generateKeyBundle(userId: String) async throws -> PublicKeyBundle
    func initiateSession(conversationId: String, theirBundle: PublicKeyBundle) async throws -> Data
    func acceptSession(conversationId: String, theirIdentityKey: Data, theirEphemeralKey: Data, oneTimePreKeyId: Int?) async throws
    func encrypt(_ text: String, conversationId: String) async throws -> String
    func encryptData(_ plainData: Data, conversationId: String) async throws -> String
    func decrypt(_ encryptedBase64: String, conversationId: String) async throws -> String
    func decryptData(_ encryptedBase64: String, conversationId: String) async throws -> Data
    func hasSession(for conversationId: String) async throws -> Bool
    func deleteSession(for conversationId: String) async throws
}

// E2EE Types shared between protocol and implementation
// These need to be in CoreKit so both protocol and implementation can use them

public struct PublicKeyBundle: Codable, Sendable {
    public let userId: String
    public let identityKey: Data
    public let signedPreKey: Data
    public let signedPreKeySignature: Data
    public let oneTimePreKeys: [Data]
    
    public init(userId: String, identityKey: Data, signedPreKey: Data, signedPreKeySignature: Data, oneTimePreKeys: [Data]) {
        self.userId = userId
        self.identityKey = identityKey
        self.signedPreKey = signedPreKey
        self.signedPreKeySignature = signedPreKeySignature
        self.oneTimePreKeys = oneTimePreKeys
    }
}

public struct MessageHeader: Codable, Sendable {
    public let ratchetPublicKey: Data
    public let messageNumber: Int
    public let previousChainLength: Int
    
    public init(ratchetPublicKey: Data, messageNumber: Int, previousChainLength: Int) {
        self.ratchetPublicKey = ratchetPublicKey
        self.messageNumber = messageNumber
        self.previousChainLength = previousChainLength
    }
}

public struct EncryptedEnvelope: Codable, Sendable {
    public let header: MessageHeader
    public let ciphertext: Data
    public var sessionSetup: SessionSetupPayload?
    
    public init(header: MessageHeader, ciphertext: Data, sessionSetup: SessionSetupPayload? = nil) {
        self.header = header
        self.ciphertext = ciphertext
        self.sessionSetup = sessionSetup
    }
}

public struct SessionSetupPayload: Codable, Sendable {
    public let senderIdentityKey: Data
    public let senderEphemeralKey: Data
    public let usedOneTimePreKeyId: Int?
    
    public init(senderIdentityKey: Data, senderEphemeralKey: Data, usedOneTimePreKeyId: Int?) {
        self.senderIdentityKey = senderIdentityKey
        self.senderEphemeralKey = senderEphemeralKey
        self.usedOneTimePreKeyId = usedOneTimePreKeyId
    }
}

public struct SessionState: Codable, Sendable {
    public var rootKey: Data
    public var sendingChainKey: Data
    public var receivingChainKey: Data?
    public var sendingRatchetPrivateKey: Data
    public var sendingRatchetPublicKey: Data
    public var receivingRatchetPublicKey: Data?
    public var sendMessageNumber: Int = 0
    public var receiveMessageNumber: Int = 0
    public var previousSendingChainLength: Int = 0
    public var skippedMessageKeys: [String: Data] = [:]
    
    public init(
        rootKey: Data,
        sendingChainKey: Data,
        receivingChainKey: Data?,
        sendingRatchetPrivateKey: Data,
        sendingRatchetPublicKey: Data,
        receivingRatchetPublicKey: Data?,
        sendMessageNumber: Int = 0,
        receiveMessageNumber: Int = 0,
        previousSendingChainLength: Int = 0,
        skippedMessageKeys: [String: Data] = [:]
    ) {
        self.rootKey = rootKey
        self.sendingChainKey = sendingChainKey
        self.receivingChainKey = receivingChainKey
        self.sendingRatchetPrivateKey = sendingRatchetPrivateKey
        self.sendingRatchetPublicKey = sendingRatchetPublicKey
        self.receivingRatchetPublicKey = receivingRatchetPublicKey
        self.sendMessageNumber = sendMessageNumber
        self.receiveMessageNumber = receiveMessageNumber
        self.previousSendingChainLength = previousSendingChainLength
        self.skippedMessageKeys = skippedMessageKeys
    }
}

public enum E2EEError: Error, LocalizedError, Sendable {
    case noReceivingChain
    case noSessionFound
    case invalidPublicKey
    case sessionInitFailed
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .noReceivingChain:  return "No receiving chain established"
        case .noSessionFound:    return "No session found for this conversation"
        case .invalidPublicKey:  return "Invalid public key data"
        case .sessionInitFailed: return "Session initialization failed"
        case .decryptionFailed:  return "Message decryption failed"
        }
    }
}