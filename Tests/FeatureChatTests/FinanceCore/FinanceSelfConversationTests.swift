//
//  FinanceSelfConversationTests.swift
//  FeatureChatTests
//
//  §5.1.1 — dossier personnel et `X-Membership-Epoch`.
//

import XCTest
import WaanguCoreKit
import WaanguNetworkKit
@testable import WaanguFeatureChat

final class FinanceSelfConversationTests: XCTestCase {

    // MARK: - Le dossier

    /// La réponse du contrat, décodée telle quelle.
    func test_selfConversation_readsTheFolder() async throws {
        let client = EpochStubClient(json: """
        { "success": true, "message": "ok", "statusCode": 200,
          "data": { "conversationId": "conv_self_1", "membershipEpoch": 3,
                    "kind": "FINANCIAL_SELF", "title": "Mes factures",
                    "hubConversationType": "SELF" },
          "error": null, "timestamp": "2026-09-09T12:00:00Z" }
        """)

        let folder = try await HTTPChatFinanceDataSource(httpClient: client).selfConversation()

        XCTAssertEqual(folder.conversationId, "conv_self_1")
        XCTAssertEqual(folder.membershipEpoch, 3)
        XCTAssertEqual(folder.hubConversationType, "SELF")
    }

    /// Lire le dossier retient son époque : sans ça, le prepare qui suit
    /// partirait sans `X-Membership-Epoch` et serait refusé par `CF_074`.
    func test_readingTheFolder_remembersItsEpoch() async throws {
        FinanceMembershipEpochs.shared.clear()
        let client = EpochStubClient(json: """
        { "success": true, "statusCode": 200,
          "data": { "conversationId": "conv_self_2", "membershipEpoch": 7 },
          "error": null }
        """)

        _ = try await HTTPChatFinanceDataSource(httpClient: client).selfConversation()

        XCTAssertEqual(FinanceMembershipEpochs.shared.epoch(for: "conv_self_2"), 7)
        FinanceMembershipEpochs.shared.clear()
    }

    /// La route du contrat, en lecture.
    func test_selfConversation_route() {
        XCTAssertEqual(ChatFinanceEndpoints.selfConversation.path,
                       "/chat-core/financial/self-conversation")
        XCTAssertEqual(ChatFinanceEndpoints.selfConversation.method, .get)
    }

    /// Le Hub d'un parcours ouvert hors conversation demande `SELF`, pas
    /// `DIRECT` : c'est ce qui rendait le portefeuille vide depuis les Réglages.
    func test_personalKind_asksTheHubForSELF() {
        XCTAssertEqual(FinanceGovernanceMapper.conversationType(for: .selfChat), "SELF")
        XCTAssertEqual(FinanceGovernanceMapper.conversationType(for: .direct), "DIRECT")
    }

    /// Les quatre parcours sans interlocuteur — le groupe `WALLET` du Hub.
    func test_onlyWalletFlows_usePersonalFolder() {
        for kind: FinanceEntryKind in [.payBill, .topUp, .cashIn, .cashOut] {
            XCTAssertTrue(kind.usesPersonalFolder, kind.rawValue)
        }
        for kind: FinanceEntryKind in [.sendMoney, .requestMoney, .splitBill] {
            XCTAssertFalse(kind.usesPersonalFolder, kind.rawValue)
        }
    }

    // MARK: - L'en-tête

    /// L'époque connue part sur l'écriture qui nomme cette conversation.
    func test_mutation_carriesTheKnownEpoch() {
        FinanceMembershipEpochs.shared.clear()
        FinanceMembershipEpochs.shared.remember(4, for: "conv_9")

        let endpoint = ChatFinanceEndpoints.prepareQuoted(
            .payBill, body: ["conversationId": "conv_9"],
            IdempotencyContext.new(deviceID: "dev_1"))

        XCTAssertEqual(endpoint.headers?["X-Membership-Epoch"], "4")
        FinanceMembershipEpochs.shared.clear()
    }

    /// Époque inconnue ⇒ pas d'en-tête. En inventer une la ferait refuser par
    /// `CF_074` en affirmant un fait qu'on n'a pas.
    func test_unknownEpoch_sendsNoHeader() {
        FinanceMembershipEpochs.shared.clear()

        let endpoint = ChatFinanceEndpoints.prepareQuoted(
            .payBill, body: ["conversationId": "conv_inconnue"],
            IdempotencyContext.new(deviceID: "dev_1"))

        XCTAssertNil(endpoint.headers?["X-Membership-Epoch"])
    }

