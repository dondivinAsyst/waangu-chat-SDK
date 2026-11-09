//
//  PaymentsTests.swift
//  WaanguChatSDKTests
//
//  SDK plan, step 1.9 — payments in the facade: off unless the host asks, live when it does, and
//  the saved payment operations are kept per account. The persistence moved from the Waangu app
//  target, where it had no tests.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
import WaanguFeatureChat
@testable import WaanguChatSDK

final class FacadePaymentsTests: XCTestCase {

    private func configuration(payments: Bool) -> WaanguChatConfiguration {
        WaanguChatConfiguration(
            appId: "test-host", userId: "test-user",
            chatBaseURL: "https://chat.test.invalid",
            chatUploadBaseURL: "https://upload.test.invalid",
            mainAPIBaseURL: "https://main.test.invalid",
            realtime: .init(host: "mqtt.test.invalid", port: 8883, useTLS: true),
            keychainService: "com.test.waangu-chat-sdk",
            modules: payments ? ChatModule.standard.union([.payments]) : ChatModule.standard
        )
    }

    private func dependencies(payments: Bool) async throws -> ChatDependencies {
        let database = await WaanguChat.makeDatabase()
        let chat = WaanguChat(configuration: configuration(payments: payments),
                              database: database, tokenManager: HostTokens())
        return try await chat.makeChatDependencies()
    }

    func test_paymentsAreOffByDefault() {
        let withoutFlag = WaanguChatConfiguration(
            appId: "a", userId: "test-user", chatBaseURL: "c", chatUploadBaseURL: "u", mainAPIBaseURL: "m",
            realtime: .init(host: "h", port: 1, useTLS: false), keychainService: "k")

        XCTAssertFalse(withoutFlag.modules.contains(.payments))
    }

    /// A messaging-and-calls host: every payment service is the closed one, nothing is saved.
    func test_withPaymentsOff_everyPaymentServiceIsClosed() async throws {
        let deps = try await dependencies(payments: false)

        XCTAssertTrue(deps.killSwitch is ClosedKillSwitch)
        XCTAssertTrue(deps.financeCatalog is ClosedChatFinanceCatalog)
        XCTAssertTrue(deps.recipientResolver is ClosedRecipientResolver)
        XCTAssertTrue(deps.bills is ClosedBillPaying)
        XCTAssertTrue(deps.cashIn is ClosedCashIn)
        XCTAssertNil(deps.financeAPIClient)
        XCTAssertNil(deps.financeSession)
        XCTAssertNil(deps.financialObjectPersistence)
        XCTAssertNil(deps.moneyRequestResponder)
        XCTAssertNil(deps.billFieldValidator)
    }

    func test_withPaymentsOn_theChatCoreServicesAreLive() async throws {
        let deps = try await dependencies(payments: true)

        XCTAssertFalse(deps.killSwitch is ClosedKillSwitch)
        XCTAssertFalse(deps.financeCatalog is ClosedChatFinanceCatalog)
        XCTAssertFalse(deps.recipientResolver is ClosedRecipientResolver)
        XCTAssertFalse(deps.bills is ClosedBillPaying)
        XCTAssertFalse(deps.cashIn is ClosedCashIn)
        XCTAssertNotNil(deps.financeAPIClient)
        XCTAssertNotNil(deps.financeSession)
        XCTAssertNotNil(deps.financialObjectPersistence, "an operation killed mid-flight must be recoverable")
        XCTAssertNotNil(deps.moneyRequestResponder)
        XCTAssertNotNil(deps.billFieldValidator)
    }

    /// Services with no live version are not simulated: a screen never shows an invented value.
    func test_withPaymentsOn_servicesWithoutALiveVersionStayClosed() async throws {
        let deps = try await dependencies(payments: true)

        XCTAssertTrue(deps.cards is ClosedCardManager)
        XCTAssertTrue(deps.mandates is ClosedMandateManaging)
        XCTAssertTrue(deps.remittance is ClosedRemittance)
        XCTAssertTrue(deps.fx is ClosedFX)
    }
}

