//
//  ChatMetricsTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.13 — les mesures que le Chat remet à l'hôte, et ce qu'elles ne
//  contiennent jamais : aucun identifiant, aucun texte, aucun motif d'échec.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

/// Retient les mesures reçues.
final class RecordingMetricsSink: ChatMetricsSink, @unchecked Sendable {
    private let lock = NSLock()
    private var _metrics: [ChatMetric] = []

    var metrics: [ChatMetric] { lock.withLock { _metrics } }
    func named(_ name: String) -> [ChatMetric] { metrics.filter { $0.name == name } }

    func record(_ metric: ChatMetric) {
        lock.withLock { _metrics.append(metric) }
    }
}

// MARK: - Envoi → accusé

final class SendToAckMetricTests: XCTestCase {

    private func store() async -> any DatabaseRepositoryProtocol {
        let store = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: store)
        return store
    }

    /// Enregistre un message `pending` créé il y a `age` secondes, puis traite `type`.
    private func receive(
        _ type: String,
        messageAge age: TimeInterval,
        deliveryStatus: MessageDeliveryStatusModel = .pending,
        sink: RecordingMetricsSink
    ) async throws {
        let store = await store()
        let conversation = ConversationModel(id: "conv-\(UUID().uuidString)", type: .direct)
        try await store.save(conversation)
        let message = MessageModel(conversationId: conversation.id, senderId: "me", senderName: "Me",
                                   timestamp: Date().addingTimeInterval(-age), deliveryStatus: deliveryStatus)
        try await store.save(message)

        let delegate = ChatSyncDelegate(fieldCrypto: PassthroughCrypto(), metricsSink: sink)
        let receipt = ChatSyncEventDTO(type: type, referenceId: message.id, conversationId: message.conversationId,
                                       payload: nil, at: Date().timeIntervalSince1970)
        await delegate.processEvent(receipt, database: store)
    }

    func test_firstAcknowledgement_reportsTheWait() async throws {
        let sink = RecordingMetricsSink()

        try await receive("sent_receipt", messageAge: 2, sink: sink)

        let metrics = sink.named("send_to_ack")
        XCTAssertEqual(metrics.count, 1)
        let waited = try XCTUnwrap(metrics.first?.durationMs)
        XCTAssertTrue((1_900...30_000).contains(waited), "\(waited) ms")
        XCTAssertTrue(metrics[0].attributes.isEmpty)
    }

    /// Un second accusé trouve le message déjà `sent` : rien de nouveau à mesurer.
    func test_aMessageAlreadySent_isNotMeasuredAgain() async throws {
        let sink = RecordingMetricsSink()

        try await receive("sent_receipt", messageAge: 2, deliveryStatus: .sent, sink: sink)

        XCTAssertTrue(sink.named("send_to_ack").isEmpty)
    }

    func test_aSendFailure_isNotMeasuredAsAnAcknowledgement() async throws {
        let sink = RecordingMetricsSink()

        try await receive("send_failed", messageAge: 2, sink: sink)

        XCTAssertTrue(sink.named("send_to_ack").isEmpty)
    }

    /// Téléphone en avance sur le serveur : jamais de durée négative.
    func test_aPhoneClockAheadOfNow_reportsZero_notANegative() async throws {
        let sink = RecordingMetricsSink()

        try await receive("sent_receipt", messageAge: -3_600, sink: sink)

        XCTAssertEqual(sink.named("send_to_ack").first?.durationMs, 0)
    }
}

private struct PassthroughCrypto: FieldEncryptionServiceProtocol {
    func encrypt(_ value: String) -> String { value }
    func decrypt(_ value: String) -> String { value }
    func encryptOptional(_ value: String?) -> String? { value }
    func decryptOptional(_ value: String?) -> String? { value }
    func encryptData(_ data: Data) -> Data { data }
    func decryptData(_ data: Data) -> Data { data }
}

// MARK: - Ouverture d'une conversation

@MainActor
final class ConversationOpenMetricTests: XCTestCase {

    private struct LoadFailed: Error {}

    private struct StubLoadPage: LoadMessagesPageUseCaseProtocol {
        let fails: Bool
        func execute(conversationId: String, before cursor: Date?, pageSize: Int) async throws -> ChatRoomPaginationResult {
            if fails { throw LoadFailed() }
            return ChatRoomPaginationResult(messages: [], allMediaMessages: [], oldestLoadedDate: nil, hasMore: false)
        }
    }

    private struct EmptyObservation: ObserveMessagesUseCaseProtocol {
        func execute(conversationId: String) -> AsyncStream<Result<[MessageDataItem], DatabaseError>> {
            AsyncStream { $0.finish() }
        }
    }

    private struct EmptyTyping: ObserveTypingUseCaseProtocol {
        func execute(conversationId: String) async throws -> AsyncStream<[TypingUser]> {
            AsyncStream { $0.finish() }
        }
    }

    private struct SilentPresence: PresenceRepositoryProtocol {
        func runTypingFeed() async throws {}
        func sendTyping(conversationId: String, type: TypingPayloadType) async {}
        func sendUserPresence(status: PresenceStatus, currentRideId: String?) async {}
        func runPresenceFeed() async throws {}
        func cleanup() async {}
    }

