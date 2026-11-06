//
//  ChatFinanceDataSourceTests.swift
//  FeatureChatTests
//
//  Phase 0 — `ChatFinanceEndpoints` et `HTTPChatFinanceDataSource`, contre les
//  JSON du contrat (INTEGRATION_CHAT_FINANCE.md).
//

import XCTest
import WaanguCoreKit
import WaanguNetworkKit
@testable import WaanguFeatureChat

final class ChatFinanceDataSourceTests: XCTestCase {

    // MARK: - Enveloppe — §0.4

    /// `data` d'un `ResumeState` (§1.6), dans l'enveloppe standard.
    func test_successEnvelope_unwrapsData() async throws {
        let client = StubAPIClient(json: """
        { "success": true, "message": "ok", "statusCode": 200,
          "data": { "userId": "usr_1", "locked": false, "expiresAt": "2026-09-09T12:15:00Z" },
          "error": null, "timestamp": "2026-09-09T12:00:00Z" }
        """)

        let state = try await HTTPChatFinanceDataSource(httpClient: client).sessionResumeState()

        XCTAssertEqual(state.userId, "usr_1")
        XCTAssertEqual(state.locked, false)
        XCTAssertEqual(state.expiresAt, "2026-09-09T12:15:00Z")
    }

    /// L'erreur métier exacte de l'exemple §0.4 : `statusCode` à 0, texte en
    /// anglais — seul `error.code` compte.
    func test_businessErrorEnvelope_yieldsTheCode_notTheText() async {
        let client = StubAPIClient(json: """
        { "success": false, "message": null, "statusCode": 0, "data": null,
          "error": { "code": "CF_029", "message": "Finance quote expired — request a new quote", "details": null },
          "timestamp": "2026-09-09T12:00:01Z" }
        """)

        let failure = await Self.failure { try await HTTPChatFinanceDataSource(httpClient: client).financialObject(ref: "fco_1") }

        guard case .business(let code, let message)? = failure else { return XCTFail("\(String(describing: failure))") }
        XCTAssertEqual(code.rawValue, "CF_029")
        XCTAssertEqual(message, "Finance quote expired — request a new quote", "Le texte serveur est gardé pour l'affichage")
        XCTAssertEqual(code.clientAction, .refreshQuote)
        XCTAssertEqual(code.financeError, .expired)
    }

    /// Un code métier l'emporte même si `success` est incohérent.
    func test_errorCode_winsOverSuccessFlag() {
        let response = ChatCoreAPIResponse<ResumeStateDTO>(
            success: true, message: nil, statusCode: 200, data: nil,
            error: ChatCoreErrorBody(code: "CF_069", message: nil), timestamp: nil)
        guard case .failure(.business(let code, _)) = HTTPChatFinanceDataSource.unwrap(response) else {
            return XCTFail("Un kill-switch ne doit jamais passer pour un succès")
        }
        XCTAssertEqual(code.clientAction, .showUnavailable)
    }

    func test_successWithoutData_isMissingData_notSuccess() {
        let response = ChatCoreAPIResponse<ResumeStateDTO>(
            success: true, message: nil, statusCode: 200, data: nil, error: nil, timestamp: nil)
        guard case .failure(.missingData) = HTTPChatFinanceDataSource.unwrap(response) else {
            return XCTFail("Un succès sans `data` n'est pas un succès")
        }
    }

    /// Une session déclarée périmée est oubliée — la lecture suivante refait l'amorçage.
    func test_staleSessionCode_invalidatesTheSession() async {
        let client = StubAPIClient(json: FinanceCoreJSON.error("CF_066"))
        let invalidated = Flag()
        let dataSource = HTTPChatFinanceDataSource(httpClient: client, onSessionInvalid: { await invalidated.raise() })

        _ = try? await dataSource.financialObject(ref: "fco_1")

        let raised = await invalidated.value
        XCTAssertTrue(raised)
    }

    // MARK: - Codes CF

    /// Chaque code du contrat 1.4.0 a une action déclarée — aucun ne tombe par
    /// défaut dans « indisponible » sans l'avoir décidé.
    func test_everyContractCode_hasAnExplicitClientAction() {
        let undeclared = FinanceCoreErrorCode.contractCodes.filter {
            !FinanceCoreErrorCode.isDeclared($0)
        }
        XCTAssertEqual(FinanceCoreErrorCode.contractCodes.count, 74)
        XCTAssertTrue(undeclared.isEmpty, "Codes sans action : \(undeclared)")
    }

