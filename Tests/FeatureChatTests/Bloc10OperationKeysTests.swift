//
//  Bloc10OperationKeysTests.swift
//  FeatureChatTests
//
//  §4 et §21.E — zéro double transaction, y compris après fermeture ou crash.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

/// Registre en mémoire qui se comporte comme celui du trousseau : même clé
/// réenregistrée sans effet, clé différente refusée.
private actor InMemoryPreserver: IdempotencyKeyPreserving {
    private(set) var contexts: [String: IdempotencyContext] = [:]
    private(set) var releases = 0

    func register(operationID: String, context: IdempotencyContext) async throws {
        if let existing = contexts[operationID], existing.key != context.key {
            throw IdempotencyViolation.alreadyRegistered(operationID: operationID)
        }
        contexts[operationID] = context
    }
    func context(for operationID: String) async -> IdempotencyContext? { contexts[operationID] }
    func assertSameKey(operationID: String, providedKey: String) async throws {}
    func purge(userID: String) async { contexts.removeAll() }
    func release(operationID: String) async { contexts[operationID] = nil; releases += 1 }
    func storedIDs() -> [String] { Array(contexts.keys) }
}

final class FinanceOperationKeysTests: XCTestCase {

    // MARK: - Nouvelle tentative : même clé

    func test_retryOfSameOperation_reusesTheOriginalKey() async {
        let keys = FinanceOperationKeys()
        let scope = FinanceOperationKeys.scope("bill.pay", "bill-7", 18_000)
        let first = await keys.key(for: scope, deviceID: "d")
        let retry = await keys.key(for: scope, deviceID: "d")
        XCTAssertEqual(first.key, retry.key,
                       "Une nouvelle tentative doit porter la clé d'origine, sinon le serveur exécute deux fois")
    }

    // MARK: - Fermeture de l'écran / crash : même clé

    func test_retryAfterScreenClosedOrAppRelaunched_reusesThePersistedKey() async {
        let preserver = InMemoryPreserver()
        let scope = FinanceOperationKeys.scope("bill.pay", "bill-7", 18_000)

        // Premier écran : tentative, délai dépassé, l'écran se ferme.
        let firstScreen = FinanceOperationKeys(preserver: preserver)
        let original = await firstScreen.key(for: scope, deviceID: "d")

        // Nouvelle instance, cache vide : c'est l'app relancée ou l'écran rouvert.
        let reopened = FinanceOperationKeys(preserver: preserver)
        let retry = await reopened.key(for: scope, deviceID: "d")

        XCTAssertEqual(original.key, retry.key,
                       "Rouvrir l'écran ne doit pas refabriquer une clé : c'était le double débit un geste plus loin")
    }

    // MARK: - Opérations distinctes : clés distinctes

    func test_distinctOperationsOnSameScreen_neverShareAKey() async {
        let keys = FinanceOperationKeys()
        let create = await keys.key(for: FinanceOperationKeys.scope("split.create", "s-1"), deviceID: "d")
        let contribute = await keys.key(for: FinanceOperationKeys.scope("split.contribute", "s-1"), deviceID: "d")
        XCTAssertNotEqual(create.key, contribute.key,
                          "Une clé partagée ferait écarter la seconde opération comme doublon")
    }

    // MARK: - Charge utile modifiée : clé neuve

    func test_changedAmount_producesANewKey_soTheOldPaymentIsNotReplayed() async {
        let keys = FinanceOperationKeys()
        let atThree = await keys.key(for: FinanceOperationKeys.scope("bill.pay", "bill-7", 3_000), deviceID: "d")
        let atFive = await keys.key(for: FinanceOperationKeys.scope("bill.pay", "bill-7", 5_000), deviceID: "d")
        XCTAssertNotEqual(atThree.key, atFive.key,
                          "Rejouer l'ancienne clé rendrait l'ancien montant sous l'apparence d'une réussite")
    }

    // MARK: - Libération après succès établi

    func test_releaseAfterSuccess_allowsAGenuinelyNewOperation_andClearsPersistence() async {
        let preserver = InMemoryPreserver()
        let keys = FinanceOperationKeys(preserver: preserver)
        let scope = FinanceOperationKeys.scope("card.freeze", "card-1", true)

        let first = await keys.key(for: scope, deviceID: "d")
        await keys.release(scope)
        let second = await keys.key(for: scope, deviceID: "d")

        XCTAssertNotEqual(first.key, second.key,
                          "Geler, dégeler puis geler de nouveau sont trois opérations")
        let releases = await preserver.releases
        XCTAssertEqual(releases, 1, "La libération doit aussi atteindre le registre persistant")
    }

    // MARK: - Confidentialité du trousseau

    func test_persistedIdentifier_neverContainsThePayload() async {
        let preserver = InMemoryPreserver()
        let keys = FinanceOperationKeys(preserver: preserver)
        let scope = FinanceOperationKeys.scope("send", "Yohana Ndayisenga", "0950656966", 250_000)
        _ = await keys.key(for: scope, deviceID: "d")

        let stored = await preserver.storedIDs()
        XCTAssertEqual(stored.count, 1)
        let id = stored[0]
        for secret in ["Yohana", "0950656966", "250000", "250,000"] {
            XCTAssertFalse(id.contains(secret), "« \(secret) » ne doit pas entrer en clair dans le trousseau")
        }
        XCTAssertTrue(id.hasPrefix("op."))
        XCTAssertEqual(id, FinanceOperationKeys.operationID(for: scope),
                       "L'empreinte doit être stable pour retrouver la clé après relance")
    }

    // MARK: - Registre défaillant : protection du processus conservée

    func test_whenPreserverRefuses_keyIsStillStableInProcess() async {
        let keys = FinanceOperationKeys(preserver: ClosedIdempotencyKeyPreserver())
        let scope = FinanceOperationKeys.scope("topup.order", "0795", "p-1")
        let first = await keys.key(for: scope, deviceID: "d")
        let retry = await keys.key(for: scope, deviceID: "d")
        XCTAssertEqual(first.key, retry.key,
                       "Un registre fermé ne doit pas ramener au comportement d'une clé par tentative")
    }

    // MARK: - Portée non ambiguë

    func test_scopeSeparator_preventsCollisions() {
        XCTAssertNotEqual(FinanceOperationKeys.scope("op", "a|b", "c"),
                          FinanceOperationKeys.scope("op", "a", "b|c"))
        XCTAssertNotEqual(FinanceOperationKeys.scope("op", "ab", "c"),
                          FinanceOperationKeys.scope("op", "a", "bc"))
    }
}
