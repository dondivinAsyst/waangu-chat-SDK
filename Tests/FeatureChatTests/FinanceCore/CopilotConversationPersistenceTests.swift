//
//  CopilotConversationPersistenceTests.swift
//  FeatureChatTests
//
//  La conversation Waangu Copilot, conservée sur l'appareil comme une conversation.
//

import XCTest
import WaanguCoreKit
import WaanguStorageKit
@testable import WaanguFeatureChat

@MainActor
final class CopilotConversationPersistenceTests: XCTestCase {

    // MARK: - Doublures

    private struct PassthroughCrypto: FieldEncryptionServiceProtocol {
        func encrypt(_ value: String) -> String { value }
        func decrypt(_ value: String) -> String { value }
        func encryptOptional(_ value: String?) -> String? { value }
        func decryptOptional(_ value: String?) -> String? { value }
        func encryptData(_ data: Data) -> Data { data }
        func decryptData(_ data: Data) -> Data { data }
    }

    /// Une conversation en mémoire : ce que le modèle écrit, dans l'ordre.
    private actor MemoryStore: CopilotConversationStoring {
        private(set) var id = "copilot_1"
        private(set) var rows: [(id: String, payload: Data, preview: String?)] = []

        func conversationID() async throws -> String { id }
        func messages(in conversationID: String) async throws -> [Data] { rows.map(\.payload) }
        func save(_ payload: Data, messageID: String, preview: String?, to conversationID: String) async throws {
            if let index = rows.firstIndex(where: { $0.id == messageID }) {
                rows[index].payload = payload
            } else {
                rows.append((messageID, payload, preview))
            }
        }
        func delete(_ conversationID: String) async throws { rows = []; id = "copilot_2" }

        func stored() -> [CopilotConversationViewModel.StoredMessage] {
            rows.compactMap { try? JSONDecoder().decode(CopilotConversationViewModel.StoredMessage.self, from: $0.payload) }
        }
    }

    /// Pas d'outil Copilot ; le dossier personnel du serveur.
    private actor ToollessCatalog: ChatFinanceCatalogProviding {
        func entries(for context: ChatFinanceContext) async -> [FinanceCatalogEntry] { [] }
        func invalidate() async {}
        func copilotTools() async -> Result<[FinanceCopilotTool], FinanceError> { .success([]) }
        func personalFolder() async -> PersonalFinanceFolder? { PersonalFinanceFolder(conversationID: "self_1") }
    }

