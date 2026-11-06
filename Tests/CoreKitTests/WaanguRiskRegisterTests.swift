//
//  WaanguRiskRegisterTests.swift
//  CoreKitTests
//

import XCTest
@testable import WaanguCoreKit

final class WaanguRiskRegisterTests: XCTestCase {

    private var register: SecurityRiskRegister { WaanguRiskRegister.register }

    /// Un registre vide est un registre absent.
    func test_registerIsNotEmpty() {
        XCTAssertFalse(register.risks.isEmpty)
    }

    /// Chaque risque doit porter un chemin d'attaque : sans lui, on ne sait ni
    /// le reproduire ni vérifier qu'il est clos.
    func test_everyRiskHasAnAttackPathAndOwner() {
        for r in register.risks {
            XCTAssertFalse(r.attackPath.isEmpty, "\(r.id) sans chemin d'attaque")
            XCTAssertFalse(r.owner.isEmpty, "\(r.id) sans propriétaire")
        }
    }

    /// Les deux écarts dont le résiduel est maximal doivent apparaître comme
    /// bloquants : ce sont ceux dont le mécanisme existe sans effet réel.
    func test_inertControlsRemainBlocking() {
        let blocking = Set(register.blocking.map(\.id))

        XCTAssertTrue(blocking.contains("G9-01"),
                      "L'épinglage sans broches doit rester bloquant.")
        XCTAssertTrue(blocking.contains("G9-02"),
                      "L'absence de rotation doit rester bloquante.")
    }

    /// Le masquage d'écran est livré et effectif : il ne doit plus bloquer.
    func test_deliveredControlIsNoLongerBlocking() {
        XCTAssertFalse(register.blocking.map(\.id).contains("G9-04"))
    }

    func test_exportProducesOneRowPerRisk() {
        let lines = register.exportCSV().split(separator: "\n")
        XCTAssertEqual(lines.count, register.risks.count + 1, "en-tête + une ligne par risque")
    }
}
