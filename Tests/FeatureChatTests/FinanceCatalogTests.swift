//
//  FinanceCatalogTests.swift
//  FeatureChatTests
//
//  Chapitre 16 — le catalogue décide, jamais le client.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - Doublure

actor MockFinanceCatalog: ChatFinanceCatalogProviding {

    private(set) var receivedContexts: [ChatFinanceContext] = []
    private(set) var invalidateCount = 0
    private var result: [FinanceCatalogEntry]

    init(_ entries: [FinanceCatalogEntry] = []) { self.result = entries }

    func setEntries(_ entries: [FinanceCatalogEntry]) { result = entries }

    func entries(for context: ChatFinanceContext) async -> [FinanceCatalogEntry] {
        receivedContexts.append(context)
        return result
    }

    func invalidate() async { invalidateCount += 1 }
}

private enum CatalogFixtures {

    static func entry(
        kind: FinanceEntryKind = .sendMoney,
        enabled: Bool = true,
        reason: String? = nil,
        expiresAt: Date? = nil
    ) -> FinanceCatalogEntry {
        FinanceCatalogEntry(
            id: kind.rawValue,
            kind: kind,
            titleKey: "finance.entry.\(kind.rawValue)",
            iconName: "arrow.up.circle",
            isEnabled: enabled,
            unavailableReasonKey: reason,
            expiresAt: expiresAt
        )
    }

    static let context = ChatFinanceContext(
        conversationID: "conv-1",
        conversationKind: .direct,
        participantCount: 2
    )
}

// MARK: - Fermé par défaut

final class ClosedFinanceCatalogTests: XCTestCase {

    /// Sans contrat backend, aucune entrée. Le menu s'affiche vide — ce qui est
    /// le comportement juste, et non un écran cassé.
    func test_closedCatalogProposesNothing() async {
        let entries = await ClosedChatFinanceCatalog().entries(for: CatalogFixtures.context)
        XCTAssertTrue(entries.isEmpty)
    }

    /// **Pas une liste d'entrées grisées.** Proposer sept entrées désactivées
    /// ferait croire que le produit existe et qu'il est en panne, alors qu'il
    /// n'est pas encore livré sur ce marché.
    func test_closedCatalogReturnsEmptyNotDisabledEntries() async {
        let entries = await ClosedChatFinanceCatalog().entries(for: CatalogFixtures.context)
        XCTAssertEqual(entries.count, 0)
    }
}

// MARK: - Validité et actionnabilité

final class FinanceCatalogEntryTests: XCTestCase {

    func test_entryWithoutExpiryIsValid() {
        XCTAssertTrue(CatalogFixtures.entry().isValid())
    }

    func test_expiredEntryIsNotValid() {
        let past = Date().addingTimeInterval(-60)
        XCTAssertFalse(CatalogFixtures.entry(expiresAt: past).isValid())
    }

    /// **Le point du chapitre 16.** Une entrée périmée n'est pas actionnable
    /// même marquée `isEnabled` : le catalogue qui l'a autorisée n'est plus
    /// d'actualité, et l'ouvrir proposerait un parcours sous conditions expirées.
    func test_expiredEntryIsNotActionableEvenWhenEnabled() {
        let entry = CatalogFixtures.entry(enabled: true, expiresAt: Date().addingTimeInterval(-1))
        XCTAssertTrue(entry.isEnabled, "le backend l'avait bien autorisée")
        XCTAssertFalse(entry.isActionable(), "mais plus maintenant")
    }

    func test_disabledEntryIsNotActionable() {
        XCTAssertFalse(CatalogFixtures.entry(enabled: false, reason: "kyc.required").isActionable())
    }
}

// MARK: - Contexte

final class FinanceCatalogContextTests: XCTestCase {

    /// Le contexte de conversation doit atteindre le backend : c'est lui qui
    /// permet de proposer des entrées différentes en groupe et en tête-à-tête.
    func test_contextReachesTheCatalog() async {
        let catalog = MockFinanceCatalog()
        let groupContext = ChatFinanceContext(
            conversationID: "conv-9",
            conversationKind: .group,
            participantCount: 7
        )
        _ = await catalog.entries(for: groupContext)

        let received = await catalog.receivedContexts
        XCTAssertEqual(received, [groupContext])
    }

    /// Une nature de conversation inconnue retombe sur `direct`, la plus
    /// restrictive : elle ne débloque aucun parcours marchand ni institutionnel.
    func test_unknownConversationKindFallsBackToDirect() throws {
        let decoded = try JSONDecoder().decode(
            ConversationFinancialKind.self,
            from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertEqual(decoded, .direct)
    }

    /// Une nature d'entrée inconnue fait échouer le décodage plutôt que de se
    /// replier : afficher une entrée dont on ignore la nature ouvrirait un
    /// parcours qu'on ne sait pas rendre.
    func test_unknownEntryKindFailsRatherThanFallingBack() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(FinanceEntryKind.self, from: Data("\"TELEPORT_MONEY\"".utf8))
        )
    }
}
