//
//  Bloc10DesignSystemTests.swift
//  FeatureChatTests
//
//  Bloc 10, chapitre 79 — design system des cartes financières.
//

import XCTest
import WaanguCoreKit
import WaanguSharedUI
@testable import WaanguFeatureChat

final class Bloc10DesignSystemTests: XCTestCase {

    /// Le design system ne doit jamais rendre plus optimiste que le traitement :
    /// seule une réussite **vérifiée** devient `.confirmed`.
    func test_onlySettledPresentation_becomesConfirmed() {
        for presentation in FinancialCardPresentation.allCases {
            XCTAssertEqual(presentation.visualState.announcesSuccess, presentation.announcesSuccess,
                           "\(presentation) : le badge et le traitement divergent sur la réussite")
        }
    }

    func test_completedButUnverifiedPayment_isNotShownAsConfirmed() {
        let payload = FinancialCardPayload(
            reference: FinanceFixtures.reference(), status: .completed,
            amount: 25_000, currency: "BIF", verification: .unverified
        )
        XCTAssertNotEqual(payload.presentation.visualState, .confirmed)
        XCTAssertEqual(payload.presentation.tone, .secondary, "Une vérification en cours reste neutre")
    }

    /// Texte + icône + couleur : aucun traitement ne peut s'afficher sans libellé
    /// ni symbole — la couleur seule ne dit rien à VoiceOver ni à un daltonien.
    func test_everyPresentation_hasALabelAndASymbol() {
        for presentation in FinancialCardPresentation.allCases {
            XCTAssertFalse(presentation.label.trimmingCharacters(in: .whitespaces).isEmpty, "\(presentation)")
            XCTAssertFalse(presentation.symbol.isEmpty, "\(presentation)")
        }
    }

    /// Les états d'échec et de blocage ne partagent jamais le ton de la réussite.
    func test_failureStates_neverUseTheSuccessTone() {
        let negative: [FinanceVisualState] = [.failed, .rejected, .blocked, .expired, .offline, .pending]
        for state in negative {
            XCTAssertNotEqual(state.tone, .success, "\(state)")
        }
        XCTAssertEqual(FinanceVisualState.allCases.filter { $0.tone == .success }, [.confirmed])
    }

    /// Le franc burundais n'a pas de décimales : la carte les affichait quand même.
    func test_cardAmount_respectsCurrencyExponent() throws {
        let payload = FinancialCardPayload(
            reference: FinanceFixtures.reference(), status: .completed,
            amount: try XCTUnwrap(Decimal(string: "1000.5")), currency: "BIF", verification: .verified
        )
        XCTAssertFalse(payload.formattedAmount.contains(",5"), payload.formattedAmount)
        XCTAssertFalse(payload.formattedAmount.contains(".5"), payload.formattedAmount)
        XCTAssertEqual(payload.formattedAmount, AmountEntry.format(payload.amount, "BIF"))
    }
}