    /// Une lecture ne porte pas l'époque : elle ne mute rien.
    func test_read_sendsNoEpoch() {
        FinanceMembershipEpochs.shared.clear()
        FinanceMembershipEpochs.shared.remember(2, for: "conv_9")

        XCTAssertNil(ChatFinanceEndpoints.selfConversation.headers?["X-Membership-Epoch"])
        FinanceMembershipEpochs.shared.clear()
    }

    /// Une réponse plus ancienne arrivée après une plus récente ne rétablit pas
    /// une époque dépassée.
    func test_epoch_neverGoesBackwards() {
        FinanceMembershipEpochs.shared.clear()
        FinanceMembershipEpochs.shared.remember(5, for: "conv_x")
        FinanceMembershipEpochs.shared.remember(2, for: "conv_x")

        XCTAssertEqual(FinanceMembershipEpochs.shared.epoch(for: "conv_x"), 5)
        FinanceMembershipEpochs.shared.clear()
    }

    // MARK: - CF_074

    /// Le code est décidé, et décidé comme un **refus** : l'opération n'a pas
    /// eu lieu, l'écran ne doit pas ouvrir la vérification.
    func test_CF074_isARefusal_notAnUnknownOutcome() {
        let code = FinanceCoreErrorCode(rawValue: "CF_074")

        XCTAssertEqual(code.clientAction, .resyncMembership)
        XCTAssertEqual(code.financeError, .conflict)
        XCTAssertFalse(FinancialOutcomeRoute.isFinalityUnknown(code.financeError))
    }

    /// `CF_074` fait oublier ce qu'on croyait savoir : sans ça, l'écriture
    /// suivante rejouerait l'époque que le serveur vient de refuser.
    func test_CF074_forgetsWhatWeKnew() async {
        FinanceMembershipEpochs.shared.clear()
        FinanceMembershipEpochs.shared.remember(1, for: "conv_9")

        let client = EpochStubClient(json: """
        { "success": false, "statusCode": 403, "data": null,
          "error": { "code": "CF_074",
                     "message": "Conversation membership epoch is stale", "details": null } }
        """)
        let resynced = ResyncFlag()
        let source = HTTPChatFinanceDataSource(
            httpClient: client,
            onSessionInvalid: { await resynced.raise(); FinanceMembershipEpochs.shared.clear() })

        _ = try? await source.selfConversation()

        let didResync = await resynced.value
        XCTAssertTrue(didResync, "CF_074 doit déclencher la relecture")
        XCTAssertNil(FinanceMembershipEpochs.shared.epoch(for: "conv_9"))
    }
}

// MARK: - Doublures

private actor ResyncFlag {
    private(set) var value = false
    func raise() { value = true }
}

private final class EpochStubClient: APIClientProtocol, @unchecked Sendable {
    private let json: String

    init(json: String) { self.json = json }

    var isConnected: Bool { get async { true } }

    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}

// MARK: - Refus affiché tel quel

final class FinanceCatalogRefusalTests: XCTestCase {

    /// Le hub qui ne connaît pas `SELF` répond `SYS_001` avec une phrase
    /// précise. Elle doit arriver à l'écran : « service indisponible » ferait
    /// chercher une panne réseau là où le serveur a nommé la cause.
    func test_serverRefusal_isKeptForDisplay_wordForWord() async {
        FinanceErrorExplanations.shared.clear()
        let client = EpochStubClient(json: """
        { "success": false, "statusCode": 0, "data": null,
          "error": { "code": "SYS_001",
                     "message": "Parameter 'conversationType' should be of type ConversationType",
                     "details": null } }
        """)

        let failure = await Self.failure {
            try await HTTPChatFinanceDataSource(httpClient: client).hubActions(conversationType: "SELF")
        }

        guard case .business(let code, _)? = failure else { return XCTFail("\(String(describing: failure))") }
        // Un code hors taxonomie CF reste un refus serveur, jamais un succès.
        XCTAssertEqual(code.rawValue, "SYS_001")
        XCTAssertEqual(FinanceStrings.errorMessage(code.financeError),
                       "Parameter 'conversationType' should be of type ConversationType")
        FinanceErrorExplanations.shared.clear()
    }

    /// Sans message serveur, rien n'est inventé : l'écran garde sa phrase.
    func test_withoutServerMessage_noReasonIsInvented() {
        FinanceErrorExplanations.shared.clear()
        XCTAssertNil(FinanceErrorExplanations.shared.explanation(for: .providerUnavailable))
    }

    private static func failure(_ operation: () async throws -> Any) async -> FinanceCoreError? {
        do { _ = try await operation(); return nil }
        catch let error as FinanceCoreError { return error }
        catch { return nil }
    }
}
