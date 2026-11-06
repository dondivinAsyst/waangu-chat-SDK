//
//  OutboxRestartTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 2.5 — le nonce d'un message survit au redémarrage de l'application.
//
//  « Redémarrage » ici : un second magasin SQLite ouvert sur le **même fichier**, avec un
//  nouveau `DatabaseOutbox`, comme le fait un lancement à froid. Rien de l'instance d'avant
//  n'est réutilisé.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

final class OutboxRestartTests: XCTestCase {

    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    /// Ne garde que les éléments de ce test : le fichier est partagé avec les autres tests.
    private final class Seen: @unchecked Sendable {
        private let lock = NSLock()
        private var _items: [ChatOutboxItem] = []
        var items: [ChatOutboxItem] { lock.withLock { _items } }
        func add(_ item: ChatOutboxItem) { lock.withLock { _items.append(item) } }
    }

    private func outbox(on store: any DatabaseRepositoryProtocol, tag: String, seen: Seen,
                        succeed: Bool = true) -> DatabaseOutbox<ChatOutboxItem> {
        DatabaseOutbox<ChatOutboxItem>(
            database: store,
            config: OutboxConfiguration(batchSize: 30, maxRetries: 3, stuckTimeout: 120,
                                        syncedRetention: 86_400, interBatchDelay: 0)
        ) { batch in
            batch.map { item in
                guard item.idempotencyKey.contains(tag) else {
                    return OutboxFlushResult(localId: item.id, success: true)   // les lignes des autres tests
                }
                seen.add(item)
                return OutboxFlushResult(localId: item.id, success: succeed, retryable: !succeed)
            }
        }
    }

    private func dto(_ codeMessage: String) -> OutboundMessageDTO {
        OutboundMessageDTO(
            sessionId: "s", senderId: "me", senderName: "Me", senderPhone: "+25700000000",
            senderAvatar: nil, receiverId: "peer", groupId: nil, conversationId: "conv-\(codeMessage)",
            codeMessage: codeMessage, content: "{}", typeMessage: "TEXT", status: "PENDING",
            forwarded: false, isMoney: false)
    }

    // MARK: Le nonce est écrit une fois, à la création

    /// Le nonce envoyé au serveur, la clé d'idempotence et le `codeMessage` du contenu sont une
    /// seule et même valeur : rien ne peut en inventer une seconde au renvoi.
    func test_theNonce_isTheCodeMessage_inTheKeyAndInThePayload() throws {
        let code = "nonce-\(UUID().uuidString)"

        let item = ChatOutboxItem.sendMessage(dto(code))

        XCTAssertEqual(item.idempotencyKey, "send_message:\(code)")
        let sent = try JSONDecoder().decode(OutboundMessageDTO.self, from: item.payload)
        XCTAssertEqual(sent.codeMessage, code)
    }

    // MARK: Après un redémarrage

    func test_afterARelaunch_theQueuedMessage_isSentWithTheSameNonceAndPayload() async throws {
        let code = "restart-\(UUID().uuidString)"
        let queued = ChatOutboxItem.sendMessage(dto(code))

        // Lancement 1 : le message est mis en file, puis l'application est tuée.
        let firstStore = await makeStore()
        try await outbox(on: firstStore, tag: code, seen: Seen()).enqueue(queued)

        // Lancement 2 : un nouveau magasin sur le même fichier, un nouvel outbox.
        let secondStore = await makeStore()
        let seen = Seen()
        _ = await outbox(on: secondStore, tag: code, seen: seen).flush()

        let sent = try XCTUnwrap(seen.items.first, "le message en file n'a pas été renvoyé")
        XCTAssertEqual(seen.items.count, 1)
        XCTAssertEqual(sent.idempotencyKey, queued.idempotencyKey)
        XCTAssertEqual(sent.id, queued.id)
        XCTAssertEqual(sent.payload, queued.payload, "le contenu envoyé est celui écrit avant la mort du processus")
        let decoded = try JSONDecoder().decode(OutboundMessageDTO.self, from: sent.payload)
        XCTAssertEqual(decoded.codeMessage, code)
    }

    /// Une première tentative échoue (réponse non définitive), puis l'application redémarre : le renvoi
    /// garde le même nonce, le serveur reconnaît le doublon. Une mort **pendant** l'envoi (élément
    /// resté « en cours ») est couverte par `OutboxBehaviourTests.test_flush_picksUpAnItemStuckMidSend_afterTheTimeout`.
    func test_afterAFailedAttemptAndARelaunch_theRetryKeepsTheSameNonce() async throws {
        let code = "midsend-\(UUID().uuidString)"
        let queued = ChatOutboxItem.sendMessage(dto(code))

        let firstStore = await makeStore()
        let firstSeen = Seen()
        // Le premier lancement envoie, mais la réponse n'est pas définitive : l'élément reste en file.
        try await outbox(on: firstStore, tag: code, seen: firstSeen, succeed: false).enqueue(queued)
        _ = await outbox(on: firstStore, tag: code, seen: firstSeen, succeed: false).flush()
        XCTAssertEqual(firstSeen.items.map(\.idempotencyKey), [queued.idempotencyKey])

        let secondStore = await makeStore()
        let secondSeen = Seen()
        _ = await outbox(on: secondStore, tag: code, seen: secondSeen).flush()

        let retried = try XCTUnwrap(secondSeen.items.first)
        XCTAssertEqual(retried.idempotencyKey, queued.idempotencyKey, "même nonce au renvoi")
        XCTAssertEqual(retried.payload, queued.payload)
        XCTAssertEqual(retried.retryCount, 1, "la tentative d'avant est comptée, pas oubliée")
    }

    /// Remettre en file le même message après le redémarrage (même nonce) ne crée pas de doublon.
    func test_enqueuingTheSameMessageAfterARelaunch_doesNotDuplicateIt() async throws {
        let code = "dup-\(UUID().uuidString)"
        let queued = ChatOutboxItem.sendMessage(dto(code))

        let firstStore = await makeStore()
        try await outbox(on: firstStore, tag: code, seen: Seen()).enqueue(queued)

        let secondStore = await makeStore()
        let seen = Seen()
        let relaunched = outbox(on: secondStore, tag: code, seen: seen)
        try await relaunched.enqueue(ChatOutboxItem.sendMessage(dto(code)))
        _ = await relaunched.flush()

        XCTAssertEqual(seen.items.count, 1, "un seul envoi pour un seul nonce")
    }
}