    private func open(failing: Bool, sink: RecordingMetricsSink) async {
        let session = ChatRoomSessionUseCase(
            observeMessages: EmptyObservation(),
            observeTyping: EmptyTyping(),
            loadMessagesPage: StubLoadPage(fails: failing),
            discussionRepository: RecordingDiscussionRepository(),
            presenceRepository: SilentPresence(),
            metricsSink: sink
        )
        let store = ChatRoomMessagesStore()
        await session.start(conversationId: "conv-\(UUID().uuidString)", store: store)
        await session.stop(store: store)
    }

    func test_aRoomThatOpens_reportsItsLatency() async {
        let sink = RecordingMetricsSink()

        await open(failing: false, sink: sink)

        let metrics = sink.named("conversation_open")
        XCTAssertEqual(metrics.count, 1)
        XCTAssertNotNil(metrics.first?.durationMs)
        XCTAssertEqual(metrics.first?.attributes, ["result": "ok"])
    }

    func test_aRoomThatFailsToLoad_reportsTheFailure() async {
        let sink = RecordingMetricsSink()

        await open(failing: true, sink: sink)

        XCTAssertEqual(sink.named("conversation_open").first?.attributes, ["result": "failed"])
    }

    /// Le conversationId d'une ouverture ne figure dans aucune mesure.
    func test_noMetricCarriesTheConversationId() async {
        let sink = RecordingMetricsSink()
        let store = ChatRoomMessagesStore()
        let session = ChatRoomSessionUseCase(
            observeMessages: EmptyObservation(), observeTyping: EmptyTyping(),
            loadMessagesPage: StubLoadPage(fails: false),
            discussionRepository: RecordingDiscussionRepository(),
            presenceRepository: SilentPresence(), metricsSink: sink)

        await session.start(conversationId: "conv_SECRET", store: store)
        await session.stop(store: store)

        for metric in sink.metrics {
            XCTAssertFalse("\(metric)".contains("SECRET"), "\(metric)")
        }
    }
}

// MARK: - Reconnexion et échecs de synchro

final class ReconnectMetricTests: XCTestCase {

    private typealias Report = ChatReconnectSequence.Report

    func test_aCleanReconnect_isOneMetric() {
        let report = Report(result: .finished, outcomes: [
            .init(step: .deltaSync, outcome: .completed),
            .init(step: .drainChatOutbox, outcome: .completed),
            .init(step: .refreshMembership, outcome: .skipped("no contract")),
        ])

        let metrics = report.metrics(trigger: .reconnect, durationMs: 420)

        XCTAssertEqual(metrics, [ChatMetric(name: "reconnect", durationMs: 420, attributes: [
            "trigger": "reconnect", "result": "finished", "failed_steps": "0",
        ])])
    }

    func test_aFailedAndATimedOutStep_eachReportASyncFailure() {
        let report = Report(result: .finished, outcomes: [
            .init(step: .deltaSync, outcome: .failed("https://x.test/conv_SECRET?token=tok_SECRET")),
            .init(step: .drainFinanceOutbox, outcome: .timedOut),
            .init(step: .drainChatOutbox, outcome: .completed),
        ])

        let metrics = report.metrics(trigger: .reconnect, durationMs: 9_000)

        XCTAssertEqual(metrics.map(\.name), ["reconnect", "sync_failure", "sync_failure"])
        XCTAssertEqual(metrics[0].attributes["failed_steps"], "2")
        XCTAssertEqual(metrics[1].attributes, ["source": "reconnect", "step": "deltaSync", "outcome": "failed"])
        XCTAssertEqual(metrics[2].attributes, ["source": "reconnect", "step": "drainFinanceOutbox", "outcome": "timed_out"])
    }

    /// Le texte d'un échec peut citer une URL ou un jeton : il ne sort pas.
    func test_aFailureText_neverLeavesInAMetric() {
        let report = Report(result: .finished, outcomes: [
            .init(step: .deltaSync, outcome: .failed("conv_SECRET tok_SECRET")),
        ])

        for metric in report.metrics(trigger: .reconnect, durationMs: 1) {
            XCTAssertFalse("\(metric)".contains("SECRET"), "\(metric)")
        }
    }

    func test_aSessionThatNeedsReauthentication_isSaidSo() {
        let report = Report(result: .stoppedForReauthentication, outcomes: [
            .init(step: .reauthenticate, outcome: .completed),
        ])

        let metrics = report.metrics(trigger: .reconnect, durationMs: 5)

        XCTAssertEqual(metrics.first?.attributes["result"], "stopped_for_reauthentication")
    }

    func test_startup_isNamedAsSuch() {
        let report = Report(result: .finished, outcomes: [.init(step: .drainChatOutbox, outcome: .completed)])

        XCTAssertEqual(report.metrics(trigger: .startup, durationMs: 1).first?.attributes["trigger"], "startup")
    }
}

// MARK: - Le défaut ne change rien

final class NoChatMetricsTests: XCTestCase {

    func test_theDefaultSink_dropsEverything() {
        NoChatMetrics().record(ChatMetric(name: "reconnect", durationMs: 1))
    }

    func test_elapsedTime_isInMilliseconds() async throws {
        let start = ContinuousClock.now

        try await Task.sleep(nanoseconds: 120_000_000)

        let elapsed = ChatMetric.elapsedMs(since: start)
        XCTAssertTrue((100...5_000).contains(elapsed), "\(elapsed) ms")
    }
}
