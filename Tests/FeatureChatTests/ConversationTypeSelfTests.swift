//
//  ConversationTypeSelfTests.swift
//  FeatureChatTests
//
//  `SELF` — le dossier personnel (INTEGRATION_CHAT_FINANCE.md §5.1.1).
//

import XCTest
import WaanguCoreKit
@testable import WaanguFeatureChat

final class ConversationTypeSelfTests: XCTestCase {

    /// Les trois orthographes que Core emploie pour le dossier personnel :
    /// `SELF` côté Hub, `FINANCIAL_SELF` dans `GET /financial/self-conversation`.
    func test_selfWireValues_mapToSelfChat() {
        for wire in ["SELF", "self", "SELF_CHAT", "FINANCIAL_SELF"] {
            XCTAssertEqual(ConversationTypeMapper.model(from: wire), .selfChat, wire)
        }
    }

    /// Avant, `SELF` tombait sur `.direct` : l'application cherchait alors un
    /// correspondant dans une conversation qui n'en a pas.
    func test_selfConversation_hasNoPeer() {
        XCTAssertFalse(ConversationTypeMapper.isDirect("SELF"))
        XCTAssertFalse(ConversationTypeModel.selfChat.hasPeer)
    }

    /// Sans pair, mais **pas** une salle : rien n'y est diffusé et il n'a pas
    /// d'identifiant de groupe.
    func test_selfConversation_isNotMultiParty() {
        XCTAssertFalse(ConversationTypeModel.selfChat.isMultiParty)
        XCTAssertTrue(ConversationTypeModel.group.isMultiParty)
        XCTAssertTrue(ConversationTypeModel.channel.isMultiParty)
    }

    /// Les autres types ne bougent pas.
    func test_knownTypes_areUnchanged() {
        XCTAssertEqual(ConversationTypeMapper.model(from: "GROUP"), .group)
        XCTAssertEqual(ConversationTypeMapper.model(from: "BROADCAST"), .channel)
        XCTAssertEqual(ConversationTypeMapper.model(from: "DIRECT"), .direct)
        // Une valeur inconnue reste un tête-à-tête, le repli d'origine.
        XCTAssertEqual(ConversationTypeMapper.model(from: "TELEPORT"), .direct)
    }

    /// **Un seul nom, un seul mot sur le fil.** Les deux énumérations désignent
    /// le dossier personnel et doivent le dire pareil : `personal` d'un côté et
    /// `selfChat` de l'autre faisait chercher un cas absent qui existait
    /// ailleurs sous un autre nom.
    func test_bothEnums_nameSelfTheSameWay() {
        XCTAssertEqual(ConversationTypeMapper.wire(from: .selfChat), "SELF")
        XCTAssertEqual(ConversationFinancialKind.selfChat.rawValue, "SELF")
        XCTAssertEqual(FinanceGovernanceMapper.conversationType(for: .selfChat), "SELF")
    }

    /// La valeur brute est explicite : un dossier personnel rendu par le
    /// serveur se décode, au lieu de retomber sur `direct`.
    func test_financialKind_decodesFromSELF() throws {
        let decoded = try JSONDecoder().decode(ConversationFinancialKind.self,
                                               from: Data("\"SELF\"".utf8))
        XCTAssertEqual(decoded, .selfChat)
    }

    /// Le portefeuille interroge le Hub sur `SELF`, et le Hub ne propose alors
    /// que les quatre parcours sans interlocuteur. Envoyer, Demander et Scanner
    /// en sont absents — ils s'adressent à quelqu'un.
    func test_selfHub_offersOnlyTheWalletFlows() {
        let actions = ["PAY_BILL", "TOP_UP", "CASH_IN", "CASH_OUT"].map {
            ResolvedActionDTO(code: $0, label: nil, intentType: nil, version: nil,
                              visible: true, enabled: true, requiresStepUp: false,
                              shortcutGroup: "WALLET", reason: nil)
        }
        let entries = FinanceGovernanceMapper.catalogEntries(from: actions)

        XCTAssertEqual(Set(entries.map(\.kind)), [.payBill, .topUp, .cashIn, .cashOut])
        XCTAssertTrue(entries.allSatisfy { $0.kind.usesPersonalFolder },
                      "Les quatre parcours du dossier personnel, et eux seuls")
    }

    /// Aller-retour : ce que le Hub attend pour chaque type.
    func test_wireRoundTrip() {
        for model in [ConversationTypeModel.direct, .group, .channel, .selfChat] {
            let wire = ConversationTypeMapper.wire(from: model)
            XCTAssertEqual(ConversationTypeMapper.model(from: wire), model, wire)
        }
        XCTAssertEqual(ConversationTypeMapper.wire(from: .selfChat), "SELF")
    }
}
