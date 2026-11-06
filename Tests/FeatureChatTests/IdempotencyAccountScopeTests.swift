//
//  IdempotencyAccountScopeTests.swift
//  FeatureChatTests
//
//  Les clés d'idempotence appartiennent à un compte — Bloc 1 P0-3, dernier volet.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class IdempotencyAccountScopeTests: XCTestCase {

    /// La purge doit viser l'identifiant porté par l'événement de logout, et non
    /// « l'utilisateur courant », qui peut déjà avoir été effacé de la session.
    func test_purgeTargetsTheIdentifierItWasGiven() async {
        let preserver = MockIdempotencyPreserver()
        try? await preserver.register(
            operationID: "op-A",
            context: FinanceFixtures.idempotency(key: "key-A")
        )

        await preserver.purge(userID: "user-A")

        let purged = await preserver.purgedUserIDs
        XCTAssertEqual(purged, ["user-A"])

        let survivor = await preserver.context(for: "op-A")
        XCTAssertNil(survivor, "aucune clé du compte purgé ne survit")
    }

    /// Après purge, le compte suivant repart d'un espace vide : le même
    /// identifiant d'opération ne retrouve pas la clé du compte précédent.
    func test_nextAccountDoesNotInheritKeys() async {
        let preserver = MockIdempotencyPreserver()

        try? await preserver.register(
            operationID: "op-shared",
            context: FinanceFixtures.idempotency(key: "key-of-A")
        )
        await preserver.purge(userID: "user-A")

        // B réutilise le même identifiant d'opération — cas ordinaire, puisque
        // l'identifiant dérive du geste, pas du compte.
        try? await preserver.register(
            operationID: "op-shared",
            context: FinanceFixtures.idempotency(key: "key-of-B")
        )

        let context = await preserver.context(for: "op-shared")
        XCTAssertEqual(context?.key, "key-of-B", "B ne doit jamais hériter de la clé de A")
    }
}