    private static func model(_ store: MemoryStore, services: FinanceCoreLiveServices,
                              kinds: [FinanceEntryKind] = [.sendMoney]) -> CopilotConversationViewModel {
        CopilotConversationViewModel(
            surface: CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                             contacts: [CopilotTestSurface.contact("Jean Kabura", phone: "+25779000001")]),
            host: nil, hubKinds: kinds, conversationStore: store)
    }

    private static func quoteID(in model: CopilotConversationViewModel) -> UUID? {
        model.messages.reversed().first { if case .quote = $0 { return true }; return false }?.id
    }

    /// Bénéficiaire, montant : le devis est à l'écran.
    private func quoteToJean(_ model: CopilotConversationViewModel) async throws {
        await model.load()
        await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "action-SEND_MONEY" }))
        await model.pick(try XCTUnwrap(model.recipientChoices.first))
        await model.submit("1 000")
        await model.flushPersistence()
    }

    // MARK: - Le modèle

    /// Rouverte, la conversation reprend — et un devis d'hier ne se confirme plus.
    func test_reopenedConversation_restoresTheThread_withTheQuoteClosed() async throws {
        let store = MemoryStore()
        let (services, server) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let first = Self.model(store, services: services)
        try await quoteToJean(first)
        let count = first.messages.count

        let reopened = Self.model(store, services: services)
        await reopened.load()

        XCTAssertEqual(reopened.messages.count, count)
        XCTAssertEqual(reopened.restoredCount, count)
        let quoteID = try XCTUnwrap(Self.quoteID(in: reopened))
        XCTAssertTrue(reopened.messages.contains { if case .quote(quoteID, let card) = $0 { return card.state == .closed }; return false })

        await reopened.confirm(quoteID)
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") }, "Un devis restauré ne part jamais")
    }

    /// Soumise, l'opération garde sa référence : son statut se relit au serveur.
    func test_submittedOperation_keepsItsReference() async throws {
        let store = MemoryStore()
        let (services, _) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let first = Self.model(store, services: services)
        try await quoteToJean(first)
        await first.confirm(try XCTUnwrap(Self.quoteID(in: first)))
        await first.flushPersistence()

        let reopened = Self.model(store, services: services)
        await reopened.load()

        XCTAssertTrue(reopened.messages.contains { if case .outcome(_, let ref) = $0 { return ref.id == "fco_9c2e" }; return false })
    }

    /// Hors d'un fil, le prepare porte le dossier personnel — jamais l'identifiant
    /// de la conversation Copilot, que Chat Core ne connaît pas.
    func test_copilotConversationID_isNeverSentToChatCore() async throws {
        let store = MemoryStore()
        let (services, server) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        try await quoteToJean(Self.model(store, services: services))

        let calls = await server.calls
        XCTAssertFalse(calls.contains { call in call.body.values.contains { ($0 as? String) == "copilot_1" } })
        let prepare = try XCTUnwrap(calls.first { $0.route.hasSuffix("/send-money/prepare") })
        XCTAssertEqual(prepare.body["conversationId"] as? String, "self_1")
    }

    /// La caméra qui lit un code se réécrit à sa place : « lu », pas « fermé ».
    func test_scanner_isStoredClosed_thenScanned() async throws {
        let store = MemoryStore()
        let (services, _) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let model = Self.model(store, services: services, kinds: [.qrPay])
        await model.load()
        await model.choose(try XCTUnwrap(model.suggestions.first))
        await model.flushPersistence()
        var stored = await store.stored()
        XCTAssertTrue(stored.contains { if case .scanner(_, false) = $0 { return true }; return false })

        let scannerID = try XCTUnwrap(model.messages.first { if case .scanner(_, .active) = $0 { return true }; return false }?.id)
        await model.scanned(scannerID, payload: "waangu:qr:v1:abc")
        await model.flushPersistence()

        stored = await store.stored()
        XCTAssertTrue(stored.contains { if case .scanner(scannerID, true) = $0 { return true }; return false })
        // Une seule ligne pour ce lecteur. (Le devis échoue ici : un nouveau lecteur
        // s'ouvre, et c'est une autre ligne.)
        XCTAssertEqual(stored.filter { if case .scanner(scannerID, _) = $0 { return true }; return false }.count, 1)
    }

    /// Ouverte depuis l'accueil des paiements d'un fil : la **même** conversation —
    /// l'historique reprend, ce qui s'y dit s'y garde — et le lien au fil reste.
    func test_openedInAChat_usesTheSameConversation_andKeepsThePeerFirst() async throws {
        let store = MemoryStore()
        let (services, _) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        try await quoteToJean(Self.model(store, services: services))
        let earlier = await store.stored().count

        let inChat = CopilotConversationViewModel(
            surface: CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                             contacts: [CopilotTestSurface.contact("Jean Kabura", phone: "+25779000001")]),
            host: CopilotConversationHost(conversationID: "conv_1", peer: .phoneNumber("+25779000009"),
                                          peerName: "Ali", publish: { _, _ in true }),
            hubKinds: [.sendMoney], conversationStore: store)
        await inChat.load()
        XCTAssertEqual(inChat.restoredCount, earlier, "L'historique de la liste reprend dans le fil")

        await inChat.choose(try XCTUnwrap(inChat.suggestions.first { $0.id == "action-SEND_MONEY" }))
        await inChat.flushPersistence()

        XCTAssertEqual(inChat.recipientChoices.first?.id, "peer", "L'interlocuteur du fil, proposé d'abord")
        let now = await store.stored().count
        XCTAssertGreaterThan(now, earlier, "Ce qui se dit dans le fil s'ajoute à la même conversation")
        let id = await store.id
        XCTAssertEqual(inChat.storedConversationID, id)
    }

    // MARK: - Issue inconnue (Phase 9) : jamais un second execute

    /// L'execute part, puis `CF_017` : issue incertaine. Copilot le dit sans parler
    /// d'échec, garde la référence, et rien ne peut renvoyer l'envoi.
    private func confirmWithUnknownOutcome(_ store: MemoryStore) async throws
        -> (CopilotConversationViewModel, FinanceCoreLiveServices, ScriptedChatCoreAPIClient) {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/send-money/execute"] = FinanceCoreJSON.error("CF_017")
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let model = Self.model(store, services: services)
        try await quoteToJean(model)
        await model.confirm(try XCTUnwrap(Self.quoteID(in: model)))
        await model.flushPersistence()
        return (model, services, server)
    }

    func test_unknownOutcome_isNeverAnError_andNeverRetried() async throws {
        let store = MemoryStore()
        let (model, _, server) = try await confirmWithUnknownOutcome(store)
        let quoteID = try XCTUnwrap(Self.quoteID(in: model))

        XCTAssertTrue(model.messages.contains { if case .notice(_, FinanceStrings.errorMessage(.timeoutUnknown)) = $0 { return true }; return false },
                      "« Nous vérifions… Ne la relancez pas » — jamais « échoué »")
        XCTAssertTrue(model.messages.contains { if case .outcome(_, let ref) = $0 { return ref.id == "fco_9c2e" }; return false },
                      "La référence reste à l'écran : c'est elle qu'on revérifie")
        XCTAssertFalse(model.messages.contains { if case .question(_, FinanceStrings.copilotSubmitted) = $0 { return true }; return false },
                       "Jamais « envoyé » en cas de doute")

        // Le devis est fermé : confirmer encore ne renvoie rien.
        await model.confirm(quoteID)
        let executes = await server.calls.filter { $0.route.hasSuffix("/send-money/execute") }
        XCTAssertEqual(executes.count, 1)
    }

    /// Après un redémarrage : la conversation rouverte garde la référence en doute
    /// (dont le statut se relit au serveur), et aucun devis n'est confirmable.
    func test_unknownOutcome_survivesARestart_withoutAnyResend() async throws {
        let store = MemoryStore()
        let (_, services, server) = try await confirmWithUnknownOutcome(store)

        let reopened = Self.model(store, services: services)
        await reopened.load()

        XCTAssertTrue(reopened.messages.contains { if case .outcome(_, let ref) = $0 { return ref.id == "fco_9c2e" }; return false })
        let quoteID = try XCTUnwrap(Self.quoteID(in: reopened))
        await reopened.confirm(quoteID)
        let executes = await server.calls.filter { $0.route.hasSuffix("/send-money/execute") }
        XCTAssertEqual(executes.count, 1, "Un doute ne se résout jamais par un second execute")
    }

    // MARK: - Signaler un problème (litige)

    private actor FakeDisputes: DisputeFiling {
        private(set) var drafts: [DisputeDraft] = []
        /// La taxonomie que rend le serveur ; `nil` : illisible.
        var taxonomy: [String]? = ["WRONG_BENEFICIARY", "QR_FRAUD", "OTHER"]
        func setTaxonomy(_ value: [String]?) { taxonomy = value }
        func categories() async -> Result<[String], FinanceError> {
            taxonomy.map { .success($0) } ?? .failure(.networkUnavailable)
        }
        func file(_ draft: DisputeDraft, idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError> {
            drafts.append(draft)
            return .success(FinanceFixtures.reference(id: "dsp_1"))
        }
        func allowedEvidence(for reason: DisputeReason) async -> Result<[EvidenceKind], FinanceError> { .success([.text]) }
    }

    private func reportingModel(_ disputes: FakeDisputes, withOperation: Bool,
                                allowedActions: [String]? = ["OPEN_DISPUTE"],
                                status: PaymentStatus = .processing,
                                extraRoutes: [String: String] = [:],
                                server: UnsafeMutablePointer<ScriptedChatCoreAPIClient?>? = nil) async throws -> CopilotConversationViewModel {
        var routes = FinanceSendMoneyTests.routes()
        routes.merge(extraRoutes) { _, new in new }
        let (services, scripted) = FinanceSendMoneyTests.make(routes)
        server?.pointee = scripted
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                              contacts: [CopilotTestSurface.contact("Jean Kabura", phone: "+25779000001")],
                                              disputes: disputes,
                                              // Le statut observé que le litige emporte.
                                              objectReader: FakeFinancialObjects(served: FinancialCardPayload(
                                                reference: FinanceFixtures.reference(id: "fco_9c2e"),
                                                status: status, amount: 1000, currency: "BIF",
                                                allowedActions: allowedActions)))
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [.sendMoney])
        await model.load()
        if withOperation {
            await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "action-SEND_MONEY" }))
            await model.pick(try XCTUnwrap(model.recipientChoices.first))
            await model.submit("1 000")
            await model.confirm(try XCTUnwrap(Self.quoteID(in: model)))
        }
        return model
    }

    /// Opération à signaler, motif, description, consentement : le litige part une fois.
    func test_reportProblem_filesTheDisputeInTheConversation() async throws {
        let disputes = FakeDisputes()
        let model = try await reportingModel(disputes, withOperation: true)

        await model.choose(.reportProblem)
        XCTAssertEqual(model.step, .choice, "Une seule opération : la catégorie est demandée aussitôt")
        XCTAssertEqual(model.options.map(\.id), ["WRONG_BENEFICIARY", "QR_FRAUD", "OTHER"],
                       "Exactement la taxonomie du serveur, rien d'autre")
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "WRONG_BENEFICIARY" }))
        XCTAssertEqual(model.step, .text)
        await model.submit("Mauvais destinataire")
        XCTAssertEqual(model.step, .choice, "Le consentement se demande, il ne se présume pas")
        let draftsBeforeConsent = await disputes.drafts
        XCTAssertTrue(draftsBeforeConsent.isEmpty)
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "agree" }))

        let drafts = await disputes.drafts
        XCTAssertEqual(drafts.count, 1)
        XCTAssertEqual(drafts.first?.category, "WRONG_BENEFICIARY")
        XCTAssertEqual(drafts.first?.conversationID, "self_1", "Jamais vide : le dossier personnel hors conversation")
        XCTAssertNil(drafts.first?.reason)
        XCTAssertEqual(drafts.first?.description, "Mauvais destinataire")
        XCTAssertEqual(drafts.first?.sharingConsent, true)
        XCTAssertEqual(drafts.first?.reference.id, "fco_9c2e")
        XCTAssertTrue(model.messages.contains { if case .outcome(_, let ref) = $0 { return ref.id == "dsp_1" }; return false })
    }

    /// Le lien sous la carte : l'opération est déjà choisie, le motif vient aussitôt.
    func test_reportProblemFromACard_asksTheReasonDirectly() async throws {
        let disputes = FakeDisputes()
        let model = try await reportingModel(disputes, withOperation: true)
        let reference = try XCTUnwrap(model.messages.compactMap { message -> FinancialReference? in
            if case .outcome(_, let ref) = message { return ref }; return nil }.first)

        await model.reportProblem(on: reference)

        XCTAssertEqual(model.step, .choice)
        XCTAssertEqual(model.options.count, 3, "La taxonomie du serveur")
        let drafts = await disputes.drafts
        XCTAssertTrue(drafts.isEmpty, "Rien ne part avant le consentement")
    }

    /// Le serveur ne liste pas `OPEN_DISPUTE` sur la carte : rien à signaler.
    func test_reportProblem_isOfferedOnlyWhereTheServerAllows() async throws {
        // La règle du serveur, sans le contournement Debug.
        DisputeEligibility.bypassesServerAction = false
        defer { DisputeEligibility.bypassesServerAction = true }
        let disputes = FakeDisputes()
        let model = try await reportingModel(disputes, withOperation: true, allowedActions: ["WAIT", "ASK_COPILOT"])

        await model.choose(.reportProblem)

        XCTAssertTrue(model.messages.contains { if case .notice(_, FinanceStrings.copilotDisputeNoOperation) = $0 { return true }; return false })
        XCTAssertEqual(model.step, .free)
        let drafts = await disputes.drafts
        XCTAssertTrue(drafts.isEmpty)
    }

    /// Debug : le dev ne termine aucun paiement, l'option est offerte sans l'action serveur.
    func test_reportProblem_inDebug_isOfferedWithoutTheServerAction() async throws {
        let model = try await reportingModel(FakeDisputes(), withOperation: true, allowedActions: ["WAIT", "ASK_COPILOT"])

        await model.choose(.reportProblem)

        XCTAssertEqual(model.step, .choice, "La catégorie est demandée")
    }

    /// Taxonomie illisible : aucune catégorie n'est devinée, rien ne part.
    func test_reportProblem_withoutTheTaxonomy_guessesNothing() async throws {
        let disputes = FakeDisputes()
        await disputes.setTaxonomy(nil)
        let model = try await reportingModel(disputes, withOperation: true)

        await model.choose(.reportProblem)

        XCTAssertTrue(model.options.isEmpty)
        XCTAssertEqual(model.step, .free)
        XCTAssertTrue(model.messages.contains { if case .notice = $0 { return true }; return false })
        let drafts = await disputes.drafts
        XCTAssertTrue(drafts.isEmpty)
    }

    func test_reportProblem_declinedConsent_sendsNothing() async throws {
        let disputes = FakeDisputes()
        let model = try await reportingModel(disputes, withOperation: true)

        await model.choose(.reportProblem)
        await model.choose(try XCTUnwrap(model.options.first))
        await model.submit("Texte")
        await model.choose(try XCTUnwrap(model.options.first { $0.id != "agree" }))

        let drafts = await disputes.drafts
        XCTAssertTrue(drafts.isEmpty)
        XCTAssertEqual(model.step, .free)
    }

    /// Rien n'a été fait dans cette conversation : rien à contester.
    func test_reportProblem_withoutAnOperation_saysSo() async throws {
        let model = try await reportingModel(FakeDisputes(), withOperation: false)

        await model.choose(.reportProblem)

        XCTAssertTrue(model.messages.contains { if case .notice(_, FinanceStrings.copilotDisputeNoOperation) = $0 { return true }; return false })
        XCTAssertEqual(model.step, .free)
    }

    // MARK: - Suivre un litige : ses propres routes, jamais `/objects/`

    /// Le dossier et sa frise, tels que le serveur de dev les rend.
    func test_followDispute_readsTheDisputeRoutes_notTheObjects() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/disputes/dsp_1"] = FinanceCoreJSON.wrap(#"""
        { "disputeId": "dsp_1", "conversationId": "conv_1", "supportConversationId": "fin-sup-1",
          "financialIntentRef": "fco_9c2e", "clientUserId": "usr_1", "category": "UNRECOGNIZED_PAYMENT",
          "priority": "HIGH", "status": "OPEN", "assigneeId": null, "teamId": null,
          "firstResponseDueAt": "2026-10-19T21:04:33.006232Z", "resolveDueAt": "2026-10-20T17:04:33.006232Z",
          "createdAt": "2026-10-19T17:04:33.006232Z", "updatedAt": "2026-10-19T17:04:33.006232Z",
          "closedAt": null, "closedBy": null, "closeReason": null, "evidence": [], "shareLog": [] }
        """#)
        routes["GET /chat-core/financial/disputes/dsp_1/timeline"] = FinanceCoreJSON.wrap(#"""
        [ { "step": "FCO_CREATED", "value": "2026-10-19T17:03:55Z" }, { "step": "SUPPORT_CASE", "value": "dsp_1" } ]
        """#)
        let (services, server) = FinanceSendMoneyTests.make(routes)

        let snapshot = try await services.disputes.follow(disputeID: "dsp_1").get()

        XCTAssertEqual(snapshot.status, "OPEN")
        XCTAssertEqual(snapshot.category, "UNRECOGNIZED_PAYMENT")
        XCTAssertNotNil(snapshot.firstResponseDueAt)
        XCTAssertNil(snapshot.closedAt)
        XCTAssertEqual(snapshot.timeline.map(\.step), ["FCO_CREATED", "SUPPORT_CASE"])
        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.contains("/objects/") }, "Un litige n'est pas une intention financière")
    }

    /// La frise manquante n'empêche pas de montrer le dossier.
    func test_followDispute_withoutATimeline_stillShowsTheCase() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/disputes/dsp_1"] = FinanceCoreJSON.wrap(
            #"{ "disputeId": "dsp_1", "status": "CLOSED", "closedAt": "2026-10-20T10:00:00Z" }"#)
        let (services, _) = FinanceSendMoneyTests.make(routes)

        let snapshot = try await services.disputes.follow(disputeID: "dsp_1").get()

        XCTAssertEqual(snapshot.status, "CLOSED")
        XCTAssertNotNil(snapshot.closedAt)
        XCTAssertTrue(snapshot.timeline.isEmpty)
    }

    /// La catégorie choisie part telle quelle ; hors taxonomie, rien ne part.
    func test_filing_sendsTheChosenServerCategory_asIs() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/financial/disputes/taxonomy"] = FinanceCoreJSON.wrap(#"["QR_FRAUD","OTHER"]"#)
        routes["POST /chat-core/financial/disputes"] = FinanceCoreJSON.wrap(#"{ "disputeId": "dsp_1", "status": "OPEN" }"#)
        let (services, server) = FinanceSendMoneyTests.make(routes)
        func draft(_ category: String) -> DisputeDraft {
            DisputeDraft(reference: FinanceFixtures.reference(id: "fco_9c2e"), description: "",
                         correlationID: FinanceFixtures.reference(id: "fco_9c2e").correlationID,
                         observedStatus: .processing, sharingConsent: true, category: category)
        }
        let key = IdempotencyContext.new(deviceID: "dev_1")

        _ = try await services.disputes.file(draft("QR_FRAUD"), idempotency: key).get()
        let refused = await services.disputes.file(draft("NOT_A_CATEGORY"), idempotency: key)

        let opens = await server.calls.filter { $0.route == "POST /chat-core/financial/disputes" }
        XCTAssertEqual(opens.count, 1)
        XCTAssertEqual(opens.first?.body["category"] as? String, "QR_FRAUD")
        XCTAssertNil(opens.first?.body["priority"])
        guard case .failure(.validation) = refused else { return XCTFail("\(refused)") }
    }

    // MARK: - Rembourser, extourne (Phase 10)

    private static let refundPrepare = FinanceCoreJSON.wrap(#"""
    { "financialIntentRef": "fco_ref", "conversationId": "self_1", "status": "READY_FOR_CONFIRMATION",
      "processRequired": false, "amountMinor": 500, "currency": "BIF", "quoteId": "q_ref", "feeMinor": 0,
      "totalMinor": 500, "quoteExpiresAt": "2099-09-09T12:02:00Z", "objectVersion": "v1",
      "confirmation": { "confirmationId": "cf_ref", "expiresAt": "2099-09-09T12:02:00Z" },
      "executionPermitId": "perm_ref" }
    """#)

    func test_refundAndReversal_routesFollowTheGuide() {
        XCTAssertEqual(QuotedOperation.refund.prepareRoute, "/financial/refund", "Pas de /prepare")
        XCTAssertEqual(QuotedOperation.refund.executeRoute, "/financial/send-money/execute", "Pas de /refund/execute")
        XCTAssertEqual(QuotedOperation.refund.objectType, .refund)
        XCTAssertEqual(ChatFinanceEndpoints.requestReversal(
            CancelIntentRequest(financialIntentRef: "fco_1", conversationId: nil, reason: "x"), CorrelationId()).path,
                       "/chat-core/financial/reversal/request")
    }

    /// `POST /refund` avec l'opération, le montant choisi et l'appareil ; Face ID ; puis
    /// l'execute de Send Money — jamais un `/refund/execute`.
    func test_refund_isQuotedThenExecutedLikeASend() async throws {
        var server: ScriptedChatCoreAPIClient?
        let model = try await reportingModel(FakeDisputes(), withOperation: true, status: .completed,
                                             extraRoutes: ["POST /chat-core/financial/refund": Self.refundPrepare],
                                             server: &server)

        await model.choose(.refund)
        XCTAssertEqual(model.step, .amount, "Une seule opération : le montant est demandé aussitôt")
        XCTAssertEqual(model.options.map(\.id), ["full"])
        await model.submit("500")
        let quote = try XCTUnwrap(model.messages.reversed().first { if case .quote = $0 { return true }; return false })
        guard case .quote(let quoteID, let card) = quote else { return XCTFail("devis attendu") }
        XCTAssertEqual(card.titleOverride, FinanceStrings.copilotRefundTitle)
        let scripted = try XCTUnwrap(server)
        let afterPrepare = await scripted.calls
        let prepare = try XCTUnwrap(afterPrepare.first { $0.route == "POST /chat-core/financial/refund" })
        XCTAssertEqual(prepare.body["originalIntentRef"] as? String, "fco_9c2e")
        XCTAssertEqual(prepare.body["amountMinor"] as? Int64, 500)
        XCTAssertFalse(afterPrepare.filter { $0.route.hasSuffix("/send-money/execute") }.count > 1, "Rien ne part avant Confirmer")

        await model.confirm(quoteID)
        let allCalls = await scripted.calls
        let executes = allCalls.filter { $0.route.hasSuffix("/send-money/execute") }
        XCTAssertEqual(executes.count, 2, "L'envoi d'origine, puis le remboursement — sur la route de Send Money")
        XCTAssertFalse(allCalls.contains { $0.route.contains("/refund/execute") })
    }

    /// Le serveur ne dit pas `COMPLETED` : ni remboursement ni extourne.
    func test_refundAndReversal_areOfferedOnlyWhereTheServerAllows() async throws {
        // La règle du serveur, sans le contournement Debug.
        ReversalEligibility.bypassesCompletedStatus = false
        defer { ReversalEligibility.bypassesCompletedStatus = true }
        let model = try await reportingModel(FakeDisputes(), withOperation: true, allowedActions: ["WAIT"],
                                             status: .processing)

        await model.choose(.refund)
        await model.choose(.reversal)

        XCTAssertTrue(model.messages.contains { if case .notice(_, FinanceStrings.copilotNothingToRefund) = $0 { return true }; return false })
        XCTAssertTrue(model.messages.contains { if case .notice(_, FinanceStrings.copilotNothingToReverse) = $0 { return true }; return false })
        XCTAssertEqual(model.step, .free)
    }

    /// Debug : le dev ne termine aucun paiement ; remboursement et extourne sont offerts quand même.
    func test_refund_inDebug_isOfferedOnAPendingOperation() async throws {
        let model = try await reportingModel(FakeDisputes(), withOperation: true, allowedActions: ["WAIT"],
                                             status: .processing)

        await model.choose(.refund)

        XCTAssertEqual(model.step, .amount, "Le montant est demandé")
    }

    /// Une demande d'extourne : la raison, la confirmation, puis `POST /reversal/request`.
    func test_reversal_isARequest_financeExecutes() async throws {
        var server: ScriptedChatCoreAPIClient?
        let model = try await reportingModel(
            FakeDisputes(), withOperation: true, status: .completed,
            extraRoutes: ["POST /chat-core/financial/reversal/request": FinanceCoreJSON.wrap(
                #"{ "originalIntentRef": "fco_9c2e", "status": "REVERSAL_REQUESTED", "message": "Finance must execute." }"#)],
            server: &server)

        await model.choose(.reversal)
        XCTAssertEqual(model.step, .text)
        await model.submit("Mauvais montant")
        XCTAssertEqual(model.step, .choice, "La demande se confirme, elle ne part pas seule")
        let scripted = try XCTUnwrap(server)
        let before = await scripted.calls
        XCTAssertFalse(before.contains { $0.route.hasSuffix("/reversal/request") })
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "send" }))

        let after = await scripted.calls
        let request = try XCTUnwrap(after.first { $0.route.hasSuffix("/reversal/request") })
        XCTAssertEqual(request.body["financialIntentRef"] as? String, "fco_9c2e")
        XCTAssertEqual(request.body["reason"] as? String, "Mauvais montant")
        XCTAssertEqual(request.body["conversationId"] as? String, "self_1",
                       "Jamais vide : le dossier personnel hors conversation")
        XCTAssertTrue(model.messages.contains { if case .copilot(_, "Finance must execute.", _) = $0 { return true }; return false },
                      "Le message du serveur, tel quel")
        XCTAssertFalse(model.messages.contains { if case .question(_, FinanceStrings.copilotReversalRequested) = $0 { return true }; return false })
    }

    // MARK: - Partage d'addition dans le fil

    private static let splitCreated = FinanceCoreJSON.wrap(#"""
    {"requestRef":"spl_1","conversationId":"self_1","requesterUserId":"usr_me","status":"OPEN",
     "processRequired":false,"amountMode":"FIXED","currency":"BIF","amountMinor":500,
     "expiresAt":"2099-09-25T14:40:48Z",
     "parties":[{"chatUserId":"usr_x","requestedMinor":500,"paidMinor":0,"remainingMinor":500,
                 "currency":"BIF","status":"PENDING"}],
     "kind":"SPLIT_BILL","nextSafeActions":["PAY_SHARE","WAIT"]}
    """#)

    func test_splitBill_isComposedInTheConversation_thenCreatedOnce() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/split-bill"] = Self.splitCreated
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                              contacts: [CopilotTestSurface.contact("Jean Kabura", phone: "+25779000001")])
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [.splitBill])
        await model.load()

        await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "action-SPLIT_BILL" }))
        XCTAssertEqual(model.step, .text, "Le nom du partage")
        await model.submit("Dîner")
        XCTAssertEqual(model.step, .amount)
        await model.submit("500")
        XCTAssertEqual(model.step, .choice, "Les participants, parmi les contacts")
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "usr_x" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "__done" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == SplitStrategyInput.Kind.equal.rawValue }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "own" }))
        let before = await server.calls
        XCTAssertFalse(before.contains { $0.route == "POST /chat-core/financial/split-bill" }, "Rien ne part avant la confirmation")
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "create" }))

        let calls = await server.calls
        let creates = calls.filter { $0.route == "POST /chat-core/financial/split-bill" }
        XCTAssertEqual(creates.count, 1)
        XCTAssertEqual(creates.first?.body["label"] as? String, "Dîner")
        XCTAssertEqual(creates.first?.body["totalMinor"] as? Int64, 500)
        XCTAssertEqual(creates.first?.body["strategy"] as? String, "EQUAL")
        XCTAssertEqual(creates.first?.body["privacyScope"] as? String, "OWN_SHARE_ONLY")
        XCTAssertEqual(creates.first?.body["conversationId"] as? String, "self_1")
        XCTAssertTrue(model.messages.contains { if case .question(_, FinanceStrings.copilotSplitCreated) = $0 { return true }; return false })
    }

    func test_splitBill_declinedAtTheSummary_createsNothing() async throws {
        let (services, server) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                              contacts: [CopilotTestSurface.contact("Jean Kabura", phone: "+25779000001")])
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [.splitBill])
        await model.load()
        await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "action-SPLIT_BILL" }))
        await model.submit("Dîner")
        await model.submit("500")
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "usr_x" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "__done" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "equal" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "own" }))

        await model.choose(try XCTUnwrap(model.options.first { $0.id == "cancel" }))

        let calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route == "POST /chat-core/financial/split-bill" })
        XCTAssertEqual(model.step, .free)
    }

    // MARK: - Répondre à une demande reçue

    private func answerModel() async -> (CopilotConversationViewModel, ScriptedChatCoreAPIClient) {
        var routes = FinanceRequestResponseTests.answerRoutes()
        routes["GET /chat-core/financial/request-money/req_1"] = FinanceCoreJSON.wrap(
            FinanceRequestMoneyTests.requestView.replacingOccurrences(of: "usr_me", with: "usr_jean"))
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog())
        let model = CopilotConversationViewModel(
            surface: surface,
            host: CopilotConversationHost(
                conversationID: "conv_1", peer: nil, peerName: nil,
                receivedRequests: { [FinanceFixtures.reference(type: .moneyRequest, id: "req_1", version: 0)] },
                publish: { _, _ in true }),
            hubKinds: [])
        await model.load()
        return (model, server)
    }

    func test_answer_pay_quotesTheRequest_andNeverExecutesBeforeConfirmation() async throws {
        let (model, server) = await answerModel()
        await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "answer-request" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "pay" }))

        let calls = await server.calls
        XCTAssertTrue(calls.contains { $0.route == "POST /chat-core/financial/request-money/pay" })
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/execute") })
        XCTAssertTrue(model.messages.contains { if case .quote = $0 { return true }; return false })
    }

    func test_answer_decline_asksFirst_thenDeclines() async throws {
        let (model, server) = await answerModel()
        await model.choose(try XCTUnwrap(model.suggestions.first { $0.id == "answer-request" }))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "decline" }))
        var calls = await server.calls
        XCTAssertFalse(calls.contains { $0.route.hasSuffix("/decline") }, "Refuser se confirme d'abord")

        await model.choose(try XCTUnwrap(model.options.first { $0.id == "decline" }))
        calls = await server.calls
        let decline = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/decline" })
        XCTAssertEqual(decline.body["requestRef"] as? String, "req_1")
        XCTAssertEqual(model.step, .free)
    }

    func test_answer_isOnlyOfferedWhenTheThreadHoldsReceivedRequests() async {
        let (services, _) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog())
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [])
        await model.load()
        XCTAssertFalse(model.suggestions.contains { $0.id == "answer-request" })
    }

    // MARK: - Lien de paiement

    /// Le lien sort de `/request-money/payment-link`, se montre dans la conversation, et son jeton n'est pas gardé.
    func test_paymentLink_isShown_butItsTokenIsNotKept() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/request-money/payment-link"] = FinanceCoreJSON.wrap(
            #"{"token":"lnk_1","nonce":"n_1","requestRef":"req_1","conversationId":"self_1","expiresAt":"2099-09-09T18:00:00Z","executable":false,"consumedAt":null}"#)
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog())
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [])
        await model.load()
        XCTAssertTrue(model.canIssuePaymentLinks)

        await model.issuePaymentLink(for: FinanceFixtures.reference(type: .moneyRequest, id: "req_1", version: 0))

        let calls = await server.calls
        let issue = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/request-money/payment-link" })
        XCTAssertEqual(issue.body["requestRef"] as? String, "req_1")
        XCTAssertEqual(issue.body["conversationId"] as? String, "self_1")
        let shown = model.messages.compactMap { m -> String? in
            if case .paymentLink(_, let url, _) = m { return url }; return nil
        }
        XCTAssertEqual(shown.count, 1)
        XCTAssertTrue(try XCTUnwrap(shown.first).contains("lnk_1"))
        let kept = model.messages.compactMap { CopilotConversationViewModel.StoredMessage($0) }
        let data = try JSONEncoder().encode(kept)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("lnk_1"), "Le jeton ne se conserve pas")
    }

    // MARK: - Annuler une opération

    /// Une carte qui répond à l'annulation (`cancelled`, `requested` ou refus).
    private struct CancellingObjects: FinancialObjectUseCasesProtocol {
        let served: FinancialCardPayload
        let outcome: Result<MoneyRequestCancelOutcome, FinanceError>
        func current(for reference: FinancialReference) async -> FinancialCardPayload? { served }
        func refresh(_ reference: FinancialReference) async -> Result<FinancialCardPayload, FinanceError> { .success(served) }
        func apply(_ payload: FinancialCardPayload) async -> Bool { false }
        func recordSubmission(_ payload: FinancialCardPayload) async {}
        func discardSubmission(_ reference: FinancialReference) async {}
        func reconcilePending() async {}
        func restoreHydrated() async {}
        func pendingReconciliation() async -> [FinancialCardPayload] { [] }
        func purge() async {}
        func cancel(_ reference: FinancialReference, conversationID: String?) async -> Result<MoneyRequestCancelOutcome, FinanceError> { outcome }
    }

    private func cancelModel(outcome: Result<MoneyRequestCancelOutcome, FinanceError>) async throws -> CopilotConversationViewModel {
        let (services, _) = FinanceSendMoneyTests.make(FinanceSendMoneyTests.routes())
        let card = FinancialCardPayload(reference: FinanceFixtures.reference(id: "fco_9c2e"), status: .processing,
                                        amount: 1000, currency: "BIF", allowedActions: ["CANCEL"])
        let surface = CopilotTestSurface.make(services: services, catalog: ToollessCatalog(),
                                              objectReader: CancellingObjects(served: card, outcome: outcome))
        let model = CopilotConversationViewModel(surface: surface, host: nil, hubKinds: [])
        await model.load()
        return model
    }

    /// Le serveur liste `CANCEL` sur un objet pas final : le lien est offert ; sinon, non.
    func test_cancel_isOfferedOnlyWhereTheServerAllows() {
        func card(_ actions: [String]?, _ status: PaymentStatus) -> FinancialCardPayload {
            FinancialCardPayload(reference: FinanceFixtures.reference(id: "x"), status: status, amount: 1,
                                 currency: "BIF", allowedActions: actions)
        }
        XCTAssertTrue(CopilotConversationViewModel.allowsCancel(card(["CANCEL"], .processing)))
        XCTAssertTrue(CopilotConversationViewModel.allowsCancel(card(["CANCEL_INTENT"], .pending)))
        XCTAssertFalse(CopilotConversationViewModel.allowsCancel(card(["WAIT"], .processing)))
        XCTAssertFalse(CopilotConversationViewModel.allowsCancel(card(["CANCEL"], .completed)), "Un objet final ne s'annule pas")
        XCTAssertFalse(CopilotConversationViewModel.allowsCancel(card(nil, .processing)))
    }

    /// La confirmation d'abord ; puis la demande, dite « annulée » ou « demandée » selon le serveur.
    func test_cancel_confirms_thenReportsWhatTheServerSaid() async throws {
        let model = try await cancelModel(outcome: .success(.requested))
        let reference = FinanceFixtures.reference(id: "fco_9c2e")

        await model.requestCancel(on: reference)
        XCTAssertEqual(model.step, .choice, "Rien ne part avant la confirmation")
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "cancel" }))

        XCTAssertTrue(model.messages.contains { if case .question(_, FinanceStrings.cancelRequested) = $0 { return true }; return false },
                      "CF_046 : demandé, pas fait")
        XCTAssertFalse(model.messages.contains { if case .question(_, FinanceStrings.cancelDone) = $0 { return true }; return false })
    }

    func test_cancel_declined_sendsNothing() async throws {
        let model = try await cancelModel(outcome: .success(.cancelled))

        await model.requestCancel(on: FinanceFixtures.reference(id: "fco_9c2e"))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "keep" }))

        XCTAssertFalse(model.messages.contains { if case .question(_, FinanceStrings.cancelDone) = $0 { return true }; return false })
        XCTAssertEqual(model.step, .free)
    }

    func test_cancel_refusedByTheServer_showsItsReason() async throws {
        let model = try await cancelModel(outcome: .failure(.forbidden))

        await model.requestCancel(on: FinanceFixtures.reference(id: "fco_9c2e"))
        await model.choose(try XCTUnwrap(model.options.first { $0.id == "cancel" }))

        XCTAssertTrue(model.messages.contains { if case .notice = $0 { return true }; return false })
    }

    // MARK: - Reçu : la carte dans la conversation, et la vérification

    private static let receiptRecord = #"""
    { "receiptRef": "rcpt_1", "financialIntentRef": "fco_9c2e", "conversationId": "conv_1", "sha256": "abc",
      "version": 1, "signedUrl": "https://finance-docs.example/signed/1", "signedUrlExpiresAt": "2099-01-01T00:00:00Z" }
    """#

    /// Le reçu (déjà émis) sert sa référence ; la carte part avec cette référence, dans ce fil.
    func test_receipt_isPostedInTheConversation_withTheServersReference() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/receipts/share"] = FinanceCoreJSON.wrap(Self.receiptRecord)
        routes["POST /chat-core/financial/receipt/share"] = FinanceCoreJSON.wrap("null")
        let (services, server) = FinanceSendMoneyTests.make(routes)

        _ = try await services.receipts.postInConversation(FinanceFixtures.reference(id: "fco_9c2e"),
                                                           conversationID: "conv_1").get()

        let calls = await server.calls
        let card = try XCTUnwrap(calls.first { $0.route == "POST /chat-core/financial/receipt/share" })
        XCTAssertEqual(card.body["receiptRef"] as? String, "rcpt_1")
        XCTAssertEqual(card.body["conversationId"] as? String, "conv_1")
        XCTAssertEqual(card.body["financialIntentRef"] as? String, "fco_9c2e")
    }

    /// Un hash qui ne correspond pas est `CF_045` : la vérification échoue.
    func test_receiptVerify_failsOnAHashMismatch() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["POST /chat-core/financial/receipts/verify"] = FinanceCoreJSON.error("CF_045")
        let (services, server) = FinanceSendMoneyTests.make(routes)

        let result = await services.receipts.verify(receiptID: "rcpt_1", documentBody: "tampered")

        guard case .failure = result else { return XCTFail("CF_045 attendu") }
        let calls = await server.calls
        let verify = try XCTUnwrap(calls.first { $0.route.hasSuffix("/receipts/verify") })
        XCTAssertEqual(verify.body["receiptRef"] as? String, "rcpt_1")
        XCTAssertEqual(verify.body["documentBody"] as? String, "tampered")
    }

    // MARK: - Ce qui ne se garde pas

    func test_withdrawalCode_andFailedAnnouncement_areNeverStored() {
        let code = CopilotConversationViewModel.Message.cashOutCode(id: UUID(), CashOutToken(code: "483920"))
        guard case .notice(_, let text)? = CopilotConversationViewModel.StoredMessage(code) else {
            return XCTFail("Le code est remplacé par un avis")
        }
        XCTAssertFalse(text.contains("483920"))
        XCTAssertEqual(text, FinanceStrings.copilotCashOutCodeNotKept)
        XCTAssertNil(CopilotConversationViewModel.StoredMessage(.announceFailed(id: UUID(), resolved: false)))
    }

    // MARK: - La liste

    func test_copilotRow_opensTheCopilotConversation() {
        var copilot = DiscussionChatItem(lastMessage: Self.placeholder(), conversationId: "copilot_1",
                                         contact: ContactChannel(isBlocked: false, id: "copilot_1", isCopilot: true))
        guard case .copilot(let id) = ChatListNativeView.route(for: copilot) else { return XCTFail("route Copilot attendue") }
        XCTAssertEqual(id, "copilot_1")

        copilot.contact = ContactChannel(phone: "+25779000001", isBlocked: false)
        guard case .chatRoom = ChatListNativeView.route(for: copilot) else { return XCTFail("une conversation ordinaire") }
    }

    private static func placeholder() -> MessageDataItem {
        MessageDataItem(codeMessage: "", senderId: "", groupId: "", typeMessage: .TEXT,
                        message: MessageContent(text: ""), status: .PENDING, createdAt: Date())
    }

    // MARK: - La base réelle

    private static func database() async -> any DatabaseRepositoryProtocol {
        let database = DatabaseAssembly.makeSearchable(
            config: .init(engine: .sqlite, migrationSteps: ChatDatabaseRegistration.migrationSteps))
        await DatabaseAssembly.register(ChatDatabaseRegistration.self, in: database)
        return database
    }

    /// Une conversation ; ses messages dans l'ordre ; un message remplacé à sa
    /// place ; la ligne de la liste qui suit ; supprimée, la suivante est neuve.
    func test_store_keepsOneConversation_inOrder_andDeletesIt() async throws {
        let database = await Self.database()
        let store = GRDBCopilotConversationStore(store: database, fieldCrypto: PassthroughCrypto())

        let id = try await store.conversationID()
        let again = try await store.conversationID()
        XCTAssertEqual(again, id)

        try await store.save(Data("a".utf8), messageID: "m1", preview: "Bonjour", to: id)
        try await store.save(Data("b".utf8), messageID: "m2", preview: nil, to: id)
        try await store.save(Data("a2".utf8), messageID: "m1", preview: "ignored", to: id)
        let stored = try await store.messages(in: id)
        XCTAssertEqual(stored.map { String(decoding: $0, as: UTF8.self) }, ["a2", "b"])

        let rows = try await DiscussionDataSourceFactory.create(store: database, fieldCrypto: PassthroughCrypto())
            .fetchDiscussions()
        let row = try XCTUnwrap(rows.first { $0.conversationId == id })
        XCTAssertTrue(row.contact?.isCopilotChat == true)
        XCTAssertEqual(row.contact?.userName, FinanceStrings.copilotName)
        XCTAssertEqual(row.lastMessage.message.text, "Bonjour")

        try await store.delete(id)
        let remaining = try await store.messages(in: id)
        XCTAssertTrue(remaining.isEmpty)
        let fresh = try await store.conversationID()
        XCTAssertNotEqual(fresh, id)
        try await store.delete(fresh)
    }
}
