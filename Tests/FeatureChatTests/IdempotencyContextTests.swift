//
//  IdempotencyContextTests.swift
//  FeatureChatTests
//
//  Tâche 10.3 — la clé survit aux retries, une clé divergente lève.

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class IdempotencyContextTests: XCTestCase {

    // MARK: - Stabilité de la clé

    /// La règle centrale du §3.3 : N tentatives, une seule clé.
    func test_keySurvivesManyRetries() {
        var context = IdempotencyContext.new(deviceID: "device-1")
        let originalKey = context.key

        for _ in 0..<50 {
            context = context.nextAttempt()
        }

        XCTAssertEqual(context.key, originalKey)
    }

    /// Chaque tentative reste distinguable en observabilité, sans que la clé bouge.
    func test_eachAttemptHasNewRequestIDButSameKey() {
        let first = IdempotencyContext.new(deviceID: "device-1")
        let second = first.nextAttempt()

        XCTAssertEqual(first.key, second.key)
        XCTAssertNotEqual(first.clientRequestID, second.clientRequestID)
        XCTAssertEqual(first.correlationID, second.correlationID)
        XCTAssertEqual(first.createdAt, second.createdAt)
    }

    /// L'âge se mesure depuis la création de la clé, pas depuis la dernière
    /// tentative — sinon un retry indéfini repousserait la péremption pour toujours.
    func test_ageIsMeasuredFromKeyCreation() {
        let old = Date().addingTimeInterval(-3600)
        let context = IdempotencyContext(
            key: "k", clientRequestID: UUID(),
            correlationID: CorrelationId(value: "c"),
            deviceID: "d", createdAt: old
        )
        XCTAssertEqual(context.nextAttempt().age(), context.age(), accuracy: 1)
        XCTAssertGreaterThan(context.age(), 3500)
    }

    /// Deux appareils ne doivent pas pouvoir produire la même clé.
    func test_keysAreDeviceScoped() {
        let a = IdempotencyContext.new(deviceID: "device-a")
        let b = IdempotencyContext.new(deviceID: "device-b")
        XCTAssertNotEqual(a.key, b.key)
        XCTAssertTrue(a.key.contains("device-a"))
    }

    /// La clé doit survivre au disque : c'est la condition pour couvrir le kill
    /// d'application entre soumission et réponse.
    func test_contextRoundTripsThroughCoding() throws {
        let original = IdempotencyContext.new(deviceID: "device-1")
        let data = try JSONEncoder().encode(original)
        let restored = try JSONDecoder().decode(IdempotencyContext.self, from: data)
        XCTAssertEqual(original, restored)
        XCTAssertEqual(original.key, restored.key)
    }

    // MARK: - Préservation

    func test_divergentKeyThrows() async throws {
        let preserver = MockIdempotencyPreserver()
        let context = IdempotencyContext.new(deviceID: "device-1")

        try await preserver.register(operationID: "op-1", context: context)
        try await preserver.assertSameKey(operationID: "op-1", providedKey: context.key)

        do {
            try await preserver.assertSameKey(operationID: "op-1", providedKey: "clé-fabriquée")
            XCTFail("Une clé divergente doit lever")
        } catch {
            let count = await preserver.mismatchCount
            XCTAssertEqual(count, 1)
        }
    }

    /// Réenregistrer la même opération sous une autre clé effacerait la clé
    /// d'origine, donc autoriserait une seconde soumission.
    func test_reregisteringWithDifferentKeyThrows() async throws {
        let preserver = MockIdempotencyPreserver()
        try await preserver.register(operationID: "op-1", context: .new(deviceID: "d"))

        do {
            try await preserver.register(operationID: "op-1", context: .new(deviceID: "d"))
            XCTFail("Un réenregistrement sous une autre clé doit lever")
        } catch {
            // attendu
        }
    }

    /// Une opération inconnue ne doit pas être considérée comme un rejeu valide.
    func test_unknownOperationRejectsAssertion() async {
        let preserver = MockIdempotencyPreserver()
        do {
            try await preserver.assertSameKey(operationID: "jamais-vue", providedKey: "k")
            XCTFail("Une opération inconnue doit lever")
        } catch {
            // attendu
        }
    }
}
