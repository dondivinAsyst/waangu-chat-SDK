//
//  GlobalChatFinanceIndependenceTests.swift
//  FeatureChatTests
//
//  TEST-GLOBALCHAT-001 — une finance refusée ne coupe jamais le Chat ordinaire.
//  Voir docs/harness/IOS_WORK_PLAN.md (W1) et l'autoprompt Harness §10, §26, §27.
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

/// Chaque scénario prouve les deux moitiés de l'invariant dans le même test :
/// la gouvernance de Chat Core ferme la finance, **et** un message texte part
/// quand même.
///
/// Ce que ces tests ne prouvent pas seuls : que le chemin d'envoi ne lit
/// jamais la finance. Il n'en reçoit aucune dépendance aujourd'hui ; la barrière
/// `Scripts/ci_forbid_chat_send_finance_dependency.sh` garde cette propriété.
final class GlobalChatFinanceIndependenceTests: XCTestCase {

    // MARK: - Pays non licencié

    func test_unlicensedCountry_blocksEveryFinancialEntry_andChatStillSends() async {
        let finance = Self.finance(Self.routes(countryApproved: false))

        let gates = await finance.capabilityGates.capabilities()
        XCTAssertFalse(gates.isEmpty, "La gouvernance a été lue : le refus vient de la licence, pas d'un échec")
        for gate in gates {
            XCTAssertEqual(gate.closure(), .notLicensed, gate.capabilityID)
        }
        await assertNoFinancialEntryOpens(finance)

        await assertChatSendsText()
    }

    // MARK: - Licence inconnue

    func test_unknownLicence_failsClosed_andChatStillSends() async {
        var routes = Self.routes()
        routes["GET /chat-core/governance/capabilities"] = nil
        let finance = Self.finance(routes)

        let suspensions = await finance.killSwitch.activeSuspensions()
        XCTAssertEqual(suspensions, .everything, "Gouvernance illisible ⇒ tout suspendu")
        await assertNoFinancialEntryOpens(finance)

        await assertChatSendsText()
    }

    // MARK: - Coupe-circuits

    func test_globalKillSwitch_suspendsFinance_andChatStillSends() async {
        let finance = Self.finance(Self.routes(killSwitchGlobal: true))

        let suspensions = await finance.killSwitch.activeSuspensions()
        XCTAssertTrue(suspensions.entireFinancialLayerSuspended)
        await assertEveryFinancialEntryIsSuspended(finance)

        await assertChatSendsText()
    }

    func test_countryKillSwitch_suspendsFinance_andChatStillSends() async {
        let finance = Self.finance(Self.routes(killSwitchCountry: true))

        let suspensions = await finance.killSwitch.activeSuspensions()
        XCTAssertTrue(suspensions.entireFinancialLayerSuspended)
        await assertEveryFinancialEntryIsSuspended(finance)

        await assertChatSendsText()
    }

    // MARK: - Témoin : pays licencié

    /// Sans ce témoin, les scénarios de refus passeraient aussi avec une
    /// finance qui ne s'ouvre jamais.
    func test_licensedCountry_opensSendMoney_andChatStillSends() async {
        let finance = Self.finance(Self.routes())

        let admissions = await Self.admissions(finance)
        XCTAssertEqual(admissions[.sendMoney], .open)

        await assertChatSendsText()
    }

    // MARK: - Assertions

    private func assertNoFinancialEntryOpens(_ finance: FinanceCoreLiveServices,
                                             file: StaticString = #filePath,
                                             line: UInt = #line) async {
        let admissions = await Self.admissions(finance)
        let opened = admissions.filter { $0.value == .open }.map(\.key.rawValue).sorted()
        XCTAssertTrue(opened.isEmpty, "Entrées financières ouvertes : \(opened)", file: file, line: line)

        let capabilities = await finance.capabilities(for: FinanceFixtures.testContext)
        XCTAssertFalse(capabilities.allowsAnyOutgoingOperation, file: file, line: line)
    }

    private func assertEveryFinancialEntryIsSuspended(_ finance: FinanceCoreLiveServices,
                                                      file: StaticString = #filePath,
                                                      line: UInt = #line) async {
        let admissions = await Self.admissions(finance)
        for (kind, admission) in admissions {
            guard case .suspended = admission else {
                XCTFail("\(kind.rawValue) : \(admission)", file: file, line: line)
                continue
            }
        }
        await assertNoFinancialEntryOpens(finance, file: file, line: line)
    }

