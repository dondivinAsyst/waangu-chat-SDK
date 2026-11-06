//
//  TenantOwnerTests.swift
//  FeatureChatTests
//
//  Plan SDK, étape 1.4 / 2.9 — le repère de propriétaire de la base inclut le locataire.
//
//  Le serveur (réponse du 2026-11-06) : `appUserId` est l'utilisateur global, mais ce qu'il voit
//  dépend du locataire, de l'organisation et des appartenances. Le même identifiant dans un
//  autre locataire ne doit donc pas voir les conversations du précédent.
//

import XCTest
@testable import WaanguFeatureChat

final class TenantOwnerTests: XCTestCase {

    typealias D = ChatFeature.DatabaseOwnerDecision

    private func decide(_ stored: String?, tenant: String, env: String = "api.prod") -> D {
        ChatFeature.databaseOwnerDecision(stored: stored, loginUserId: "A", environment: env, tenant: tenant)
    }

    private func freshDefaults() -> UserDefaults {
        let suite = "TenantOwnerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        return defaults
    }

    private actor Purges {
        private(set) var count = 0
        func record() { count += 1 }
    }

    // MARK: Décision

    func test_sameTenant_keepsEverything() {
        XCTAssertEqual(decide("A|api.prod|t1", tenant: "t1"), D.keep)
    }

    func test_anotherTenant_purges() {
        XCTAssertEqual(decide("A|api.prod|t1", tenant: "t2"), D.purgeThenAdopt)
    }

    /// Un repère d'avant le locataire garde ses données et reçoit le locataire courant.
    func test_aMarkerWithoutATenant_keepsItsData_andLearnsTheTenant() {
        XCTAssertEqual(decide("A|api.prod", tenant: "t1"), D.adopt)
    }

    /// La réponse de connexion n'a pas de locataire : rien n'a changé que nous puissions affirmer.
    func test_anUnknownTenantNow_changesNothing() {
        XCTAssertEqual(decide("A|api.prod|t1", tenant: ""), D.keep)
        XCTAssertEqual(decide("A|api.prod", tenant: ""), D.keep)
    }

    func test_anotherAccount_orServer_stillPurgesWhateverTheTenant() {
        XCTAssertEqual(ChatFeature.databaseOwnerDecision(stored: "B|api.prod|t1", loginUserId: "A",
                                                         environment: "api.prod", tenant: "t1"), D.purgeThenAdopt)
        XCTAssertEqual(decide("A|api.staging|t1", tenant: "t1"), D.purgeThenAdopt)
    }

    /// Un serveur inconnu ne compare rien, comme avant : le locataire n'y change rien.
    func test_withoutAnEnvironment_nothingIsCompared() {
        XCTAssertEqual(decide("A|api.prod|t1", tenant: "t2", env: ""), D.keep)
    }

    // MARK: Repère enregistré

    func test_theMarkerIsUserServerTenant() async {
        let defaults = freshDefaults()
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "t1",
                                                 defaults: defaults) { await purges.record() }

        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod|t1")
        let count = await purges.count
        XCTAssertEqual(count, 0, "premier lancement : rien à effacer")
    }

    func test_aTenantChange_purgesOnce_andRecordsTheNewTenant() async {
        let defaults = freshDefaults()
        defaults.set("A|api.prod|t1", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "t2",
                                                 defaults: defaults) { await purges.record() }
        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "t2",
                                                 defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 1, "effacé au changement, pas à chaque connexion")
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod|t2")
    }

    func test_anExistingInstall_learnsTheTenantWithoutLosingData() async {
        let defaults = freshDefaults()
        defaults.set("A|api.prod", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "t1",
                                                 defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod|t1")
    }

    func test_anUnknownTenant_doesNotRewriteTheMarker() async {
        let defaults = freshDefaults()
        defaults.set("A|api.prod|t1", forKey: ChatFeature.databaseOwnerKey)
        let purges = Purges()

        await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "",
                                                 defaults: defaults) { await purges.record() }

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod|t1")
    }

    /// Le séparateur ne peut pas être dans le locataire : relu tronqué, il effacerait à chaque connexion.
    func test_aTenantContainingTheSeparator_doesNotPurgeOnEveryLogin() async {
        let defaults = freshDefaults()
        let purges = Purges()

        for _ in 0..<3 {
            await ChatFeature.reconcileDatabaseOwner(loginUserId: "A", environment: "api.prod", tenant: "org|west",
                                                     defaults: defaults) { await purges.record() }
        }

        let count = await purges.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(defaults.string(forKey: ChatFeature.databaseOwnerKey), "A|api.prod|org_west")
    }

    // MARK: Ouverture de session complète

    func test_theLoginHandler_purgesBeforeRestoringFinance_whenTheTenantChanged() async {
        let defaults = freshDefaults()
        defaults.set("A|api.prod|t1", forKey: ChatFeature.databaseOwnerKey)
        let order = Order()

        await ChatFeature.handleChatLogin(
            userId: "A", environment: "api.prod", tenant: "t2", defaults: defaults,
            purgeConversations: { await order.add("purge") },
            restoreFinance: { await order.add("restore") })

        let names = await order.names
        XCTAssertEqual(names, ["purge", "restore"])
    }

    private actor Order {
        private(set) var names: [String] = []
        func add(_ name: String) { names.append(name) }
    }
}
