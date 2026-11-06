import Foundation
import CryptoKit
import WaanguStorageKit
import WaanguCoreKit

public final class CryptoService: CryptoServiceProtocol {

    private let keychain: any KeychainStoreProtocol
    private var key: SymmetricKey?
    private let keyIdentifier = "message.encryption.key"

    public init(keychain: any KeychainStoreProtocol) {
        self.keychain = keychain
    }

    private func loadKey() async throws -> SymmetricKey {
        if let key { return key }
        
        if let existingData = try await keychain.getData(forKey: keyIdentifier) {
            let loadedKey = SymmetricKey(data: existingData)
            self.key = loadedKey
            return loadedKey
        }
        
        let newKey = SymmetricKey(size: .bits256)
        let keyData = newKey.withUnsafeBytes { Data($0) }
        try await keychain.saveData(keyData, forKey: keyIdentifier)
        self.key = newKey
        return newKey
    }

    public func encrypt(_ text: String) async throws -> Data {
        let key = try await loadKey()
        let data = Data(text.utf8)
        let sealed = try AES.GCM.seal(data, using: key)
        return sealed.combined!
    }

    public func decrypt(_ data: Data) async throws -> String {
        let key = try await loadKey()
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        return String(decoding: decrypted, as: UTF8.self)
    }
}
