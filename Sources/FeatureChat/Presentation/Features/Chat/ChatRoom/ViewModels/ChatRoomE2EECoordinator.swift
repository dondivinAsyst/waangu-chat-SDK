//
//  ChatRoomE2EECoordinator.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Encrypts/decrypts chat text and manages the pending E2EE offline queue.
struct ChatRoomE2EECoordinator {

    let e2eeUseCases: E2EEUseCasesProtocol
    let pendingQueue: any PendingE2EEQueueProtocol

    // MARK: - Decrypt

    func decryptIncoming(_ message: MessageDataItem, conversationId: String) async -> MessageDataItem {
        guard !message.message.text.isEmpty else { return message }

        guard let envelopeData = Data(base64Encoded: message.message.text),
              let _ = try? JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData) else {
            return message
        }

        do {
            var sessionExists = try await e2eeUseCases.hasSession.execute(conversationId: conversationId)

            if !sessionExists {
                if let envelope = try? JSONDecoder().decode(EncryptedEnvelope.self, from: envelopeData),
                   let setup = envelope.sessionSetup {
                    try await e2eeUseCases.acceptSession.execute(
                        conversationId: conversationId,
                        theirIdentityKey: setup.senderIdentityKey,
                        theirEphemeralKey: setup.senderEphemeralKey,
                        oneTimePreKeyId: setup.usedOneTimePreKeyId
                    )
                    sessionExists = true
                }
            }

            guard sessionExists else { return message }

            let plaintext = try await e2eeUseCases.decrypt.execute(
                encryptedText: message.message.text,
                conversationId: conversationId
            )
            var decrypted = message
            decrypted.message.text = plaintext
            return decrypted
        } catch {
            #if DEBUG
            print("E2EE decrypt failed, using raw text: \(error)")
            #endif
            return message
        }
    }

    func decryptBatch(_ messages: [MessageDataItem], conversationId: String) async -> [MessageDataItem] {
        var decrypted: [MessageDataItem] = []
        for msg in messages {
            decrypted.append(await decryptIncoming(msg, conversationId: conversationId))
        }
        return decrypted
    }

    // MARK: - Encrypt

    enum EncryptOutcome {
        case encrypted(String)
        case queued
    }

    func encryptOutgoingText(
        plaintext: String,
        codeMessage: String,
        conversationId: String,
        recipientId: String
    ) async -> EncryptOutcome {
        guard !recipientId.isEmpty else { return .queued }

        do {
            var sessionExists = try await e2eeUseCases.hasSession.execute(conversationId: conversationId)

            if !sessionExists {
                do {
                    let theirBundle = try await e2eeUseCases.fetchKeyBundle.execute(userId: recipientId)
                    _ = try await e2eeUseCases.initiateSession.execute(
                        conversationId: conversationId,
                        theirBundle: theirBundle
                    )
                    sessionExists = true
                } catch {
                    try? pendingQueue.enqueue(
                        codeMessage: codeMessage,
                        plaintext: plaintext,
                        conversationId: conversationId,
                        recipientUserId: recipientId
                    )
                    return .queued
                }
            }

            let encrypted = try await e2eeUseCases.encrypt.execute(
                text: plaintext,
                conversationId: conversationId
            )
            return .encrypted(encrypted)
        } catch {
            #if DEBUG
            print("E2EE encrypt error: \(error)")
            #endif
            try? pendingQueue.enqueue(
                codeMessage: codeMessage,
                plaintext: plaintext,
                conversationId: conversationId,
                recipientUserId: recipientId
            )
            return .queued
        }
    }

    // MARK: - Pending queue flush

    struct PendingEncryptionUpdate {
        let codeMessage: String
        let encryptedText: String
        let requeuePlaintext: String?
        let requeueItem: PendingE2EEQueueItem?
    }

    func flushPending(conversationId: String) async -> [PendingEncryptionUpdate] {
        guard pendingQueue.hasItems(for: conversationId) else { return [] }

        let queued = pendingQueue.dequeueAll(for: conversationId)
        guard !queued.isEmpty else { return [] }

        var updates: [PendingEncryptionUpdate] = []

        for (plaintext, item) in queued {
            do {
                var sessionExists = try await e2eeUseCases.hasSession.execute(conversationId: item.conversationId)

                if !sessionExists {
                    let theirBundle = try await e2eeUseCases.fetchKeyBundle.execute(userId: item.recipientUserId)
                    _ = try await e2eeUseCases.initiateSession.execute(
                        conversationId: item.conversationId,
                        theirBundle: theirBundle
                    )
                    sessionExists = true
                }

                let encrypted = try await e2eeUseCases.encrypt.execute(
                    text: plaintext,
                    conversationId: item.conversationId
                )
                updates.append(
                    PendingEncryptionUpdate(
                        codeMessage: item.codeMessage,
                        encryptedText: encrypted,
                        requeuePlaintext: nil,
                        requeueItem: nil
                    )
                )
            } catch {
                #if DEBUG
                print("Flush pending E2EE failed, re-queuing: \(error)")
                #endif
                updates.append(
                    PendingEncryptionUpdate(
                        codeMessage: item.codeMessage,
                        encryptedText: "",
                        requeuePlaintext: plaintext,
                        requeueItem: item
                    )
                )
            }
        }

        return updates
    }

    /// Applies flush results — re-queues failures and patches successful encryptions.
    static func applyFlushResults(
        _ updates: [PendingEncryptionUpdate],
        pendingQueue: any PendingE2EEQueueProtocol,
        patchEncrypted: (String, String) async -> Void,
        rebuildTimeline: @MainActor () -> Void
    ) async {
        for update in updates {
            if let plaintext = update.requeuePlaintext, let item = update.requeueItem {
                try? pendingQueue.enqueue(
                    codeMessage: item.codeMessage,
                    plaintext: plaintext,
                    conversationId: item.conversationId,
                    recipientUserId: item.recipientUserId,
                    messageType: item.messageType,
                    groupId: item.groupId
                )
                continue
            }
            await patchEncrypted(update.encryptedText, update.codeMessage)
            await rebuildTimeline()
        }
    }
}

