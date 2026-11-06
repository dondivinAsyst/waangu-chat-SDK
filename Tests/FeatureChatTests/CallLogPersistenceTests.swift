import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// Exercises the call log against a real SQLite store.
///
/// The risky parts are not the Swift: they are whether the filters name the
/// columns the schema builder actually created (it uses `indexedFields`
/// verbatim, so camelCase), and whether a log with no conversation survives the
/// foreign key on `conversationId`.
final class CallLogPersistenceTests: XCTestCase {

    /// Mirrors how the app builds its chat store: a searchable SQLite store with
    /// `ChatDatabaseRegistration` registered.
    ///
    /// The registration is not optional. Without it the model has no dedicated
    /// table and every read falls through to `fetchFromProxy`, which applies
    /// LIMIT and OFFSET but silently ignores the filter — so a filter test would
    /// pass back rows it was supposed to exclude.
    private func makeStore() async -> any SearchableDatabaseProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(
                engine: .sqlite,
                migrationSteps: ChatDatabaseRegistration.migrationSteps
            )
        )
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    private func makeDataSource() async throws -> LocalCallDataSourceProtocol {
        let dataSource = GRDBCallDataSource(store: await makeStore())
        // The store is a file on disk shared across test methods and runs.
        try await dataSource.deleteAll()
        return dataSource
    }

    private func makeLog(
        id: String,
        outcome: CallOutcome,
        direction: CallDirection = .incoming,
        media: CallMedia = .voice,
        startedAt: Date = Date(),
        durationSeconds: Int = 0
    ) -> CallLogEntity {
        CallLogEntity(
            id: id,
            contactName: "Test Contact",
            contactPhone: "+243897654321",
            media: media,
            direction: direction,
            outcome: outcome,
            durationSeconds: durationSeconds,
            startedAt: startedAt
        )
    }

    // MARK: - Round trip

    func test_savesAndReadsBackACallWithNoConversation() async throws {
        let dataSource = try await makeDataSource()
        let id = UUID().uuidString.lowercased()

        try await dataSource.save(
            makeLog(id: id, outcome: .answered, direction: .outgoing, media: .video, durationSeconds: 42)
        )

        let stored = try await dataSource.fetchOne(id: id)
        let log = try XCTUnwrap(stored, "a call log with a nil conversationId must survive the foreign key")

        XCTAssertEqual(log.outcome, .answered)
        XCTAssertEqual(log.direction, .outgoing)
        XCTAssertEqual(log.media, .video)
        XCTAssertEqual(log.durationSeconds, 42)
        XCTAssertEqual(log.contactPhone, "+243897654321")

        try await dataSource.delete(id: id)
    }

    /// The whole point of the rewrite: calls that never connected are logged too.
    func test_persistsEveryTerminalOutcome() async throws {
        let dataSource = try await makeDataSource()
        let outcomes: [CallOutcome] = [.answered, .missed, .declined, .cancelled, .noAnswer, .busy]
        var ids: [String] = []

        for outcome in outcomes {
            let id = UUID().uuidString.lowercased()
            ids.append(id)
            try await dataSource.save(makeLog(id: id, outcome: outcome))
        }

        for (id, outcome) in zip(ids, outcomes) {
            let stored = try await dataSource.fetchOne(id: id)
            XCTAssertEqual(stored?.outcome, outcome, "\(outcome) did not round trip")
        }

        for id in ids { try await dataSource.delete(id: id) }
    }

    // MARK: - Filtering

    func test_missedFilterMatchesOnTheStatusColumn() async throws {
        let dataSource = try await makeDataSource()
        try await dataSource.deleteAll()

        let missedId = UUID().uuidString.lowercased()
        let noAnswerId = UUID().uuidString.lowercased()
        let answeredId = UUID().uuidString.lowercased()

        try await dataSource.save(makeLog(id: missedId, outcome: .missed))
        try await dataSource.save(makeLog(id: noAnswerId, outcome: .noAnswer))
        try await dataSource.save(makeLog(id: answeredId, outcome: .answered))

        let missed = try await dataSource.fetchAll(filter: .missed, limit: nil)
        let missedIds = Set(missed.map(\.id))

        // An empty result here means the filter named a column that does not exist.
        XCTAssertTrue(missedIds.contains(missedId))
        XCTAssertTrue(missedIds.contains(noAnswerId))
        XCTAssertFalse(missedIds.contains(answeredId))

        try await dataSource.deleteAll()
    }

    // MARK: - Ordering

    func test_returnsNewestFirstAndRespectsLimit() async throws {
        let dataSource = try await makeDataSource()
        try await dataSource.deleteAll()

        let now = Date()
        let oldestId = UUID().uuidString.lowercased()
        let middleId = UUID().uuidString.lowercased()
        let newestId = UUID().uuidString.lowercased()

        try await dataSource.save(makeLog(id: middleId, outcome: .missed, startedAt: now.addingTimeInterval(-600)))
        try await dataSource.save(makeLog(id: oldestId, outcome: .missed, startedAt: now.addingTimeInterval(-3600)))
        try await dataSource.save(makeLog(id: newestId, outcome: .missed, startedAt: now))

        let all = try await dataSource.fetchAll(filter: .all, limit: nil)
        XCTAssertEqual(all.map(\.id), [newestId, middleId, oldestId])

        let limited = try await dataSource.fetchAll(filter: .all, limit: 2)
        XCTAssertEqual(limited.map(\.id), [newestId, middleId])

        try await dataSource.deleteAll()
    }

    /// Re-saving the same call id updates it instead of adding a second row, so
    /// a call logged while ringing can be upgraded when it ends.
    func test_resavingSameIdUpdatesInPlace() async throws {
        let dataSource = try await makeDataSource()
        try await dataSource.deleteAll()

        let id = UUID().uuidString.lowercased()
        try await dataSource.save(makeLog(id: id, outcome: .missed))
        try await dataSource.save(makeLog(id: id, outcome: .answered, durationSeconds: 30))

        let all = try await dataSource.fetchAll(filter: .all, limit: nil)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.outcome, .answered)
        XCTAssertEqual(all.first?.durationSeconds, 30)

        try await dataSource.deleteAll()
    }
}
