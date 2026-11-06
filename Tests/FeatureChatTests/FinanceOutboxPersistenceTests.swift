import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// Bloc 1, lot 2.3 — la file financière survit au kill, par compte, sous sa clé
/// d'origine.
///
/// La logique de file est vérifiée sur un stockage en mémoire ; la séparation
/// des comptes, elle, contre la vraie base SQLite, dont le filtre `account_id`
/// est ce qui la garantit.
final class FinanceOutboxPersistenceTests: XCTestCase {

    private func item(
        _ id: String,
        action: FinanceOfflinePolicy.Action = .cancelOwnRequest,
        key: String = "clé-origine"
    ) -> ChatFinanceOutboxItem {
        ChatFinanceOutboxItem(
            id: id,
            action: action,
            reference: FinanceFixtures.reference(type: .moneyRequest, id: "req-\(id)"),
            idempotency: FinanceFixtures.idempotency(key: key)
        )
    }

    private func outbox(
        storage: InMemoryFinanceOutboxStore,
        preserver: MockIdempotencyPreserver,
        account: AccountBox
    ) -> ChatFinanceOutbox {
        ChatFinanceOutbox(
            preserver: preserver,
            logger: SilentLogger(),
            storage: storage,
            currentAccountID: { account.id }
        )
    }

    // MARK: - Survie au kill

    /// Le trousseau survit au kill : même registre, nouvelle file.
    func testQueuedActionIsRestoredAfterRelaunchUnderItsOriginalKey() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let preserver = MockIdempotencyPreserver()
        let account = AccountBox("account-a")

        try await outbox(storage: storage, preserver: preserver, account: account)
            .enqueue(item("op-1", key: "clé-origine"))

        let relaunched = outbox(storage: storage, preserver: preserver, account: account)
        await relaunched.restore()

        let restored = await relaunched.pendingCount
        XCTAssertEqual(restored, 1)