    /// Un message texte est sauvegardé localement, enfilé dans l'outbox du chat
    /// et publié sur le topic d'envoi — le chemin réel de `SendMessageUseCase`.
    private func assertChatSendsText(file: StaticString = #filePath, line: UInt = #line) async {
        let repository = RecordingDiscussionRepository()
        let outbox = RecordingChatOutbox()
        let realtime = RecordingRealtimeClient()
        let sendMessage = SendMessageUseCase(discussionRepository: repository, outbox: outbox, realtime: realtime)

        let code = await sendMessage.execute(SendMessageRequest(
            content: MessageContent(text: "bonjour"),
            type: .TEXT,
            conversationId: "conv_chat",
            receiver: nil,
            kind: .direct,
            recipientId: "usr_2"
        ))

        XCTAssertNotNil(code, "Le message a été refusé", file: file, line: line)
        XCTAssertEqual(repository.saved.map(\.conversationId), ["conv_chat"], file: file, line: line)
        XCTAssertEqual(outbox.items.map(\.actionType), [.sendMessage], file: file, line: line)
        XCTAssertEqual(realtime.publishedPaths, [ChatMQTTTopics.In.sendMessage.path], file: file, line: line)
    }

    // MARK: - Fixtures

    private static func finance(_ routes: [String: String]) -> FinanceCoreLiveServices {
        FinanceCoreLiveServices(apiClient: ScriptedChatCoreAPIClient(routes: routes), deviceID: { "dev_1" })
    }

    /// Le verdict d'ouverture de chaque entrée, calculé comme l'écran le calcule.
    private static func admissions(_ finance: FinanceCoreLiveServices) async -> [FinanceEntryKind: FinanceEntryAdmission] {
        let suspensions = await finance.killSwitch.activeSuspensions()
        var result: [FinanceEntryKind: FinanceEntryAdmission] = [:]
        for kind in FinanceEntryKind.allCases {
            let closure = await finance.capabilityGates.closure(for: kind.capabilityID ?? kind.rawValue)
            result[kind] = FinanceEntryAdmission.decide(kind: kind, suspensions: suspensions, closure: closure)
        }
        return result
    }

    /// Les routes du contrat (`FinanceBootstrapTests`), avec experience et
    /// gouvernance réécrites pour le scénario.
    private static func routes(countryApproved: Bool = true,
                               killSwitchGlobal: Bool = false,
                               killSwitchCountry: Bool = false) -> [String: String] {
        var routes = FinanceBootstrapTests.routes(resumeLocked: false)
        routes["GET /chat-core/experience/config"] = FinanceBootstrapTests.wrap(#"""
        { "schemaVersion": "1.0.0", "country": "BI", "allowedCountries": ["BI","RW","CA"],
          "countryApproved": \#(countryApproved), "countryLocalized": true, "currency": "BIF",
          "paymentsAllowed": true, "financialActionsLocked": false, "consultationAllowed": true,
          "safeMode": "NORMAL", "killSwitchGlobal": \#(killSwitchGlobal), "killSwitchCountry": \#(killSwitchCountry),
          "contractVersion": "1.4.0", "configGeneration": 1, "configHash": "h1" }
        """#)
        routes["GET /chat-core/governance/capabilities"] = governanceJSON(
            countryApproved: countryApproved,
            killSwitchGlobal: killSwitchGlobal,
            killSwitchCountry: killSwitchCountry
        )
        return routes
    }

    private static func governanceJSON(countryApproved: Bool,
                                       killSwitchGlobal: Bool,
                                       killSwitchCountry: Bool) -> String {
        func decision(_ key: String) -> String {
            #"{ "country": "BI", "capabilityKey": "\#(key)", "state": "GENERAL", "countryApproved": \#(countryApproved), "killSwitch": false, "allowed": true, "reason": null, "errorCode": null }"#
        }
        let capabilities = ["SEND_MONEY", "REQUEST_MONEY", "PAY_BILL", "TOP_UP"].map(decision).joined(separator: ",")
        return FinanceBootstrapTests.wrap(#"""
        { "schemaVersion": "1.0.0", "country": "BI", "countryApproved": \#(countryApproved), "allowedCountries": ["BI","RW","CA"],
          "currency": "BIF", "contractVersion": "1.4.0", "configGeneration": 1, "configHash": "h1",
          "killSwitchGlobal": \#(killSwitchGlobal), "killSwitchCountry": \#(killSwitchCountry), "safeMode": "NORMAL",
          "paymentsAllowed": true, "capabilities": [\#(capabilities)] }
        """#)
    }
}
