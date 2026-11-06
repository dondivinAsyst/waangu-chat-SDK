//
//  FinanceObjectCardTests.swift
//  FeatureChatTests
//
//  Phase 2 — carte FCO, requery et pointeur MQTT (§7, §9, §11).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceObjectCardTests: XCTestCase {

    private static let ref = "fco_9c2e"

    // MARK: - Carte §7

    func test_contractCard_mapsToAPendingEnvelope() {
        let card = Self.card(status: "PROCESSING", tone: "PENDING", final: false)
        let envelope = FcoCardMapper.envelope(from: card)
        XCTAssertEqual(envelope.id, Self.ref)
        XCTAssertEqual(envelope.status, .processing)
        XCTAssertEqual(envelope.amount, 1000, "BIF : exposant 0")
        XCTAssertEqual(envelope.objectRevision, 2, "`v2-c0ff` → rang 2")
        XCTAssertTrue(envelope.backendSignature.isEmpty, "Aucune signature n'est inventée")
    }

    func test_minorUnits_followTheCurrencyExponent() {
        XCTAssertEqual(FcoCardMapper.amount(minor: 1050, currency: "CAD"), Decimal(string: "10.5"))
        XCTAssertEqual(FcoCardMapper.amount(minor: 18_500, currency: "RWF"), 18_500)
    }

    func test_revision_parsesTheRank_orInventsNothing() {
        XCTAssertEqual(FinanceCoreRevision.parse("v1-a1b2"), 1)
        XCTAssertEqual(FinanceCoreRevision.parse("v12-ff"), 12)
        XCTAssertNil(FinanceCoreRevision.parse("abc"))
        XCTAssertNil(FinanceCoreRevision.parse(nil))
    }

    /// Un `COMPLETED` sans `visualSuccessFinal` n'est pas un succès — §7.
    func test_completedWithoutVisualSuccessFinal_isNotSuccess() {
        XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: "COMPLETED", tone: "PENDING", final: false)),
                       .pendingReconciliation)
        XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: "COMPLETED", tone: "SUCCESS_FINAL", final: true)),
                       .completed)
    }

    /// Le vocabulaire complet du backend Finance — aucun mot connu ne tombe
    /// plus sur « vérification » par défaut.
    func test_everyBackendStatus_isMapped() {
        let expected: [(String, PaymentStatus)] = [
            ("PENDING", .pending),
            ("AUTHORIZATION", .processing),
            ("RISK_CHECKING", .processing),
            ("TO_ORCHESTRATOR", .processing),
            ("SENT_TO_SWITCH", .pendingProvider),
            ("ACCEPTED", .pendingSettlement),
            ("SETTLED", .pendingReconciliation),   // sans visualSuccessFinal
            ("FAILED", .failed),
            ("REVERSED", .reversed),
            ("DISPUTED", .disputed),
            ("EXPIRED", .expired),
            ("RECONCILIATION_REQUIRED", .pendingReconciliation),
            ("COMPLIANCE_HOLD", .complianceHold),
            ("RESERVED", .authorized),
            ("POSTED", .pendingReconciliation),    // sans visualSuccessFinal
            ("REFUNDED", .refunded),
            ("IN_DOUBT", .inDoubt),                // canonique, Harness Bloc 2 §28 (M3)
            ("REJECTED", .denied),
            ("UNKNOWN", .unknown),
        ]
        for (raw, status) in expected {
            XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: raw, tone: "PENDING", final: false)),
                           status, raw)
        }
        // Mots du contrat, toujours lus.
        XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: "AWAITING_INPUT", tone: "PENDING", final: false)),
                       .pending)
        XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: "SOMETHING_NEW", tone: "PENDING", final: false)),
                       .unknown, "Un mot inconnu n'est jamais un succès")
    }

    /// `SETTLED` / `POSTED` ne sont un succès que si Finance l'a déclaré final.
    func test_settledAndPosted_areSuccessOnlyWhenFinal() {
        for raw in ["SETTLED", "POSTED"] {
            XCTAssertEqual(FcoCardMapper.status(of: Self.card(status: raw, tone: "SUCCESS_FINAL", final: true)),
                           .completed, raw)
        }
    }

    // MARK: - De bout en bout : carte → magasin → présentation

    /// Un paiement réglé et déclaré final s'affiche réussi — la coche « Done ».
    func test_settledFinalCard_isPresentedAsSettled() async {
        let presentation = await presentation(afterReading: Self.card(status: "SETTLED", tone: "SUCCESS_FINAL", final: true))
        XCTAssertEqual(presentation, .settled)
    }

    /// `PENDING` s'affiche « en cours », plus « vérification ».
    func test_pendingCard_isInFlight_notVerifying() async {
        let presentation = await presentation(afterReading: Self.card(status: "PENDING", tone: "PENDING", final: false))
        XCTAssertEqual(presentation, .inFlight)
    }

    func test_finalCard_isPresentedAsSettled() async {
        let presentation = await presentation(afterReading: Self.card(status: "COMPLETED", tone: "SUCCESS_FINAL", final: true))
        XCTAssertEqual(presentation, .settled)
    }

    func test_nonFinalCard_isNeverPresentedAsSettled() async {
        let presentation = await presentation(afterReading: Self.card(status: "COMPLETED", tone: "PENDING", final: false))
        XCTAssertNotEqual(presentation, .settled, "Seul `visualSuccessFinal` fait un succès")
    }

    /// Le garde n'accepte pas un succès que Chat Core n'a pas déclaré final.
    func test_guard_acceptsOnlyWhatChatCoreDeclaredFinal() async {
        let finality = FinanceCoreFinality()
        let guardian = ChatCoreConfirmationGuard(finality: finality)
        let confirmation = PaymentConfirmation(
            reference: FinanceFixtures.reference(id: Self.ref, version: 2), amount: 1000, currency: "BIF",
            status: .completed, backendSignature: "", idempotencyKey: "", railProof: nil, currentKnownVersion: nil)

        let before = await guardian.decide(on: confirmation)
        guard case .undetermined = before else { return XCTFail("\(before)") }

        await finality.record(objectID: Self.ref, revision: 2, isFinal: true)
        let after = await guardian.decide(on: confirmation)
        XCTAssertEqual(after, .accepted)
    }

    // MARK: - Doute §9

    func test_inDoubtCard_triggersRequery_thenReRead_neverExecute() async {
        let server = ScriptedChatCoreAPIClient(routes: [
            "GET /chat-core/financial/objects/\(Self.ref)": FinanceCoreJSON.wrap(Self.cardJSON(status: "IN_DOUBT", tone: "PENDING", final: false)),
            "POST /chat-core/financial/intent/requery": FinanceCoreJSON.wrap(#"{ "financialIntentRef": "fco_9c2e", "status": "COMPLETED" }"#),
        ])
        let client = LiveFinanceAPIClient(dataSource: server.dataSource, finality: FinanceCoreFinality(),
                                          capabilitiesProvider: { FinanceCapabilities() })

        _ = try? await client.refresh(FinanceFixtures.reference(id: Self.ref))

        let calls = await server.calls
        XCTAssertEqual(calls.map(\.route), [
            "GET /chat-core/financial/objects/\(Self.ref)",
            "POST /chat-core/financial/intent/requery",
            "GET /chat-core/financial/objects/\(Self.ref)",
        ])
        XCTAssertEqual(calls[0].query["reasonForAccess"], "SELF")
        XCTAssertEqual(calls[1].body["conversationId"] as? String, "conv_1")
        XCTAssertFalse(calls.contains { $0.route.contains("execute") })
    }

    /// Sans prepare vivant, aucun execute ne part : il faut refaire un prepare.
    func test_confirmWithoutPreparedIntent_neverExecutes() async {
        let client = LiveFinanceAPIClient(dataSource: ScriptedChatCoreAPIClient(routes: [:]).dataSource, finality: FinanceCoreFinality(),
                                          capabilitiesProvider: { FinanceCapabilities() })
        do {
            _ = try await client.confirmPaymentIntent(reference: FinanceFixtures.reference(),
                                                      idempotency: FinanceFixtures.idempotency(), stepUp: nil)
            XCTFail("Un execute sans prepare ne doit jamais partir")
        } catch {
            XCTAssertEqual(error as? FinanceError, .executionPermitExpired)
        }
    }

    // MARK: - Pointeur MQTT §11.2

    func test_contractMqttPointer_isRecognised() throws {
        let event = try XCTUnwrap(ChatMqttEventParser.parse(data: Data(Self.mqttPointer.utf8)))
        XCTAssertEqual(event.type, "finance_object_changed")
        XCTAssertEqual(event.referenceId, "fco_9c2e")
        let payload = try XCTUnwrap(event.payload?.rawData)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
        XCTAssertEqual(object["objectType"] as? String, "PAYMENT")
        XCTAssertEqual(object["version"] as? Int, 2)
        XCTAssertNil(object["amountMinor"], "Un montant glissé dans le pointeur n'est jamais repris")
    }

    func test_pointerRecognisedByActionAlone() throws {
        let json = #"{ "payload": { "action": "OBJECT_CHANGED", "refetchPath": "/v1/chat/financial/objects/fco_77" } }"#
        let event = try XCTUnwrap(ChatMqttEventParser.parse(data: Data(json.utf8)))
        XCTAssertEqual(event.referenceId, "fco_77")
    }

    func test_pointerWithoutReference_isIgnored() {
        let json = #"{ "eventType": "conversation.financial.object_changed", "payload": { "action": "OBJECT_CHANGED" } }"#
        XCTAssertNil(ChatMqttEventParser.parse(data: Data(json.utf8)))
    }

    // MARK: - Fixtures

    private func presentation(afterReading card: FcoClientCardDTO) async -> FinancialCardPresentation? {
        let finality = FinanceCoreFinality()
        let server = ScriptedChatCoreAPIClient(routes: [
            "GET /chat-core/financial/objects/\(Self.ref)": FinanceCoreJSON.wrap(
                Self.cardJSON(status: card.publicStatus ?? "", tone: card.visualTone ?? "", final: card.visualSuccessFinal ?? false))
        ])
        let store = FinancialObjectStore()
        let useCases = FinancialObjectUseCases(
            store: store,
            client: LiveFinanceAPIClient(dataSource: server.dataSource, finality: finality, capabilitiesProvider: { FinanceCapabilities() }),
            guardian: ChatCoreConfirmationGuard(finality: finality),
            capabilities: MockFinanceCapabilityProvider(FinanceFixtures.readOnlyCapabilities),
            logger: SilentLogger()
        )
        _ = await useCases.refresh(FinanceFixtures.reference(id: Self.ref, version: 1))
        return await store.current(for: FinanceFixtures.reference(id: Self.ref))?.presentation
    }

    static func card(status: String, tone: String, final: Bool) -> FcoClientCardDTO {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try! decoder.decode(FcoClientCardDTO.self, from: Data(cardJSON(status: status, tone: tone, final: final).utf8))
    }

    static func cardJSON(status: String, tone: String, final: Bool) -> String {
        #"""
        { "objectId": "fco_9c2e", "schemaVersion": "1.4.0", "objectVersion": "v2-c0ff",
          "publicStatus": "\#(status)", "visualTone": "\#(tone)", "visualSuccessFinal": \#(final),
          "intentType": "WALLET_TRANSFER", "operationKind": "SEND_MONEY", "conversationId": "conv_1",
          "amountMinor": 1000, "currency": "BIF", "inquiryStatus": "NOT_STARTED", "quoteStatus": "READY",
          "paymentStatus": "\#(status)", "settlementStatus": "NOT_STARTED", "fulfillmentStatus": "NOT_STARTED",
          "reconciliationStatus": "NOT_STARTED", "deliveryStatus": "NOT_STARTED", "allowedActions": ["WAIT"],
          "financialActionsLocked": false, "securityWarnings": [],
          "accessibility": { "statusAnnouncement": "Paiement en cours", "amountSpeech": "1000 BIF" },
          "updatedAt": "2026-09-09T12:01:02Z" }
        """#
    }

    static let mqttPointer = #"""
    { "eventType": "conversation.financial.object_changed",
      "payload": { "action": "OBJECT_CHANGED", "eventType": "conversation.financial.object_changed",
        "originalEventType": "conversation.financial_intent.confirmed", "eventId": "evt_1", "schemaVersion": "1.0.0",
        "tenantId": "t_1", "subject": { "conversationId": "conv_1", "financialIntentRef": "fco_9c2e" },
        "objectVersion": "v2-c0ff", "correlationId": "corr_1", "occurredAt": "2026-09-09T12:01:00.000Z",
        "serverTime": "2026-09-09T12:01:00.120Z", "refetchPath": "/v1/chat/financial/objects/fco_9c2e",
        "conversationId": "conv_1", "amountMinor": 999999 },
      "conversationId": "conv_1", "muted": false, "suppressNotification": false,
      "timestamp": "2026-09-09T12:01:00.150Z", "processingTimeMs": 12, "version": 1 }
    """#
}
