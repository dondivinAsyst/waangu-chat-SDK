//
//  SecurityRiskRegisterTests.swift
//  CoreKitTests
//
//  Bloc 9, chapitre 70 — preuve du registre.
//

import XCTest
@testable import WaanguCoreKit

final class SecurityRiskRegisterTests: XCTestCase {

    private func risk(_ id: String, l: Int, i: Int, residual: Int = 2,
                      accepted: Bool = false, due: Date? = nil) -> SecurityRisk {
        SecurityRisk(id: id, chapter: 70, asset: "wallet", threat: "t",
                     attackPath: "p", likelihood: l, impact: i,
                     owner: "MOBILE", residualRisk: residual,
                     dueDate: due, isAccepted: accepted)
    }

    /// La gravité se **dérive** : saisie à la main, elle diverge de la matrice
    /// dès le deuxième relecteur et le registre cesse d'être comparable.
    func test_severityIsDerivedFromLikelihoodAndImpact() {
        XCTAssertEqual(risk("a", l: 5, i: 5).severity, .critical)
        XCTAssertEqual(risk("b", l: 4, i: 4).severity, .high)
        XCTAssertEqual(risk("c", l: 2, i: 4).severity, .medium)
        XCTAssertEqual(risk("d", l: 1, i: 2).severity, .low)
    }

    /// Les entrées hors bornes sont ramenées dans 1–5 plutôt que propagées :
    /// un impact de 12 fausserait toute la matrice.
    func test_scoresAreClamped() {
        let r = SecurityRisk(id: "x", chapter: 70, asset: "a", threat: "t",
                             attackPath: "p", likelihood: 99, impact: -3,
                             owner: "MOBILE", residualRisk: 42)
        XCTAssertEqual(r.likelihood, 5)
        XCTAssertEqual(r.impact, 1)
        XCTAssertEqual(r.residualRisk, 5)
    }

    /// Un risque haut **accepté formellement** ne bloque pas ; un risque haut
    /// oublié bloque. C'est toute la distinction que demande le §34.
    func test_acceptedHighRiskDoesNotBlock() {
        let register = SecurityRiskRegister(risks: [
            risk("open", l: 5, i: 5, residual: 5),
            risk("accepted", l: 5, i: 5, residual: 5, accepted: true),
            risk("low", l: 1, i: 1)
        ])

        XCTAssertEqual(register.blocking.map(\.id), ["open"])
    }

    /// Un risque de gravité inhérente haute **dont le contrôle fonctionne** ne
    /// doit plus bloquer : sans cela, un contrôle livré n'est jamais crédité et
    /// la liste des bloquants ne diminue jamais.
    func test_effectiveControlRemovesTheBlock() {
        let register = SecurityRiskRegister(risks: [
            risk("mitigated", l: 4, i: 3, residual: 1)
        ])

        XCTAssertEqual(register.blocking.count, 0)
        XCTAssertEqual(register.risks[0].severity, .high,
                       "La gravité inhérente reste haute — c'est le résiduel qui a baissé.")
    }

    func test_overdueIgnoresAcceptedRisks() {
        let past = Date().addingTimeInterval(-86_400)
        let register = SecurityRiskRegister(risks: [
            risk("late", l: 3, i: 3, due: past),
            risk("late_but_accepted", l: 3, i: 3, accepted: true, due: past)
        ])

        XCTAssertEqual(register.overdue().map(\.id), ["late"])
    }

    /// Une virgule non échappée décale toutes les colonnes suivantes, et le
    /// tableau exporté ment sans jamais produire d'erreur.
    func test_csvEscapesSeparators() {
        let register = SecurityRiskRegister(risks: [
            SecurityRisk(id: "r1", chapter: 70, asset: "wallet, cards",
                         threat: "vol", attackPath: "p", likelihood: 3, impact: 3,
                         owner: "MOBILE", residualRisk: 2)
        ])

        let csv = register.exportCSV()
        XCTAssertTrue(csv.contains("\"wallet, cards\""),
                      "Une valeur contenant une virgule doit être entourée de guillemets.")
        XCTAssertEqual(csv.split(separator: "\n").count, 2)
    }

    func test_distributionCountsBySeverity() {
        let register = SecurityRiskRegister(risks: [
            risk("a", l: 5, i: 5), risk("b", l: 5, i: 5), risk("c", l: 1, i: 1)
        ])

        XCTAssertEqual(register.distribution[.critical], 2)
        XCTAssertEqual(register.distribution[.low], 1)
    }
}
