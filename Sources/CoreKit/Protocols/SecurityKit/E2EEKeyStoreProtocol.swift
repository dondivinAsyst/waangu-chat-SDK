import Foundation
import CryptoKit

public protocol E2EEKeyStoreProtocol {
    func getOrCreateIdentityKeyPair() async throws -> Curve25519.KeyAgreement.PrivateKey
    func getIdentityPublicKey() async throws -> Data

    func getOrCreateSignedPreKey() async throws -> Curve25519.KeyAgreement.PrivateKey
    func getSignedPreKeySignature() async throws -> Data

    func generateOneTimePreKeys(count: Int) async throws -> [Curve25519.KeyAgreement.PrivateKey]
    func consumeOneTimePreKey(id: Int) async throws -> Curve25519.KeyAgreement.PrivateKey?

    func saveSession(_ session: SessionState, for conversationId: String) async throws
    func loadSession(for conversationId: String) async throws -> SessionState?
    func deleteSession(for conversationId: String) async throws
}