    /// Un code que le serveur émet sans que le contrat le documente est tout de
    /// même décidé — et décidé comme un **refus**, pas comme une issue inconnue.
    ///
    /// Le défaut par défaut (`providerUnavailable`) signifie « le fournisseur a
    /// pu exécuter puis cesser de répondre » : il ouvre l'écran de vérification
    /// et publie une carte. Pour un refus reçu du serveur, c'est faux.
    func test_undocumentedCodes_areDecided_andNeverInDoubt() {
        for raw in FinanceCoreErrorCode.undocumentedCodes + ["CF_074"] {
            let code = FinanceCoreErrorCode(rawValue: raw)
            XCTAssertTrue(FinanceCoreErrorCode.isDeclared(raw), raw)
            XCTAssertFalse(FinancialOutcomeRoute.isFinalityUnknown(code.financeError), raw)
            XCTAssertNotNil(FinanceServerRefusal.decided(code.financeError), raw)
        }
    }

    /// Les codes d'issue incertaine mènent au requery, **jamais** à un nouvel execute.
    func test_inDoubtCodes_leadToRequery_andNeverRetry() {
        for raw in ["CF_017", "CF_024"] {
            let code = FinanceCoreErrorCode(rawValue: raw)
            XCTAssertEqual(code.clientAction, .requery, raw)
            XCTAssertEqual(code.financeError, .timeoutUnknown, raw)
            XCTAssertFalse(code.financeError.isSafeToRetry, raw)
        }
    }

    /// Un code inconnu de cette version n'est ni un succès, ni une invitation à réessayer.
    func test_unknownCode_failsClosed() {
        let code = FinanceCoreErrorCode(rawValue: "CF_999")
        XCTAssertEqual(code.clientAction, .showUnavailable)
        XCTAssertEqual(code.financeError, .providerUnavailable)
    }

    func test_complianceHold_isNeverShownAsNetworkError() {
        XCTAssertEqual(FinanceCoreErrorCode(rawValue: "CF_010").financeError,
                       .complianceBlocked(displayReason: nil))
    }

    // MARK: - Endpoints — §0.5

    func test_allRoutes_liveUnderChatCorePrefix() {
        let key = FinanceFixtures.idempotency(key: "k-1")
        let endpoints: [ChatFinanceEndpoints] = [
            .hubActions(conversationType: "DIRECT"),
            .prepareSendMoney(Self.prepareRequest, key),
            .execute(.sendMoney, Self.executeRequest, CorrelationId()),
            .requery(RequeryIntentRequest(financialIntentRef: "fco_1", conversationId: "conv_1"), CorrelationId()),
            .financialObject(ref: "fco_1"),
            .createMoneyRequest(Self.moneyRequest, key),
            .remindMoneyRequest(RemindMoneyRequestRequest(requestRef: "req_1", partyUserId: "usr_1"), CorrelationId()),
        ]
        for endpoint in endpoints {
            XCTAssertTrue(endpoint.path.hasPrefix("/chat-core/financial/"), endpoint.path)
        }
        XCTAssertEqual(ChatFinanceEndpoints.experienceConfig.path, "/chat-core/experience/config")
    }

    /// `Idempotency-Key` et `idempotencyKey` du corps viennent de la même valeur.
    func test_prepare_carriesTheSameIdempotencyKey_inHeaderAndBody() {
        let endpoint = ChatFinanceEndpoints.prepareSendMoney(Self.prepareRequest,
                                                             FinanceFixtures.idempotency(key: "idem-42"))
        XCTAssertEqual(endpoint.headers?["Idempotency-Key"], "idem-42")
        XCTAssertEqual(endpoint.parameters?["idempotencyKey"] as? String, "idem-42")
        XCTAssertEqual(endpoint.parameters?["currency"] as? String, "BIF")
        XCTAssertTrue(endpoint.isIdempotent, "Un prepare sous clé se rejoue sans créer d'intention")
    }

    /// Un champ optionnel absent ne part pas — pas de `null` que le serveur lirait comme une valeur.
    func test_absentOptionalFields_areNotSent() {
        let request = PrepareSendMoneyRequest(currency: "BIF", amountMinor: 1000, channel: "MOBILE",
                                              deviceId: "dev_1", beneficiaryToken: "btk_1",
                                              conversationId: nil, sourceWalletRef: nil)
        let parameters = ChatFinanceEndpoints.prepareSendMoney(request, FinanceFixtures.idempotency()).parameters ?? [:]
        XCTAssertNil(parameters["conversationId"])
        XCTAssertNil(parameters["sourceWalletRef"])
        XCTAssertEqual(parameters["amountMinor"] as? Int64, 1000)
    }

    /// Un execute ne se rejoue jamais — contrat §0.3.3.
    func test_execute_isNeverRetried() {
        let endpoint = ChatFinanceEndpoints.execute(.sendMoney, Self.executeRequest, CorrelationId())
        XCTAssertFalse(endpoint.isIdempotent)
        XCTAssertNil(endpoint.headers?["Idempotency-Key"])
    }

    /// Chat Core rédige ses messages dans cette langue : elle doit toujours partir.
    func test_headers_carryTheAppLanguage() {
        let headers = ChatFinanceEndpoints.experienceConfig.headers ?? [:]
        XCTAssertEqual(headers["Accept-Language"], CurrentSessionInfo.shared.languageCode)
        XCTAssertFalse((headers["Accept-Language"] ?? "").isEmpty)
    }