// MARK: - Account-scoped persistence

final class AccountScopedFinancialObjectPersistenceTests: XCTestCase {

    private final class Account: @unchecked Sendable {
        private let lock = NSLock()
        private var _id: String?
        init(_ id: String?) { _id = id }
        var id: String? { lock.withLock { _id } }
        func switchTo(_ id: String?) { lock.withLock { _id = id } }
    }

    private func object(_ id: String, version: Int = 1, status: String = "PENDING") -> PersistedFinancialObject {
        PersistedFinancialObject(type: "TRANSFER", id: id, version: version, status: status, lastKnownAt: Date())
    }

    private func makeStore(account: Account) async -> (AccountScopedFinancialObjectPersistence, any DatabaseRepositoryProtocol) {
        let database = await WaanguChat.makeDatabase()
        // The legacy JSON import looks in a folder of its own, so no test touches a real one.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("fin-\(UUID().uuidString)")
        let store = AccountScopedFinancialObjectPersistence(
            database: database, currentAccountID: { account.id }, legacyDirectory: folder)
        return (store, database)
    }

    func test_savedOperations_areReadBack() async {
        let (store, _) = await makeStore(account: Account("user-\(UUID().uuidString)"))

        await store.save(object("op-1"))
        await store.save(object("op-2"))

        let loaded = await store.load()
        XCTAssertEqual(Set(loaded.map(\.id)), ["op-1", "op-2"])
    }

    /// The account is read at each call: after a switch, the new account never sees the old one's rows.
    func test_anotherAccount_doesNotSeeTheFirstAccountsOperations() async {
        let first = "user-\(UUID().uuidString)", second = "user-\(UUID().uuidString)"
        let account = Account(first)
        let (store, _) = await makeStore(account: account)
        await store.save(object("op-of-first"))

        account.switchTo(second)
        let seenBySecond = await store.load()
        await store.save(object("op-of-second"))

        XCTAssertTrue(seenBySecond.isEmpty, "\(seenBySecond)")
        account.switchTo(first)
        let backToFirst = await store.load()
        XCTAssertEqual(backToFirst.map(\.id), ["op-of-first"])
    }

    func test_withoutASession_nothingIsReadOrWritten() async {
        let account = Account(nil)
        let (store, _) = await makeStore(account: account)

        await store.save(object("ignored"))
        let loaded = await store.load()

        XCTAssertTrue(loaded.isEmpty)
        account.switchTo("user-\(UUID().uuidString)")
        let later = await store.load()
        XCTAssertTrue(later.isEmpty, "a save made without a session must not appear for the next account")
    }

    func test_removeDeletesOneOperation() async {
        let (store, _) = await makeStore(account: Account("user-\(UUID().uuidString)"))
        await store.save(object("keep"))
        await store.save(object("drop"))

        await store.remove(type: "TRANSFER", id: "drop")

        let loaded = await store.load()
        XCTAssertEqual(loaded.map(\.id), ["keep"])
    }

    /// At sign-out the session may already be gone: the rows of the account that leaves are the ones to clear.
    func test_clear_emptiesTheAccountThatLeaves_evenAfterTheSessionIsGone() async {
        let id = "user-\(UUID().uuidString)"
        let account = Account(id)
        let (store, _) = await makeStore(account: account)
        await store.save(object("op"))

        account.switchTo(nil)
        await store.clear()

        account.switchTo(id)
        let loaded = await store.load()
        XCTAssertTrue(loaded.isEmpty, "\(loaded)")
    }

    func test_anOlderVersion_neverOverwritesANewerOne() async {
        let (store, _) = await makeStore(account: Account("user-\(UUID().uuidString)"))
        await store.save(object("op", version: 5, status: "SETTLED"))

        await store.save(object("op", version: 3, status: "PENDING"))

        let loaded = await store.load()
        XCTAssertEqual(loaded.first?.version, 5)
        XCTAssertEqual(loaded.first?.status, "SETTLED")
    }
}
