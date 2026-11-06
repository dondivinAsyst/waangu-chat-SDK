import Foundation
import CryptoKit

public final class DoubleRatchet {

    private static let maxSkip = 256

    // MARK: - Symmetric Ratchet

    private static func advanceChainKey(_ chainKey: Data) -> (newChainKey: Data, messageKeyMaterial: Data) {
        let ck = SymmetricKey(data: chainKey)
        let newChainKey = HMAC<SHA256>.authenticationCode(for: Data([0x02]), using: ck)
        let messageKeyMaterial = HMAC<SHA256>.authenticationCode(for: Data([0x01]), using: ck)
        return (Data(newChainKey), Data(messageKeyMaterial))
    }

    private static func deriveMessageKeys(from material: Data) -> (encKey: SymmetricKey, nonce: AES.GCM.Nonce) {
        let derived = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: material),
            info: Data("WaanguMsgKey".utf8),
            outputByteCount: 44  // 32 enc + 12 nonce
        )
        let bytes = derived.withUnsafeBytes { Data($0) }
        let encKey = SymmetricKey(data: bytes[0..<32])
        let nonce = try! AES.GCM.Nonce(data: bytes[32..<44])
        return (encKey, nonce)
    }

    // MARK: - DH Ratchet Step

    public static func dhRatchetStep(
        state: inout SessionState,
        theirNewRatchetKey: Data
    ) throws {
        state.previousSendingChainLength = state.sendMessageNumber
        state.sendMessageNumber = 0
        state.receiveMessageNumber = 0
        state.receivingRatchetPublicKey = theirNewRatchetKey

        let theirPub = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: theirNewRatchetKey)
        let myPriv = try Curve25519.KeyAgreement.PrivateKey(rawRepresentation: state.sendingRatchetPrivateKey)

        // Derive receiving chain from current sending key + their new key
        let dh1 = try myPriv.sharedSecretFromKeyAgreement(with: theirPub)
        let dh1Data = dh1.withUnsafeBytes { Data($0) }

        let recv = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dh1Data),
            salt: state.rootKey,
            info: Data("WaanguRatchet".utf8),
            outputByteCount: 64
        )
        let recvBytes = recv.withUnsafeBytes { Data($0) }
        state.rootKey = Data(recvBytes[0..<32])
        state.receivingChainKey = Data(recvBytes[32..<64])

        // Generate new sending ratchet key pair
        let newSendingKey = Curve25519.KeyAgreement.PrivateKey()
        state.sendingRatchetPrivateKey = newSendingKey.rawRepresentation
        state.sendingRatchetPublicKey = newSendingKey.publicKey.rawRepresentation

        let dh2 = try newSendingKey.sharedSecretFromKeyAgreement(with: theirPub)
        let dh2Data = dh2.withUnsafeBytes { Data($0) }

        let send = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: dh2Data),
            salt: state.rootKey,
            info: Data("WaanguRatchet".utf8),
            outputByteCount: 64
        )
        let sendBytes = send.withUnsafeBytes { Data($0) }
        state.rootKey = Data(sendBytes[0..<32])
        state.sendingChainKey = Data(sendBytes[32..<64])
    }

    // MARK: - Encrypt

    public static func encrypt(
        plaintext: String,
        state: inout SessionState
    ) throws -> EncryptedEnvelope {
        let (newChainKey, messageKeyMaterial) = advanceChainKey(state.sendingChainKey)
        state.sendingChainKey = newChainKey

        let (encKey, nonce) = deriveMessageKeys(from: messageKeyMaterial)

        let header = MessageHeader(
            ratchetPublicKey: state.sendingRatchetPublicKey,
            messageNumber: state.sendMessageNumber,
            previousChainLength: state.previousSendingChainLength
        )
        state.sendMessageNumber += 1

        let headerData = try JSONEncoder().encode(header)
        let sealed = try AES.GCM.seal(
            Data(plaintext.utf8),
            using: encKey,
            nonce: nonce,
            authenticating: headerData
        )

        guard let combined = sealed.combined else {
            throw E2EEError.decryptionFailed
        }

        return EncryptedEnvelope(header: header, ciphertext: combined)
    }

    // MARK: - Decrypt

    public static func decrypt(
        envelope: EncryptedEnvelope,
        state: inout SessionState
    ) throws -> String {

        // Try skipped message keys first (out-of-order delivery)
        if let plaintext = try trySkippedMessageKeys(envelope: envelope, state: &state) {
            return plaintext
        }

        // DH ratchet step if the sender's ratchet key has changed
        if envelope.header.ratchetPublicKey != state.receivingRatchetPublicKey {
            try skipMessageKeys(
                state: &state,
                until: envelope.header.previousChainLength
            )
            try dhRatchetStep(state: &state, theirNewRatchetKey: envelope.header.ratchetPublicKey)
        }

        // Skip ahead for any messages that arrived out of order
        try skipMessageKeys(state: &state, until: envelope.header.messageNumber)

        // Advance receiving chain and decrypt
        guard var recvChain = state.receivingChainKey else {
            throw E2EEError.noReceivingChain
        }

        let (newChainKey, messageKeyMaterial) = advanceChainKey(recvChain)
        state.receivingChainKey = newChainKey
        state.receiveMessageNumber += 1

        let (encKey, nonce) = deriveMessageKeys(from: messageKeyMaterial)
        let headerData = try JSONEncoder().encode(envelope.header)
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        let decrypted = try AES.GCM.open(box, using: encKey, authenticating: headerData)

        return String(decoding: decrypted, as: UTF8.self)
    }

    // MARK: - Out-of-Order Message Handling

    private static func trySkippedMessageKeys(
        envelope: EncryptedEnvelope,
        state: inout SessionState
    ) throws -> String? {
        let skippedKey = "\(envelope.header.ratchetPublicKey.base64EncodedString()):\(envelope.header.messageNumber)"
        guard let savedKeyData = state.skippedMessageKeys[skippedKey] else {
            return nil
        }

        state.skippedMessageKeys.removeValue(forKey: skippedKey)

        let (encKey, nonce) = deriveMessageKeys(from: savedKeyData)
        let headerData = try JSONEncoder().encode(envelope.header)
        let box = try AES.GCM.SealedBox(combined: envelope.ciphertext)
        let decrypted = try AES.GCM.open(box, using: encKey, authenticating: headerData)

        return String(decoding: decrypted, as: UTF8.self)
    }

    private static func skipMessageKeys(
        state: inout SessionState,
        until targetNumber: Int
    ) throws {
        guard targetNumber > state.receiveMessageNumber else { return }
        guard targetNumber - state.receiveMessageNumber <= maxSkip else {
            throw E2EEError.decryptionFailed
        }
        guard var recvChain = state.receivingChainKey else { return }

        let ratchetPubBase64 = (state.receivingRatchetPublicKey ?? Data()).base64EncodedString()

        while state.receiveMessageNumber < targetNumber {
            let (newChainKey, messageKeyMaterial) = advanceChainKey(recvChain)
            let key = "\(ratchetPubBase64):\(state.receiveMessageNumber)"
            state.skippedMessageKeys[key] = messageKeyMaterial
            recvChain = newChainKey
            state.receiveMessageNumber += 1
        }
        state.receivingChainKey = recvChain
    }
}
