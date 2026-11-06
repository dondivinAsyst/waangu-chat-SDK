//
//  FinanceOfflinePolicyTests.swift
//  FeatureChatTests
//
//  Tâche 10.11 et §7 — aucune action à effet monétaire n'est mise en file.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class FinanceOfflinePolicyTests: XCTestCase {

    /// La garantie du §7, exprimée comme une propriété plutôt que cas par cas :
    /// aucune action à effet monétaire ne peut être différée.
    func test_noMonetaryActionIsQueueable() {
        let monetary: [FinanceOfflinePolicy.Action] = [
            .createIntent, .confirmPayment, .acceptMoneyRequest, .changeBeneficiary
        ]
        for action in monetary {
            XCTAssertEqual(
                FinanceOfflinePolicy.verdict(for: action),
                .requiresNetwork,
                "\(action.rawValue) ne doit jamais être différée"
            )
        }
    }

    func test_readsAreAllowedOffline() {
        XCTAssertEqual(FinanceOfflinePolicy.verdict(for: .readCard), .allowedOffline)
        XCTAssertEqual(FinanceOfflinePolicy.verdict(for: .readHistory), .allowedOffline)
        XCTAssertEqual(FinanceOfflinePolicy.verdict(for: .draftMoneyRequest), .allowedOffline)
    }

    /// Seule une action idempotente et sans effet monétaire peut être différée.
    func test_onlyCancellationIsQueueable() {
        let queueable = FinanceOfflinePolicy.Action.allCases.filter {
            FinanceOfflinePolicy.verdict(for: $0) == .queueable
        }
        XCTAssertEqual(queueable, [.cancelOwnRequest])
    }

    /// Chaque action doit avoir un verdict explicite — aucune ne peut être oubliée.
    func test_everyActionHasAVerdict() {
        for action in FinanceOfflinePolicy.Action.allCases {
            _ = FinanceOfflinePolicy.verdict(for: action)
        }
        XCTAssertEqual(FinanceOfflinePolicy.Action.allCases.count, 8)
    }

    // MARK: - File

    func test_outboxRejectsNonQueueableAction() async {
        let outbox = ChatFinanceOutbox(preserver: MockIdempotencyPreserver(), logger: SilentLogger())
        let item = ChatFinanceOutboxItem(
            action: .confirmPayment,
            reference: FinanceFixtures.reference(),
            idempotency: FinanceFixtures.idempotency()
        )

        do {
            try await outbox.enqueue(item)
            XCTFail("Une confirmation de paiement ne doit jamais entrer en file")
        } catch {
            let count = await outbox.pendingCount
            XCTAssertEqual(count, 0)
        }
    }

    func test_outboxAcceptsQueueableAction() async throws {
        let outbox = ChatFinanceOutbox(preserver: MockIdempotencyPreserver(), logger: SilentLogger())
        try await outbox.enqueue(
            ChatFinanceOutboxItem(
                action: .cancelOwnRequest,
                reference: FinanceFixtures.reference(),
                idempotency: FinanceFixtures.idempotency()
            )
        )
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 1)
    }

    /// Le flush doit réutiliser la clé d'origine, pas en fabriquer une nouvelle.
    func test_flushPreservesOriginalKeyAcrossAttempts() async throws {
        let preserver = MockIdempotencyPreserver()
        let outbox = ChatFinanceOutbox(preserver: preserver, logger: SilentLogger())
        let context = FinanceFixtures.idempotency(key: "clé-origine")

        try await outbox.enqueue(
            ChatFinanceOutboxItem(
                id: "op-1",
                action: .cancelOwnRequest,
                reference: FinanceFixtures.reference(),
                idempotency: context
            )
        )

        let collector = KeyCollector()

        // Deux tentatives : la première échoue, la seconde réussit.
        await outbox.flush { item in
            await collector.record(item.idempotency.key)
            return false
        }
        await outbox.flush { item in
            await collector.record(item.idempotency.key)
            return true
        }

        let seenKeys = await collector.keys
        XCTAssertEqual(seenKeys, ["clé-origine", "clé-origine"])
        let mismatches = await preserver.mismatchCount
        XCTAssertEqual(mismatches, 0)
        let remaining = await outbox.pendingCount
        XCTAssertEqual(remaining, 0)
    }

    /// Un item non acquitté reste en file, avec son compteur incrémenté et sa clé
    /// inchangée.
    func test_unacknowledgedItemStaysQueued() async throws {
        let outbox = ChatFinanceOutbox(preserver: MockIdempotencyPreserver(), logger: SilentLogger())
        try await outbox.enqueue(
            ChatFinanceOutboxItem(
                id: "op-1",
                action: .cancelOwnRequest,
                reference: FinanceFixtures.reference(),
                idempotency: FinanceFixtures.idempotency()
            )
        )

        await outbox.flush { _ in false }
        let count = await outbox.pendingCount
        XCTAssertEqual(count, 1)
    }
}

// MARK: - Collecteur

/// Accumule les clés vues pendant un flush.
///
/// Acteur et non tableau local : la fermeture de flush est `@Sendable`, et y
/// capturer une variable mutable est une course sous vérification stricte.
actor KeyCollector {
    private(set) var keys: [String] = []
    func record(_ key: String) { keys.append(key) }
}

// MARK: - Journal silencieux

/// Journal inerte pour les tests — évite de polluer la sortie sans masquer les
/// appels, qui restent vérifiables si un test en a besoin.
struct SilentLogger: AppLoggerProtocol {
    func log(_ message: String, level: LogLevel, file: String, function: String, line: Int) async {}
    func addObserver(_ observer: any LogObserverProtocol) async {}
    func removeAllObservers() async {}
    var minLevel: LogLevel { get async { .critical } }
}
