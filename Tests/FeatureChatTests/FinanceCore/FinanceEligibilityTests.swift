//
//  FinanceEligibilityTests.swift
//  FeatureChatTests
//
//  Ce que l'amorçage autorise — experience, gouvernance, sécurité, Hub
//  (INTEGRATION_CHAT_FINANCE.md §1.2, §1.5, §2.1).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceEligibilityTests: XCTestCase {

    // MARK: - §1.5 Décodage de la sécurité : toute forme, jamais d'échec

    /// La réponse **réelle** du serveur (2026-09-16) : `capability` + `disposition`.
    /// Avant ce correctif, aucun droit n'était lu — tout paraissait refusé.
    func test_security_realServerResponse_grantsOnlyAllow() throws {
        let dto = try Self.decodeSecurity(Self.realSecurityJSON)
        for right in ["CHAT_READ", "CHAT_SEND", "FINANCE_READ", "PAYMENT_PREPARE", "PAYMENT_CONFIRM"] {
            XCTAssertTrue(dto.allows(right), right)
        }
        for right in ["CASH_OUT", "ADD_BENEFICIARY", "ADD_CARD", "EXPORT_DATA", "HIGH_VALUE_PAYMENT"] {
            XCTAssertFalse(dto.allows(right), "\(right) : UNAVAILABLE ne vaut pas accord")
        }
        XCTAssertEqual(dto.financialActionsLocked, false)
    }

    /// Le serveur réel, de bout en bout : lecture, préparation et confirmation
    /// permises ; retrait fermé par le moteur de risque.
    func test_realServerResponse_opensReadAndWrites_butNotCashOut() throws {
        let security = try Self.decodeSecurity(Self.realSecurityJSON)
        let snapshot = Self.snapshot(security: security)
        let status = FinanceGovernanceMapper.status(from: snapshot)
        XCTAssertTrue(status.canReadAccount)
        XCTAssertTrue(status.canWrite)
        XCTAssertTrue(status.canConfirm)
        let cashOut = FinanceGovernanceMapper.capabilities(from: snapshot)
            .first { $0.capabilityID == FinancialCapabilityID.cashOut }
        XCTAssertEqual(cashOut?.closure(), .notEnabled)
    }

    func test_disposition_winsOverABoolean_andUnknownValuesRefuse() throws {
        let dto = try Self.decodeSecurity(#"""
        { "capabilities": [ { "capability": "FINANCE_READ", "disposition": "DENY", "allowed": true },
                            { "capability": "PAYMENT_PREPARE", "disposition": "allow" },
                            { "capability": "PAYMENT_CONFIRM", "disposition": "STEP_UP_LATER" } ] }
        """#)
        XCTAssertFalse(dto.allows("FINANCE_READ"))
        XCTAssertTrue(dto.allows("PAYMENT_PREPARE"), "Casse indifférente")
        XCTAssertFalse(dto.allows("PAYMENT_CONFIRM"), "Valeur inconnue ⇒ refusé")

        let map = try Self.decodeSecurity(#"{ "capabilities": { "FINANCE_READ": { "disposition": "ALLOW" } } }"#)
        XCTAssertTrue(map.allows("FINANCE_READ"))
    }

    func test_security_decodesAListOfStringsAndObjects() throws {
        let dto = try Self.decodeSecurity(#"""
        { "financialActionsLocked": true,
          "capabilities": ["FINANCE_READ", { "capabilityKey": "PAYMENT_PREPARE", "granted": true },
                           { "name": "CASH_OUT", "allowed": false }, 42] }
        """#)
        XCTAssertEqual(dto.financialActionsLocked, true)
        XCTAssertTrue(dto.allows("FINANCE_READ"))
        XCTAssertTrue(dto.allows("PAYMENT_PREPARE"))
        XCTAssertFalse(dto.allows("CASH_OUT"))
        XCTAssertFalse(dto.allows("PAYMENT_CONFIRM"), "Non listé ⇒ refusé")
    }

    func test_security_decodesAMapOfFlags_orOfObjects() throws {
        let flags = try Self.decodeSecurity(#"{ "capabilities": { "FINANCE_READ": true, "CASH_OUT": false } }"#)
        XCTAssertTrue(flags.allows("FINANCE_READ"))
        XCTAssertFalse(flags.allows("CASH_OUT"))

        let objects = try Self.decodeSecurity(#"{ "capabilities": { "PAYMENT_CONFIRM": { "allowed": true } } }"#)
        XCTAssertTrue(objects.allows("PAYMENT_CONFIRM"))
    }

    func test_security_decodesARootArray() throws {
        let dto = try Self.decodeSecurity(#"["FINANCE_READ"]"#)
        XCTAssertTrue(dto.allows("FINANCE_READ"))
        XCTAssertNil(dto.financialActionsLocked)
    }

    /// Une forme inattendue ne fait pas tomber l'amorçage : elle n'accorde rien.
    func test_security_unexpectedShape_grantsNothing_butNeverThrows() throws {
        for json in [#"{ "capabilities": "ALL" }"#, #"{ "financialActionsLocked": "yes" }"#, #"{}"#, #"7"#] {
            let dto = try Self.decodeSecurity(json)
            XCTAssertFalse(dto.allows("FINANCE_READ"), json)
        }
    }

    // MARK: - Statut de session

    func test_consultationNotAllowed_forbidsReading_absentDoesNot() {
        let off = FinanceGovernanceMapper.status(from: Self.snapshot(consultationAllowed: false))
        XCTAssertFalse(off.canReadAccount)
        XCTAssertFalse(off.financeReadAllowed)

        let absent = FinanceGovernanceMapper.status(from: Self.snapshot(consultationAllowed: nil))
        XCTAssertTrue(absent.canReadAccount, "Un serveur qui ne l'envoie pas ne retire rien")
    }

    func test_countryNotLocalized_closesTheCountry() {
        let status = FinanceGovernanceMapper.status(from: Self.snapshot(countryLocalized: false))
        XCTAssertFalse(status.countryOpen, "Approuvé mais non localisé : écran « pays non ouvert » (§1.2)")
        XCTAssertFalse(status.canReadAccount)
    }

    func test_experienceFinancialActionsLocked_locksWrites() {
        let status = FinanceGovernanceMapper.status(from: Self.snapshot(experienceLocked: true))
        XCTAssertTrue(status.writeLocked)
        XCTAssertFalse(status.canWrite)
        XCTAssertTrue(status.canReadAccount, "Un verrou d'écriture n'empêche pas de consulter")
    }

    func test_securityRights_decideReadPrepareAndConfirm() {
        let all = FinanceGovernanceMapper.status(from: Self.snapshot())
        XCTAssertTrue(all.canReadAccount)
        XCTAssertTrue(all.canWrite)
        XCTAssertTrue(all.canConfirm)

        let noRead = FinanceGovernanceMapper.status(from: Self.snapshot(rights: ["PAYMENT_PREPARE", "PAYMENT_CONFIRM"]))
        XCTAssertFalse(noRead.canReadAccount)

        let noPrepare = FinanceGovernanceMapper.status(from: Self.snapshot(rights: ["FINANCE_READ", "PAYMENT_CONFIRM"]))
        XCTAssertFalse(noPrepare.canWrite)
        XCTAssertFalse(noPrepare.canConfirm)

        let noConfirm = FinanceGovernanceMapper.status(from: Self.snapshot(rights: ["FINANCE_READ", "PAYMENT_PREPARE"]))
        XCTAssertTrue(noConfirm.canWrite)
        XCTAssertFalse(noConfirm.canConfirm)
    }

    /// Les cartes déjà reçues restent lisibles hors pays ouvert : `FINANCE_READ` seul décide.
    func test_financialCards_followFinanceReadOnly() {
        let closedCountry = Self.snapshot(countryLocalized: false)
        let capabilities = FinanceGovernanceMapper.financeCapabilities(from: closedCountry,
                                                                       context: FinanceFixtures.testContext)
        XCTAssertTrue(capabilities.viewFinancialCards)
        XCTAssertFalse(capabilities.sendMoney)
    }

    /// `CASH_OUT` ouvert par la gouvernance reste fermé sans le droit de session à haut risque.
    func test_cashOut_needsTheSecurityRight() {
        let withoutRight = FinanceGovernanceMapper.capabilities(from: Self.snapshot())
        XCTAssertEqual(withoutRight.first { $0.capabilityID == FinancialCapabilityID.cashOut }?.closure(), .notEnabled)

        let withRight = FinanceGovernanceMapper.capabilities(
            from: Self.snapshot(rights: ["FINANCE_READ", "PAYMENT_PREPARE", "PAYMENT_CONFIRM", "CASH_OUT"]))
        XCTAssertNil(withRight.first { $0.capabilityID == FinancialCapabilityID.cashOut }?.closure())
    }

    // MARK: - Portes au bord des données

    func test_prepareWithoutPaymentPrepare_neverLeaves() async {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/security/capabilities"] = Self.securityJSON(["FINANCE_READ", "PAYMENT_CONFIRM"])
        let (services, server) = FinanceSendMoneyTests.make(routes)

        let result = await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft())

        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let prepares = await server.calls.filter { $0.route.hasSuffix("/prepare") }
        XCTAssertTrue(prepares.isEmpty)
    }

    func test_executeWithoutPaymentConfirm_neverLeaves() async throws {
        var routes = FinanceSendMoneyTests.routes()
        routes["GET /chat-core/security/capabilities"] = Self.securityJSON(["FINANCE_READ", "PAYMENT_PREPARE"])
        let (services, server) = FinanceSendMoneyTests.make(routes)
        let quote = try await services.transferQuoting.quote(for: FinanceSendMoneyTests.draft()).get()

        let outcome = await FinanceSendMoneyTests.confirm(quote, services: services)

        if case .executed = outcome { XCTFail("Aucun execute sans PAYMENT_CONFIRM") }
        let executes = await server.calls.filter { $0.route.hasSuffix("/execute") }
        XCTAssertTrue(executes.isEmpty)
    }

    func test_cashOutPrepareWithoutCashOutRight_neverLeaves() async {
        var routes = FinanceQuotedOperationsTests.routes()
        routes["POST /chat-core/financial/cash-out/prepare"] = routes["POST /chat-core/financial/pay-bill/prepare"]
        let (services, server) = FinanceQuotedOperationsTests.make(routes)

        let result = await services.quotedOperations
            .prepare(.cashOut, body: [:], idempotency: FinanceFixtures.idempotency())

        guard case .failure(.capabilityUnavailable) = result else { return XCTFail("\(result)") }
        let prepares = await server.calls.filter { $0.route.hasSuffix("/cash-out/prepare") }
        XCTAssertTrue(prepares.isEmpty)
    }

    // MARK: - §2.1 Hub

    func test_hubRequiresStepUp_isCarriedToTheEntry() {
        let actions = [
            ResolvedActionDTO(code: "TOP_UP", label: nil, intentType: nil, version: nil, visible: true,
                              enabled: true, requiresStepUp: true, shortcutGroup: nil, reason: nil),
            ResolvedActionDTO(code: "SEND_MONEY", label: nil, intentType: nil, version: nil, visible: true,
                              enabled: true, requiresStepUp: nil, shortcutGroup: nil, reason: nil),
        ]
        let entries = FinanceGovernanceMapper.catalogEntries(from: actions)
        XCTAssertEqual(entries.first { $0.kind == .topUp }?.requiresStepUp, true)
        XCTAssertEqual(entries.first { $0.kind == .sendMoney }?.requiresStepUp, false)
    }

    func test_hubReason_isTranslatedToTheMatchingMotive() {
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: "REVALIDATE_SESSION"),
                       "finance.session.session_locked_detail")
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: "SAFE_MODE"),
                       "finance.session.safe_mode_detail")
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: "Kill-switch"),
                       "finance.killswitch.suspended")
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: "Capability PROHIBITED in BI"),
                       CapabilityClosure.notEnabled.messageKey)
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: "something new"),
                       FinanceTranslationKeys.ENTRY_UNAVAILABLE)
        XCTAssertEqual(FinanceGovernanceMapper.reasonKey(forHubReason: nil),
                       FinanceTranslationKeys.ENTRY_UNAVAILABLE)
    }

    // MARK: - Vue-modèle : lire le compte seulement après l'amorçage

    @MainActor
    func test_accountIsNeverReadBeforeTheBootstrapAnswers() async {
        let viewModel = FinanceSessionViewModel(provider: StatusSession(result: .success(Self.status())))
        XCTAssertFalse(viewModel.canReadAccount, "En chargement : aucune lecture du solde")
        await viewModel.load()
        XCTAssertTrue(viewModel.canReadAccount)
    }

    @MainActor
    func test_failedBootstrap_forbidsAccountRead() async {
        let viewModel = FinanceSessionViewModel(provider: StatusSession(result: .failure(.networkUnavailable)))
        await viewModel.load()
        XCTAssertFalse(viewModel.canReadAccount)
    }

    @MainActor
    func test_readDenied_isNamed_andForbidsAccountRead() async {
        let viewModel = FinanceSessionViewModel(
            provider: StatusSession(result: .success(Self.status(financeRead: false))))
        await viewModel.load()
        XCTAssertEqual(viewModel.restriction, .readDenied)
        XCTAssertFalse(viewModel.canReadAccount)
    }

    @MainActor
    func test_safeMode_stillAllowsAccountRead() async {
        let viewModel = FinanceSessionViewModel(
            provider: StatusSession(result: .success(Self.status(safeMode: true))))
        await viewModel.load()
        XCTAssertEqual(viewModel.restriction, .safeMode)
        XCTAssertTrue(viewModel.canReadAccount)
    }

    @MainActor
    func test_simulatedBackend_readsTheDebugAccount() async {
        let viewModel = FinanceSessionViewModel(provider: nil)
        await viewModel.load()
        XCTAssertTrue(viewModel.canReadAccount)
    }

    // MARK: - Fixtures

    static let allRights = ["FINANCE_READ", "PAYMENT_PREPARE", "PAYMENT_CONFIRM"]

    /// `data` de `GET /chat-core/security/capabilities`, tel que le serveur l'a rendu.
    static let realSecurityJSON = #"""
    {"schemaVersion":"1.0.0","userId":"100000000000000001","deviceId":"94FB11A3-2326-4992-836E-38A863B4AC96","securityEpoch":1789572436533,"latestSecurityEpoch":null,"financialActionsLocked":false,"riskEngineWired":false,"principle":"Security Decision ≠ Financial Execution","capabilities":[{"capability":"CHAT_READ","disposition":"ALLOW","highRisk":false,"publicReason":"Low-risk Chat action does not require the Risk engine"},{"capability":"CHAT_SEND","disposition":"ALLOW","highRisk":false,"publicReason":"Low-risk Chat action does not require the Risk engine"},{"capability":"FINANCE_READ","disposition":"ALLOW","highRisk":false,"publicReason":"Low-risk Chat action does not require the Risk engine"},{"capability":"PAYMENT_PREPARE","disposition":"ALLOW","highRisk":false,"publicReason":"Low-risk Chat action does not require the Risk engine"},{"capability":"PAYMENT_CONFIRM","disposition":"ALLOW","highRisk":false,"publicReason":"Low-risk Chat action does not require the Risk engine"},{"capability":"CASH_OUT","disposition":"UNAVAILABLE","highRisk":true,"publicReason":"Risk engine unavailable — high-risk action blocked"},{"capability":"ADD_BENEFICIARY","disposition":"UNAVAILABLE","highRisk":true,"publicReason":"Risk engine unavailable — high-risk action blocked"},{"capability":"ADD_CARD","disposition":"UNAVAILABLE","highRisk":true,"publicReason":"Risk engine unavailable — high-risk action blocked"},{"capability":"EXPORT_DATA","disposition":"UNAVAILABLE","highRisk":true,"publicReason":"Risk engine unavailable — high-risk action blocked"},{"capability":"HIGH_VALUE_PAYMENT","disposition":"UNAVAILABLE","highRisk":true,"publicReason":"Risk engine unavailable — high-risk action blocked"}]}
    """#

    static func decodeSecurity(_ json: String) throws -> SecurityCapabilitiesDTO {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(SecurityCapabilitiesDTO.self, from: Data(json.utf8))
    }

    static func securityJSON(_ rights: [String]) -> String {
        let list = rights.map { "\"\($0)\"" }.joined(separator: ", ")
        return FinanceCoreJSON.wrap(#"{ "financialActionsLocked": false, "capabilities": [\#(list)] }"#)
    }

    static func status(financeRead: Bool = true, safeMode: Bool = false) -> FinanceSessionStatus {
        FinanceSessionStatus(paymentsAllowed: true, writeLocked: false, safeModeActive: safeMode,
                             serviceSuspended: false, countryOpen: true, currency: "BIF",
                             financeReadAllowed: financeRead, paymentPrepareAllowed: true,
                             paymentConfirmAllowed: true)
    }

    static func snapshot(countryLocalized: Bool = true, experienceLocked: Bool = false,
                         consultationAllowed: Bool? = true,
                         rights: [String] = allRights,
                         security: SecurityCapabilitiesDTO? = nil) -> FinanceSessionSnapshot {
        FinanceSessionSnapshot(
            experience: ExperienceConfigDTO(schemaVersion: "1.0.0", country: "BI", allowedCountries: ["BI"],
                                            countryApproved: true, countryLocalized: countryLocalized,
                                            currency: "BIF", paymentsAllowed: true,
                                            financialActionsLocked: experienceLocked, safeMode: "NORMAL",
                                            killSwitchGlobal: false, killSwitchCountry: false,
                                            contractVersion: "1.4.0", configGeneration: 1, configHash: "h1",
                                            consultationAllowed: consultationAllowed),
            governance: GovernanceSnapshotDTO(
                schemaVersion: "1.0.0", country: "BI", countryApproved: true, allowedCountries: ["BI"],
                currency: "BIF", contractVersion: "1.4.0", configGeneration: 1, configHash: "h1",
                killSwitchGlobal: false, killSwitchCountry: false, safeMode: "NORMAL", paymentsAllowed: true,
                capabilities: ["SEND_MONEY", "CASH_OUT"].map {
                    CapabilityDecisionDTO(country: "BI", capabilityKey: $0, state: "GENERAL", countryApproved: true,
                                          killSwitch: false, allowed: true, reason: nil, errorCode: nil)
                }),
            security: security ?? SecurityCapabilitiesDTO(
                financialActionsLocked: false,
                capabilities: rights.map { SecurityCapabilityDTO(key: $0, allowed: true) }),
            resume: ResumeStateDTO(userId: "usr_1", tenantId: nil, sessionId: nil, deviceId: "dev_1",
                                   syncAcknowledged: true, iamValid: true, complianceValid: true,
                                   capabilityValid: true, resumedAt: nil, expiresAt: "2099-09-09T12:15:00Z",
                                   locked: false),
            fetchedAt: Date()
        )
    }
}

private struct StatusSession: FinanceSessionProviding {
    let result: Result<FinanceSessionStatus, FinanceError>
    func status() async -> Result<FinanceSessionStatus, FinanceError> { result }
    func invalidate() async {}
}
