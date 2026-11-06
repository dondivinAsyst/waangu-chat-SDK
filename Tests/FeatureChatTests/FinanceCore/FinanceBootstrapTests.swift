//
//  FinanceBootstrapTests.swift
//  FeatureChatTests
//
//  Phase 1 — amorçage de session et Hub, contre les JSON du contrat §1–2.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class FinanceBootstrapTests: XCTestCase {

    // MARK: - Séquence §1.1

    func test_bootstrap_followsTheContractOrder_andResumesALockedSession() async {
        let server = ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: true))
        let services = FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_42" })

        _ = await services.session.status()

        let calls = await server.calls
        XCTAssertEqual(calls.map(\.route), [
            "GET /chat-core/experience/config",
            // §1.1, étape 2 — optionnelle : sans route, elle échoue sans rien arrêter.
            "POST /chat-core/client-capabilities/negotiate",
            "GET /chat-core/governance/capabilities",
            "GET /chat-core/security/capabilities",
            "GET /chat-core/financial/session/resume",
            "POST /chat-core/financial/session/resume",
            // `paymentsAllowed` et les droits de sécurité relus après la levée
            // du verrou — voir `test_resumeUnlock_rereadsExperienceAndSecurity`.
            "GET /chat-core/experience/config",
            "GET /chat-core/security/capabilities",
        ])
        let resumeBody = calls[5].body
        XCTAssertEqual(resumeBody["deviceId"] as? String, "dev_42")
        for flag in ["syncAcknowledged", "iamValid", "complianceValid", "capabilityValid"] {
            XCTAssertEqual(resumeBody[flag] as? Bool, true, flag)
        }
    }

    func test_unlockedSession_isNotResumedAgain() async {
        let server = ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false))
        _ = await FinanceCoreLiveServices(apiClient: server, deviceID: { "d" }).session.status()
        let routes = await server.calls.map(\.route)
        XCTAssertFalse(routes.contains("POST /chat-core/financial/session/resume"))
    }

    func test_concurrentConsumers_shareOneBootstrap() async {
        let server = ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false))
        let services = FinanceCoreLiveServices(apiClient: server, deviceID: { "d" })

        async let a = services.capabilityGates.capabilities()
        async let b = services.killSwitch.activeSuspensions()
        async let c = services.session.status()
        _ = await (a, b, c)

        let experienceCalls = await server.calls.filter { $0.route == "GET /chat-core/experience/config" }
        XCTAssertEqual(experienceCalls.count, 1, "Trois écrans ouverts ensemble ne relancent pas trois amorçages")
    }

    // MARK: - Gouvernance §1.3–1.4

    func test_governanceMatrix_opensOnlyExecutableStates() async {
        let gates = FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false)),
                                            deviceID: { "d" }).capabilityGates

        let sendMoney = await gates.closure(for: FinancialCapabilityID.sendMoney)
        let topUpPilot = await gates.closure(for: FinancialCapabilityID.topUp)
        let remittance = await gates.closure(for: FinancialCapabilityID.remittance)
        let credit = await gates.closure(for: FinancialCapabilityID.creditDiscovery)
        XCTAssertNil(sendMoney, "GENERAL + allowed")
        XCTAssertNil(topUpPilot, "PILOT reste exécutable")
        XCTAssertEqual(remittance, .notEnabled, "DISABLED")
        XCTAssertEqual(credit, .notEnabled, "PROHIBITED")
    }

    /// **Bloc 13 P0 fermé.** Une entrée sans clé de gouvernance n'est plus
    /// ouverte : absente de l'instantané, sa porte la ferme.
    func test_entryWithoutGovernanceKey_isClosedInLive() async {
        let gates = FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false)),
                                            deviceID: { "d" }).capabilityGates
        for kind in [FinanceEntryKind.merchant, .cards, .orders, .campaign, .invoice] {
            let closure = await gates.closure(for: kind.capabilityID ?? "")
            XCTAssertEqual(closure, .notEnabled, "\(kind)")
        }
    }

    func test_everyEntryKind_hasACapabilityID() {
        let ungated = FinanceEntryKind.allCases.filter { $0.capabilityID == nil }
        XCTAssertTrue(ungated.isEmpty, "Entrées ouvertes sans porte : \(ungated)")
    }

    func test_capabilityKillSwitch_suspendsItsProduct_countryKillSwitch_suspendsAll() async {
        var routes = Self.routes(resumeLocked: false)
        routes["GET /chat-core/governance/capabilities"] = Self.governanceJSON(killCashOut: true, countryKill: false)
        let perProduct = await FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes),
                                                       deviceID: { "d" }).killSwitch.activeSuspensions()
        XCTAssertTrue(perProduct.suspendedProducts.contains(FinanceEntryKind.cashOut.rawValue))
        XCTAssertFalse(perProduct.entireFinancialLayerSuspended)

        routes["GET /chat-core/governance/capabilities"] = Self.governanceJSON(killCashOut: false, countryKill: true)
        let country = await FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes),
                                                    deviceID: { "d" }).killSwitch.activeSuspensions()
        XCTAssertTrue(country.entireFinancialLayerSuspended)
    }

    /// Le serveur déverrouille à la reprise, et **experience comme sécurité**
    /// changent alors. Relire la seule experience laissait la sécurité affirmer
    /// `financialActionsLocked` et `PAYMENT_PREPARE: DENY` : l'écran réclamait
    /// une revalidation que le serveur venait d'accorder.
    func test_resumeUnlock_rereadsExperienceAndSecurity() async {
        var routes = Self.routes(resumeLocked: true)
        routes["GET /chat-core/financial/session/resume"] = Self.wrap(
            #"{ "userId": "usr_1", "locked": true }"#)
        routes["GET /chat-core/experience/config"] = Self.experienceJSON(locked: true)
        routes["GET /chat-core/security/capabilities"] = Self.securityJSON(unlocked: false)
        let server = ScriptedChatCoreAPIClient(
            routes: routes,
            sequences: [
                "GET /chat-core/experience/config": [Self.experienceJSON(locked: true),
                                                     Self.experienceJSON(locked: false)],
                "GET /chat-core/security/capabilities": [Self.securityJSON(unlocked: false),
                                                          Self.securityJSON(unlocked: true)],
            ])
        let services = FinanceCoreLiveServices(apiClient: server, deviceID: { "dev_1" })

        guard case .success(let status) = await services.session.status() else { return XCTFail() }

        XCTAssertFalse(status.writeLocked, "La reprise a levé le verrou")
        XCTAssertTrue(status.paymentPrepareAllowed, "La sécurité relue accorde PAYMENT_PREPARE")
        XCTAssertTrue(status.canWrite)
        let securityReads = await server.calls.filter { $0.route == "GET /chat-core/security/capabilities" }
        XCTAssertEqual(securityReads.count, 2, "Sécurité relue après le déverrouillage")
    }

    // MARK: - Échec d'amorçage : tout fermé

    func test_failedBootstrap_closesEverything() async {
        var routes = Self.routes(resumeLocked: false)
        routes["GET /chat-core/governance/capabilities"] = Self.error("CF_003")
        let services = FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes), deviceID: { "d" })

        let suspensions = await services.killSwitch.activeSuspensions()
        let gates = await services.capabilityGates.capabilities()
        let entries = await services.catalog.entries(for: Self.direct)
        let capabilities = await services.capabilities(for: FinanceFixtures.testContext)
        let status = await services.session.status()

        XCTAssertEqual(suspensions, .everything)
        XCTAssertTrue(gates.isEmpty)
        XCTAssertTrue(entries.isEmpty)
        XCTAssertFalse(capabilities.allowsAnyOutgoingOperation)
        guard case .failure(.capabilityUnavailable) = status else { return XCTFail("\(status)") }
    }

    // MARK: - Statut de session

    func test_lockedOrSafeMode_forbidsWrites_evenIfGovernanceAllows() async {
        var routes = Self.routes(resumeLocked: true)
        routes["POST /chat-core/financial/session/resume"] = Self.error("CF_066")
        let services = FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes), deviceID: { "d" })

        let capabilities = await services.capabilities(for: FinanceFixtures.testContext)
        guard case .success(let status) = await services.session.status() else { return XCTFail() }

        XCTAssertTrue(status.writeLocked)
        XCTAssertFalse(status.canWrite)
        XCTAssertFalse(capabilities.sendMoney, "Session verrouillée : aucune écriture, même autorisée par la gouvernance")
        XCTAssertTrue(capabilities.viewFinancialCards, "La lecture reste permise")
    }

    func test_missingSafeMode_isReadAsConsultationOnly() {
        let snapshot = FinanceSessionSnapshot(
            experience: ExperienceConfigDTO(schemaVersion: nil, country: "BI", allowedCountries: nil,
                                            countryApproved: true, countryLocalized: nil, currency: "BIF",
                                            paymentsAllowed: true, financialActionsLocked: false, safeMode: nil,
                                            killSwitchGlobal: false, killSwitchCountry: false,
                                            contractVersion: nil, configGeneration: nil, configHash: nil),
            governance: GovernanceSnapshotDTO(schemaVersion: nil, country: "BI", countryApproved: true,
                                              allowedCountries: nil, currency: "BIF", contractVersion: nil,
                                              configGeneration: nil, configHash: nil, killSwitchGlobal: nil,
                                              killSwitchCountry: nil, safeMode: nil, paymentsAllowed: nil,
                                              capabilities: []),
            security: SecurityCapabilitiesDTO(financialActionsLocked: false, capabilities: nil),
            resume: nil, fetchedAt: Date()
        )
        let status = FinanceGovernanceMapper.status(from: snapshot)
        XCTAssertTrue(status.safeModeActive)
        XCTAssertTrue(status.writeLocked, "Sans état de reprise, la session est verrouillée")
        XCTAssertFalse(status.canWrite)
    }

    // MARK: - Hub §2.1

    func test_hubActions_respectVisibleEnabled_andConversationType() async {
        let server = ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false))
        let entries = await FinanceCoreLiveServices(apiClient: server, deviceID: { "d" })
            .catalog.entries(for: Self.group)

        XCTAssertEqual(entries.map(\.kind), [.sendMoney, .requestMoney, .cashOut])
        XCTAssertTrue(entries[0].isEnabled)
        XCTAssertFalse(entries[2].isEnabled, "visible + enabled=false : grisé")
        // `REVALIDATE_SESSION` : jamais affiché brut, mais pas noyé dans un motif
        // générique — « session à revalider » appelle un autre geste.
        XCTAssertEqual(entries[2].unavailableReasonKey, "finance.session.session_locked_detail",
                       "La raison technique du serveur est traduite en son motif, jamais affichée brute")

        let hubCall = await server.calls.first { $0.route.contains("/hub/actions") }
        XCTAssertEqual(hubCall?.query["conversationType"], "GROUP")
    }

    func test_hubActions_areCachedUntilInvalidated() async {
        let server = ScriptedChatCoreAPIClient(routes: Self.routes(resumeLocked: false))
        let catalog = FinanceCoreLiveServices(apiClient: server, deviceID: { "d" }).catalog

        _ = await catalog.entries(for: Self.direct)
        _ = await catalog.entries(for: Self.direct)
        var hubCalls = await server.calls.filter { $0.route.contains("/hub/actions") }.count
        XCTAssertEqual(hubCalls, 1)

        await catalog.invalidate()
        _ = await catalog.entries(for: Self.direct)
        hubCalls = await server.calls.filter { $0.route.contains("/hub/actions") }.count
        XCTAssertEqual(hubCalls, 2)
    }

    /// Le Hub muet et le Hub injoignable ne se disent pas pareil : l'accueil
    /// explique le premier par le marché et remplace l'écran pour le second.
    func test_catalogLoad_distinguishesUnreachableFromEmpty() async {
        let down = ScriptedChatCoreAPIClient(routes: [:])
        let unreachable = FinanceCoreLiveServices(apiClient: down, deviceID: { "d" }).catalog
        let failure = await unreachable.load(for: Self.direct)
        guard case .failure = failure else {
            return XCTFail("Un Hub injoignable doit rendre un échec, pas une liste vide")
        }
        // L'ancien contrat est préservé pour les appelants qui ne lisent qu'une liste.
        let entries = await unreachable.entries(for: Self.direct)
        XCTAssertTrue(entries.isEmpty)

        var routes = Self.routes(resumeLocked: false)
        routes["GET /chat-core/financial/hub/actions"] = Self.wrap("[]")
        let empty = FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes), deviceID: { "d" }).catalog
        guard case .success(let none) = await empty.load(for: Self.direct) else {
            return XCTFail("Un Hub qui répond « rien » est un succès vide")
        }
        XCTAssertTrue(none.isEmpty)
    }

    /// Un fournisseur local ne peut pas être injoignable : le défaut du
    /// protocole rend toujours un succès.
    func test_closedCatalog_loadsSuccessfullyWithNoEntries() async {
        guard case .success(let entries) = await ClosedChatFinanceCatalog().load(for: Self.direct) else {
            return XCTFail("Le catalogue fermé ne peut pas échouer")
        }
        XCTAssertTrue(entries.isEmpty)
    }

    // MARK: - Vue-modèle

    /// Backend simulé : aucune session à lire, donc aucun écran
    /// d'indisponibilité — sinon les doublures s'ouvriraient sur une panne.
    @MainActor
    func test_viewModel_withoutProvider_isNotApplicable() async {
        let viewModel = FinanceSessionViewModel(provider: nil)
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .notApplicable)
        XCTAssertNil(viewModel.restriction)
        XCTAssertFalse(viewModel.canWrite)
    }

    @MainActor
    func test_viewModel_namesTheMostBlockingRestrictionFirst() async {
        let status = FinanceSessionStatus(paymentsAllowed: false, writeLocked: true, safeModeActive: true,
                                          serviceSuspended: false, countryOpen: false, currency: "BIF")
        let viewModel = FinanceSessionViewModel(provider: FixedSession(result: .success(status)))
        await viewModel.load()
        XCTAssertEqual(viewModel.restriction, .countryClosed)
        XCTAssertFalse(viewModel.canWrite)
    }

    @MainActor
    func test_viewModel_failedBootstrap_isUnavailable_notWritable() async {
        let viewModel = FinanceSessionViewModel(provider: FixedSession(result: .failure(.networkUnavailable)))
        await viewModel.load()
        XCTAssertEqual(viewModel.state, .unavailable)
        XCTAssertEqual(viewModel.restriction, .unavailable)
        XCTAssertFalse(viewModel.canWrite)
    }

    // MARK: - Fixtures — JSON du contrat

    static let direct = ChatFinanceContext(conversationID: "conv_1", conversationKind: .direct, participantCount: 2)
    static let group = ChatFinanceContext(conversationID: "conv_2", conversationKind: .group, participantCount: 5)

    static func wrap(_ data: String) -> String {
        #"{ "success": true, "message": null, "statusCode": 200, "data": \#(data), "error": null, "timestamp": "2026-09-09T12:00:00Z" }"#
    }

    static func error(_ code: String) -> String {
        #"{ "success": false, "message": null, "statusCode": 0, "data": null, "error": { "code": "\#(code)", "message": "x", "details": null }, "timestamp": "2026-09-09T12:00:01Z" }"#
    }

    static func governanceJSON(killCashOut: Bool = false, countryKill: Bool = false) -> String {
        func decision(_ key: String, _ state: String, allowed: Bool, kill: Bool = false) -> String {
            #"{ "country": "BI", "capabilityKey": "\#(key)", "state": "\#(state)", "countryApproved": true, "killSwitch": \#(kill), "allowed": \#(allowed), "reason": null, "errorCode": null }"#
        }
        let capabilities = [
            decision("SEND_MONEY", "GENERAL", allowed: true),
            decision("REQUEST_MONEY", "GENERAL", allowed: true),
            decision("TOP_UP", "PILOT", allowed: true),
            decision("CASH_OUT", "LIMITED", allowed: true, kill: killCashOut),
            decision("REMITTANCE", "DISABLED", allowed: false),
            decision("CREDIT", "PROHIBITED", allowed: false),
        ].joined(separator: ",")
        return wrap(#"""
        { "schemaVersion": "1.0.0", "country": "BI", "countryApproved": true, "allowedCountries": ["BI","RW","CA"],
          "currency": "BIF", "contractVersion": "1.4.0", "configGeneration": 1, "configHash": "h1",
          "killSwitchGlobal": false, "killSwitchCountry": \#(countryKill), "safeMode": "NORMAL", "paymentsAllowed": true,
          "capabilities": [\#(capabilities)] }
        """#)
    }

    /// `experience/config`, verrouillée ou non — comme le serveur la rend avant
    /// et après une reprise.
    static func experienceJSON(locked: Bool) -> String {
        wrap(#"""
        { "schemaVersion": "1.0.0", "country": "BI", "allowedCountries": ["BI","RW","CA"], "countryApproved": true,
          "countryLocalized": true, "currency": "BIF", "paymentsAllowed": \#(!locked),
          "financialActionsLocked": \#(locked), "consultationAllowed": true,
          "safeMode": "NORMAL", "killSwitchGlobal": false, "killSwitchCountry": false, "contractVersion": "1.4.0",
          "configGeneration": 1, "configHash": "h1" }
        """#)
    }

    /// `security/capabilities` dans la forme réelle du serveur.
    static func securityJSON(unlocked: Bool) -> String {
        let disposition = unlocked ? "ALLOW" : "DENY"
        return wrap(#"""
        { "schemaVersion": "1.0.0", "userId": "usr_1", "financialActionsLocked": \#(!unlocked),
          "riskEngineWired": false,
          "capabilities": [
            { "capability": "FINANCE_READ", "disposition": "ALLOW", "highRisk": false },
            { "capability": "PAYMENT_PREPARE", "disposition": "\#(disposition)", "highRisk": false },
            { "capability": "PAYMENT_CONFIRM", "disposition": "\#(disposition)", "highRisk": false },
            { "capability": "CASH_OUT", "disposition": "DENY", "highRisk": true } ] }
        """#)
    }

    static func routes(resumeLocked: Bool) -> [String: String] {
        [
            "GET /chat-core/experience/config": wrap(#"""
            { "schemaVersion": "1.0.0", "country": "BI", "allowedCountries": ["BI","RW","CA"], "countryApproved": true,
              "countryLocalized": true, "currency": "BIF", "paymentsAllowed": true, "financialActionsLocked": false,
              "safeMode": "NORMAL", "killSwitchGlobal": false, "killSwitchCountry": false, "contractVersion": "1.4.0",
              "configGeneration": 1, "configHash": "h1" }
            """#),
            "GET /chat-core/governance/capabilities": governanceJSON(),
            "GET /chat-core/security/capabilities": wrap(#"""
            { "schemaVersion": "1.0.0", "userId": "usr_1", "financialActionsLocked": false, "riskEngineWired": false,
              "capabilities": [
                { "capability": "CHAT_READ", "disposition": "ALLOW", "highRisk": false },
                { "capability": "FINANCE_READ", "disposition": "ALLOW", "highRisk": false },
                { "capability": "PAYMENT_PREPARE", "disposition": "ALLOW", "highRisk": false },
                { "capability": "PAYMENT_CONFIRM", "disposition": "ALLOW", "highRisk": false },
                { "capability": "CASH_OUT", "disposition": "UNAVAILABLE", "highRisk": true } ] }
            """#),
            "GET /chat-core/financial/session/resume": wrap(#"""
            { "userId": "usr_1", "deviceId": "dev_1", "locked": \#(resumeLocked), "expiresAt": "2099-09-09T12:15:00Z" }
            """#),
            "POST /chat-core/financial/session/resume": wrap(#"""
            { "userId": "usr_1", "deviceId": "dev_42", "syncAcknowledged": true, "iamValid": true,
              "complianceValid": true, "capabilityValid": true, "resumedAt": "2026-09-09T12:00:00Z",
              "expiresAt": "2099-09-09T12:15:00Z", "locked": false }
            """#),
            "GET /chat-core/financial/hub/actions": wrap(#"""
            [ { "code": "SEND_MONEY", "label": "Send Money", "intentType": "WALLET_TRANSFER", "version": "1.0.0",
                "visible": true, "enabled": true, "requiresStepUp": false, "shortcutGroup": "P2P", "reason": null },
              { "code": "REQUEST_MONEY", "label": "Request Money", "visible": true, "enabled": true, "reason": null },
              { "code": "GROUP_COLLECTION", "label": "Collect", "visible": true, "enabled": true, "reason": null },
              { "code": "REMITTANCE", "label": "Remittance", "visible": false, "enabled": false, "reason": "Capability DISABLED in BI" },
              { "code": "CASH_OUT", "label": "Cash out", "visible": true, "enabled": false, "reason": "REVALIDATE_SESSION" },
              { "code": "ASK_COPILOT", "label": "Ask", "visible": true, "enabled": true, "reason": null } ]
            """#),
        ]
    }
}

// MARK: - Doublures

private struct FixedSession: FinanceSessionProviding {
    let result: Result<FinanceSessionStatus, FinanceError>
    func status() async -> Result<FinanceSessionStatus, FinanceError> { result }
    func invalidate() async {}
}
