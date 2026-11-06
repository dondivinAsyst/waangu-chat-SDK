//
//  MoneyAndFeeCurrencyTests.swift
//  FeatureChatTests
//
//  Le montant et sa devise sont indissociables — Bloc 2 §0.4.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class MoneyTests: XCTestCase {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private let cad = CurrencyCode(code: "CAD", exponent: 2)

    /// Le défaut que `Money` existe pour rendre impossible.
    func test_additionAcrossCurrenciesIsRefused() {
        let a = Money(minorUnits: 1_000, currency: bif)
        let b = Money(minorUnits: 1_000, currency: cad)
        XCTAssertNil(a.adding(b))
        XCTAssertFalse(a.isComparable(to: b))
    }

    func test_additionWithinACurrencySucceeds() {
        let a = Money(minorUnits: 1_500, currency: cad)
        let b = Money(minorUnits: 250, currency: cad)
        XCTAssertEqual(a.adding(b)?.minorUnits, 1_750)
    }

    /// Un total faux est pire qu'un total absent, parce qu'il s'affiche.
    func test_overflowYieldsNoTotalRatherThanAWrongOne() {
        let a = Money(minorUnits: .max, currency: bif)
        let b = Money(minorUnits: 1, currency: bif)
        XCTAssertNil(a.adding(b))
    }

    /// L'exposant vient du backend : 0 et 2 doivent tous deux se présenter juste.
    func test_displayRespectsCurrencyExponent() {
        XCTAssertEqual(Money(minorUnits: 1_500, currency: cad).majorUnitsForDisplay, 15)
        XCTAssertEqual(Money(minorUnits: 1_500, currency: bif).majorUnitsForDisplay, 1_500)
    }

    func test_currencyCodeIsNormalised() {
        XCTAssertEqual(CurrencyCode(code: "bif", exponent: 0).code, "BIF")
    }

    func test_roundTripsThroughCodable() throws {
        let money = Money(minorUnits: 4_299, currency: cad)
        let data = try JSONEncoder().encode(money)
        XCTAssertEqual(try JSONDecoder().decode(Money.self, from: data), money)
    }
}

// MARK: - Frais en devise étrangère

final class FeeCurrencyTests: XCTestCase {

    private func payload(fee: Decimal?, feeCurrency: String?) -> FinancialCardPayload {
        FinancialCardPayload(
            reference: FinanceFixtures.reference(),
            status: .completed,
            amount: 1_000,
            currency: "BIF",
            feeAmount: fee,
            feeCurrency: feeCurrency,
            verification: .verified
        )
    }

    /// Cas ordinaire : frais dans la devise du montant.
    func test_totalAddsFeeInTheSameCurrency() {
        XCTAssertEqual(payload(fee: 25, feeCurrency: "BIF").totalAmount, 1_025)
        XCTAssertEqual(payload(fee: 25, feeCurrency: nil).totalAmount, 1_025)
    }

    func test_totalIsJustTheAmountWhenThereIsNoFee() {
        XCTAssertEqual(payload(fee: nil, feeCurrency: nil).totalAmount, 1_000)
    }

    /// **Le défaut corrigé.** `amount + feeAmount` additionnait deux devises
    /// parce que la charge laissait tomber `feeCurrency`.
    func test_noTotalWhenFeeIsInAnotherCurrency() {
        let crossBorder = payload(fee: 3, feeCurrency: "CAD")
        XCTAssertNil(crossBorder.totalAmount, "1 000 BIF + 3 CAD n'est pas un total")
        XCTAssertTrue(crossBorder.hasForeignCurrencyFee)
    }

    func test_sameCurrencyFeeIsNotFlaggedAsForeign() {
        XCTAssertFalse(payload(fee: 25, feeCurrency: "BIF").hasForeignCurrencyFee)
        XCTAssertFalse(payload(fee: nil, feeCurrency: "CAD").hasForeignCurrencyFee)
    }
}