    func test_headers_followTheContract_andNeverSendCountry() {
        let correlation = CorrelationId(value: "corr-7")
        let endpoint = ChatFinanceEndpoints.requery(
            RequeryIntentRequest(financialIntentRef: "fco_1", conversationId: "conv_1"), correlation)
        let headers = endpoint.headers ?? [:]
        XCTAssertEqual(headers["X-Correlation-Id"], "corr-7")
        XCTAssertEqual(headers["X-Channel"], "MOBILE")
        XCTAssertEqual(headers["X-Contract-Version"], "1.4.0")
        XCTAssertNotNil(headers["x-chat-session"])
        XCTAssertNil(headers["X-Country"], "Le pays du JWT fait foi — ne pas l'envoyer")
    }

    func test_objectRead_isForSelf_andEscapesTheReference() {
        let endpoint = ChatFinanceEndpoints.financialObject(ref: "fco 9")
        XCTAssertEqual(endpoint.method, .get)
        XCTAssertEqual(endpoint.parameters?["reasonForAccess"] as? String, "SELF")
        XCTAssertEqual(endpoint.path, "/chat-core/financial/objects/fco%209")
    }

    func test_financeResponses_areNeverCached() {
        if case .noCache = ChatFinanceEndpoints.hubActions(conversationType: "DIRECT").cachePolicy {} else {
            XCTFail("Une réponse financière servie depuis un cache peut être périmée")
        }
    }

    // MARK: - Avant ou après envoi

    func test_executeTimeout_isInDoubt() async {
        let dataSource = HTTPChatFinanceDataSource(httpClient: StubAPIClient(error: APIError.timeout))
        let failure = await Self.failure {
            try await dataSource.execute(.sendMoney, Self.executeRequest, correlationID: CorrelationId())
        }
        XCTAssertEqual(failure?.financeError, .timeoutUnknown, "Un timeout après execute peut cacher un débit")
    }

    func test_readTimeout_isOnlyUnavailability() async {
        let dataSource = HTTPChatFinanceDataSource(httpClient: StubAPIClient(error: APIError.timeout))
        let failure = await Self.failure { try await dataSource.hubActions(conversationType: "DIRECT") }
        XCTAssertEqual(failure?.financeError, .networkUnavailable)
    }

    /// Sans réseau, rien n'est parti : pas d'ambiguïté même pour un execute.
    func test_executeWithoutNetwork_wasNeverSent() async {
        let dataSource = HTTPChatFinanceDataSource(httpClient: StubAPIClient(error: APIError.noInternetConnection))
        let failure = await Self.failure {
            try await dataSource.execute(.sendMoney, Self.executeRequest, correlationID: CorrelationId())
        }
        XCTAssertEqual(failure?.financeError, .networkUnavailable)
    }

    // MARK: - Fixtures

    static let prepareRequest = PrepareSendMoneyRequest(
        currency: "BIF", amountMinor: 1000, channel: "MOBILE", deviceId: "dev_1",
        beneficiaryToken: "btk_1", conversationId: "conv_1", sourceWalletRef: nil)

    static let executeRequest = ExecuteIntentRequest(
        financialIntentRef: "fco_1", confirmationId: "cnf_1", quoteId: "q_1", deviceId: "dev_1",
        conversationId: "conv_1", objectVersion: "1", executionPermitId: nil)

    static let moneyRequest = CreateMoneyRequestRequest(
        recipientUserIds: ["usr_1"], amountMode: "FIXED", currency: "BIF",
        amountMinor: 100, conversationId: nil, note: nil)

    /// L'échec levé par la source, ou `nil` si l'appel a réussi.
    static func failure<T>(_ call: () async throws -> T) async -> FinanceCoreError? {
        guard case .failure(let error) = await FinanceCoreError.capture(call) else { return nil }
        return error
    }
}

// MARK: - Doublures

private actor Flag {
    private(set) var value = false
    func raise() { value = true }
}

/// Décode avec la même configuration que `APIClient` (`convertFromSnakeCase`).
private final class StubAPIClient: APIClientProtocol, @unchecked Sendable {
    private let json: String?
    private let error: Error?

    init(json: String) { self.json = json; self.error = nil }
    init(error: Error) { self.json = nil; self.error = error }

    var isConnected: Bool { get async { true } }

    func request<T: Decodable>(endpoint: any APIEndpoint) async throws -> T {
        if let error { throw error }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: Data((json ?? "").utf8))
    }
    func cancelRequest(for endpoint: any APIEndpoint) async {}
    func cancelAllRequests() async {}
    func getPerformanceMetrics() async -> APIPerformanceMetrics {
        APIPerformanceMetrics(totalRequests: 0, successCount: 0, failureCount: 0, averageDuration: 0,
                              rateLimitedCount: 0, circuitBreakerBlockCount: 0)
    }
}
