import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// `GRDBFinancialObjectPersistence` against the real chat SQLite store.
///
/// The isolation tests also prove `FinancialObjectModel` is registered: an
/// unregistered model falls back to the shared JSON proxy table, where filters
/// are ignored, so one account would read the other's rows.
///
/// The store file lives at a fixed path and outlives the test run, so every
/// test uses fresh account ids and clears them when done.
final class FinancialObjectPersistenceTests: XCTestCase {

    private var accounts: [String] = []
    private var store: (any DatabaseRepositoryProtocol)!

    override func setUp() async throws {
        store = await makeStore()
    }

    override func tearDown() async throws {
        for account in accounts {
            await GRDBFinancialObjectPersistence(store: store, accountID: account).clear()
        }
        accounts = []
        store = nil
    }

    private func makeStore() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(
                engine: .sqlite,
                migrationSteps: ChatDatabaseRegistration.migrationSteps
            )
        )
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func newAccount() -> String {
        let account = "test-account-\(UUID().lowercasedString)"
        accounts.append(account)
        return account
    }

    private func object(
        _ id: String,
        version: Int = 1,
        status: PaymentStatus = .processing
    ) -> PersistedFinancialObject {
        PersistedFinancialObject(
            type: FinancialObjectType.allCases[0].rawValue,
            id: id,
            version: version,
            status: status.rawValue,
            lastKnownAt: Date(timeIntervalSinceReferenceDate: 800_000_000)
        )
    }

    // MARK: - Round trip

    func testSavedObjectIsLoadedBack() async {
        let persistence = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let saved = object("obj-1", version: 2)

        await persistence.save(saved)

        let loaded = await persistence.load()
        XCTAssertEqual(loaded, [saved])
    }

    /// A new store instance opens the same file: what an app relaunch does.
    func testObjectSurvivesReopeningTheStore() async {
        let account = newAccount()
        let saved = object("obj-1")
        await GRDBFinancialObjectPersistence(store: store, accountID: account).save(saved)

        let reopened = await makeStore()
        let loaded = await GRDBFinancialObjectPersistence(store: reopened, accountID: account).load()

        XCTAssertEqual(loaded, [saved])
    }

    // MARK: - Account isolation

    func testAccountDoesNotSeeAnotherAccountsObjects() async {
        let first = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let second = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())

        await first.save(object("obj-1"))

        let seenBySecond = await second.load()
        XCTAssertTrue(seenBySecond.isEmpty)
    }

    /// Both accounts know the same object: each keeps its own row and revision.
    func testSameObjectIsKeptSeparatelyPerAccount() async {
        let first = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let second = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())

        await first.save(object("shared", version: 5))
        await second.save(object("shared", version: 1))

        let firstLoaded = await first.load()
        let secondLoaded = await second.load()
        XCTAssertEqual(firstLoaded.map(\.version), [5])
        XCTAssertEqual(secondLoaded.map(\.version), [1])
    }

    func testClearOnlyErasesItsOwnAccount() async {
        let first = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let second = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        await first.save(object("obj-1"))
        await second.save(object("obj-2"))

        await second.clear()

        let firstLoaded = await first.load()
        let secondLoaded = await second.load()
        XCTAssertEqual(firstLoaded.map(\.id), ["obj-1"])
        XCTAssertTrue(secondLoaded.isEmpty)
    }

    // MARK: - Revisions

    func testOlderRevisionDoesNotOverwriteNewerOne() async {
        let persistence = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())

        await persistence.save(object("obj-1", version: 3, status: .completed))
        await persistence.save(object("obj-1", version: 2, status: .processing))

        let loaded = await persistence.load()
        XCTAssertEqual(loaded.map(\.version), [3])
        XCTAssertEqual(loaded.map(\.status), [PaymentStatus.completed.rawValue])
    }

    func testNewerRevisionReplacesOlderOne() async {
        let persistence = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())

        await persistence.save(object("obj-1", version: 1))
        await persistence.save(object("obj-1", version: 2))

        let loaded = await persistence.load()
        XCTAssertEqual(loaded.map(\.version), [2])
    }

    // MARK: - Remove and import

    func testRemoveDeletesOnlyThatObject() async {
        let persistence = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let kept = object("keep")
        let dropped = object("drop")
        await persistence.save(kept)
        await persistence.save(dropped)

        await persistence.remove(type: dropped.type, id: dropped.id)

        let loaded = await persistence.load()
        XCTAssertEqual(loaded, [kept])
    }

    func testImportWritesEveryObject() async throws {
        let persistence = GRDBFinancialObjectPersistence(store: store, accountID: newAccount())
        let legacy = [object("a"), object("b", version: 4)]

        try await persistence.importObjects(legacy)

        let loaded = await persistence.load()
        XCTAssertEqual(Set(loaded), Set(legacy))
    }
}
