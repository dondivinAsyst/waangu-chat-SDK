import Foundation
import CryptoKit
import Combine
import Security
import WaanguCoreKit

/// Holds messages that couldn't be E2EE-encrypted because no session
/// exists yet (e.g. first message to a new contact while offline).
/// Plaintext is encrypted locally with a per-conversation AES key
/// so it never sits unprotected on disk. When connectivity returns,
/// the queue is flushed: fetch key bundle → create session → re-encrypt
/// with the Signal-style E2EE session → send.
public final class PendingE2EEQueue: PendingE2EEQueueProtocol {

    public struct QueuedMessage: Codable {
        public let codeMessage: String        // links to the CoreData record
        public let conversationId: String
        public let recipientUserId: String
        public let localEncryptedText: Data   // AES-GCM sealed with local key
        public let messageType: String
        public let groupId: String
        public let createdAt: Date
    }
    
    public init() {}

    private let storageKey = "com.waangu.chat.e2ee.pendingQueue"
    private let localKeyTag = "com.waangu.chat.e2ee.pendingQueue.localKey"

    // MARK: - Local Encryption (protects plaintext on disk)

    private func getOrCreateLocalKey() throws -> SymmetricKey {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: localKeyTag,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecSuccess, let data = item as? Data {
            return SymmetricKey(data: data)
        }

        let key = SymmetricKey(size: .bits256)
        let keyData = key.withUnsafeBytes { Data($0) }
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: localKeyTag,
            kSecValueData as String: keyData,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        SecItemDelete(addQuery as CFDictionary)
        SecItemAdd(addQuery as CFDictionary, nil)
        return key
    }

    private func localEncrypt(_ text: String) throws -> Data {
        let key = try getOrCreateLocalKey()
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key)
        return sealed.combined!
    }

    private func localDecrypt(_ data: Data) throws -> String {
        let key = try getOrCreateLocalKey()
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        return String(decoding: decrypted, as: UTF8.self)
    }

    // MARK: - Queue Operations

    public func enqueue(
        codeMessage: String,
        plaintext: String,
        conversationId: String,
        recipientUserId: String,
        messageType: String = "TEXT",
        groupId: String = ""
    ) throws {
        let encrypted = try localEncrypt(plaintext)
        let item = QueuedMessage(
            codeMessage: codeMessage,
            conversationId: conversationId,
            recipientUserId: recipientUserId,
            localEncryptedText: encrypted,
            messageType: messageType,
            groupId: groupId,
            createdAt: Date()
        )

        var queue = loadQueue()
        queue.append(item)
        saveQueue(queue)
    }

    public func dequeueAll(for conversationId: String) -> [(plaintext: String, item: PendingE2EEQueueItem)] {
        let queue = loadQueue()
        let matching = queue.filter { $0.conversationId == conversationId }
        var results: [(plaintext: String, item: PendingE2EEQueueItem)] = []

        for item in matching {
            if let plaintext = try? localDecrypt(item.localEncryptedText) {
                let protocolItem = PendingE2EEQueueItem(
                    codeMessage: item.codeMessage,
                    conversationId: item.conversationId,
                    recipientUserId: item.recipientUserId,
                    localEncryptedText: item.localEncryptedText,
                    messageType: item.messageType,
                    groupId: item.groupId,
                    createdAt: item.createdAt
                )
                results.append((plaintext, protocolItem))
            }
        }

        let remaining = queue.filter { $0.conversationId != conversationId }
        saveQueue(remaining)

        return results
    }

    public func dequeueAll() -> [(plaintext: String, item: PendingE2EEQueueItem)] {
        let queue = loadQueue()
        var results: [(plaintext: String, item: PendingE2EEQueueItem)] = []

        for item in queue {
            if let plaintext = try? localDecrypt(item.localEncryptedText) {
                let protocolItem = PendingE2EEQueueItem(
                    codeMessage: item.codeMessage,
                    conversationId: item.conversationId,
                    recipientUserId: item.recipientUserId,
                    localEncryptedText: item.localEncryptedText,
                    messageType: item.messageType,
                    groupId: item.groupId,
                    createdAt: item.createdAt
                )
                results.append((plaintext, protocolItem))
            }
        }

        saveQueue([])
        return results
    }

    public func hasItems(for conversationId: String) -> Bool {
        return loadQueue().contains { $0.conversationId == conversationId }
    }

    public var isEmpty: Bool {
        return loadQueue().isEmpty
    }

    // MARK: - Persistence (UserDefaults)

    private func loadQueue() -> [QueuedMessage] {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([QueuedMessage].self, from: data)) ?? []
    }

    private func saveQueue(_ queue: [QueuedMessage]) {
        if let data = try? JSONEncoder().encode(queue) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }
}