        let keys = KeyCollector()
        await relaunched.flush { sent in
            await keys.record(sent.idempotency.key)
            return true
        }
        let sentKeys = await keys.keys
        XCTAssertEqual(sentKeys, ["clé-origine"])
        let mismatches = await preserver.mismatchCount
        XCTAssertEqual(mismatches, 0)
    }

    func testAcknowledgedActionLeavesTheDisk() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))

        await queue.flush { _ in true }

        let stored = try await storage.load(accountID: "a")
        XCTAssertTrue(stored.isEmpty)
    }

    /// Une tentative ratée est conservée avec son compteur — et la même clé.
    func testFailedAttemptIsKeptOnDiskWithTheSameKey() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox("a"))
        try await queue.enqueue(item("op-1", key: "clé-origine"))

        await queue.flush { _ in false }

        let stored = try await storage.load(accountID: "a")
        XCTAssertEqual(stored.map(\.attemptCount), [1])
        XCTAssertEqual(stored.map(\.idempotency.key), ["clé-origine"])
    }

    // MARK: - Restauration

    func testRestoreOnlyReturnsTheCurrentAccountsActions() async throws {
        let storage = InMemoryFinanceOutboxStore()
        try await storage.save(item("op-a"), accountID: "a")
        try await storage.save(item("op-b"), accountID: "b")

        // Le préservateur réel recharge ses clés du trousseau au relancement ;
        // sans elles, `flush` refuse à juste titre d'envoyer (B42).
        let preserver = MockIdempotencyPreserver()
        try await preserver.register(operationID: "op-b", context: item("op-b").idempotency)

        let queue = outbox(storage: storage, preserver: preserver, account: AccountBox("b"))
        await queue.restore()

        let sent = IDCollector()
        await queue.flush { item in
            await sent.record(item.id)
            return false
        }
        let ids = await sent.ids
        XCTAssertEqual(ids, ["op-b"])
    }

    /// Une confirmation de paiement ne doit jamais repartir d'une file — même
    /// si une ligne en porte une.
    func testRestoreDropsAnActionThatIsNotQueueable() async throws {
        let storage = InMemoryFinanceOutboxStore()
        try await storage.save(item("op-pay", action: .confirmPayment), accountID: "a")

        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox("a"))
        await queue.restore()

        let count = await queue.pendingCount
        XCTAssertEqual(count, 0)
        let stored = try await storage.load(accountID: "a")
        XCTAssertTrue(stored.isEmpty)
    }

    func testRestoreTwiceDoesNotDuplicate() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))

        await queue.restore()
        await queue.restore()

        let count = await queue.pendingCount
        XCTAssertEqual(count, 1)
    }

    func testWithoutSessionNothingIsRestored() async throws {
        let storage = InMemoryFinanceOutboxStore()
        try await storage.save(item("op-1"), accountID: "a")

        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox(nil))
        await queue.restore()

        let count = await queue.pendingCount
        XCTAssertEqual(count, 0)
    }

    // MARK: - Connexion / déconnexion

    /// La connexion réinitialise la mémoire, pas le disque ni les clés : c'est
    /// ce qu'elle restaure juste après.
    func testLoginResetKeepsDiskAndKeys() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let preserver = MockIdempotencyPreserver()
        let queue = outbox(storage: storage, preserver: preserver, account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))

        await queue.clear()
        await queue.restore()

        let count = await queue.pendingCount
        XCTAssertEqual(count, 1)
        let key = await preserver.context(for: "op-1")
        XCTAssertNotNil(key)
    }

    func testLogoutErasesTheLeavingAccountOnly() async throws {
        let storage = InMemoryFinanceOutboxStore()
        try await storage.save(item("op-other"), accountID: "b")
        let preserver = MockIdempotencyPreserver()
        let queue = outbox(storage: storage, preserver: preserver, account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))

        await queue.clear(erasingPersistenceOf: "a")

        let leaving = try await storage.load(accountID: "a")
        let other = try await storage.load(accountID: "b")
        XCTAssertTrue(leaving.isEmpty)
        XCTAssertEqual(other.map(\.id), ["op-other"])
        let key = await preserver.context(for: "op-1")
        XCTAssertNil(key)
    }

    // MARK: - Flush

    /// Une action enfilée pendant un envoi n'est pas perdue par la fin du flush.
    func testActionQueuedDuringFlushIsKept() async throws {
        let storage = InMemoryFinanceOutboxStore()
        let queue = outbox(storage: storage, preserver: MockIdempotencyPreserver(), account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))
        let late = item("op-late", key: "clé-tardive")

        await queue.flush { _ in
            try? await queue.enqueue(late)
            return true
        }

        let count = await queue.pendingCount
        XCTAssertEqual(count, 1)
        let stored = try await storage.load(accountID: "a")
        XCTAssertEqual(stored.map(\.id), ["op-late"])
    }

    /// Un second flush pendant le premier n'envoie rien : pas deux fois la même action.
    func testReentrantFlushDoesNotSendTwice() async throws {
        let queue = outbox(storage: InMemoryFinanceOutboxStore(), preserver: MockIdempotencyPreserver(),
                           account: AccountBox("a"))
        try await queue.enqueue(item("op-1"))
        let sent = IDCollector()

        await queue.flush { item in
            await sent.record(item.id)
            await queue.flush { again in
                await sent.record(again.id)
                return true
            }
            return true
        }

        let ids = await sent.ids
        XCTAssertEqual(ids, ["op-1"])
    }

    // MARK: - Base réelle

    func testDatabaseKeepsAccountsApart() async throws {
        let database = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps)
        )
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: database)
        let store = GRDBFinanceOutboxStore(store: database)
        let first = "test-account-\(UUID().lowercasedString)"
        let second = "test-account-\(UUID().lowercasedString)"
        let firstItem = item("op-\(UUID().lowercasedString)")
        let secondItem = item("op-\(UUID().lowercasedString)")

        try await store.save(firstItem, accountID: first)
        try await store.save(secondItem, accountID: second)
        try await store.clear(accountID: second)

        let firstLoaded = try await store.load(accountID: first)
        let secondLoaded = try await store.load(accountID: second)
        XCTAssertEqual(firstLoaded, [firstItem])
        XCTAssertTrue(secondLoaded.isEmpty)

        try await store.clear(accountID: first)
    }
}

// MARK: - Doublures

/// Stockage en mémoire, qui survit à la file comme le disque survit au kill.
private actor InMemoryFinanceOutboxStore: ChatFinanceOutboxStoring {
    private var rows: [String: (account: String, item: ChatFinanceOutboxItem)] = [:]

    func load(accountID: String) async throws -> [ChatFinanceOutboxItem] {
        rows.values.filter { $0.account == accountID }.map(\.item).sorted { $0.createdAt < $1.createdAt }
    }

    func save(_ item: ChatFinanceOutboxItem, accountID: String) async throws {
        rows[item.id] = (accountID, item)
    }

    func remove(id: String) async throws {
        rows[id] = nil
    }

    func clear(accountID: String) async throws {
        rows = rows.filter { $0.value.account != accountID }
    }
}

/// Compte courant, lu par une fermeture synchrone.
private final class AccountBox: @unchecked Sendable {
    let id: String?
    init(_ id: String?) { self.id = id }
}

private actor IDCollector {
    private(set) var ids: [String] = []
    func record(_ id: String) { ids.append(id) }
}
