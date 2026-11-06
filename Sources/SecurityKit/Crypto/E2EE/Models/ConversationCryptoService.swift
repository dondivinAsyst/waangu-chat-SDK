import Security
import SwiftUI
import Combine
import CryptoKit
import WaanguCoreKit
import WaanguStorageKit

public final class ConversationCryptoService {

    private let keychain: any KeychainStoreProtocol
    private let keyPrefix = "conversation.key"

    public init(keychain: any KeychainStoreProtocol) {
        self.keychain = keychain
    }

    private func getOrCreateKey(for conversationId: String) async throws -> SymmetricKey {
        let keyString = "\(keyPrefix).\(conversationId)"
        
        if let existingData = try await keychain.getData(forKey: keyString) {
            return SymmetricKey(data: existingData)
        }
        
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try await keychain.saveData(keyData, forKey: keyString)
        return newKey
    }

    public func encrypt(
        _ text: String,
        conversationId: String
    ) async throws -> Data {

        let key = try await getOrCreateKey(for: conversationId)
        let data = Data(text.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined!
    }

    public func decrypt(
        _ data: Data,
        conversationId: String
    ) async throws -> String {

        let key = try await getOrCreateKey(for: conversationId)
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)

        return String(decoding: decrypted, as: UTF8.self)
    }
}
