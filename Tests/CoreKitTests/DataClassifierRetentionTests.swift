//
//  DataClassifierRetentionTests.swift
//  CoreKitTests
//
//  Harness §22, B05 — classer une donnée ne doit pas la garder en mémoire.
//

import XCTest
@testable import WaanguCoreKit

final class DataClassifierRetentionTests: XCTestCase {

    func test_classification_isUnchanged() async {
        let classifier = DataClassifier.shared
        let pii = await classifier.classify("customer phone +25779000000")
        let financial = await classifier.classify("card balance")
        let regulated = await classifier.classify("insurance claim")
        let open = await classifier.classify("bonjour")
        XCTAssertEqual(pii, .pii)
        XCTAssertEqual(financial, .financial)
        XCTAssertEqual(regulated, .regulated)
        XCTAssertEqual(open, .public_data)
    }

    /// Aucun état stocké : un cache réintroduit (clé = la chaîne classée)
    /// ferait échouer ce test. `$defaultActor` est le stockage que le runtime
    /// ajoute à tout acteur — pas une propriété du classifieur.
    func test_classifierHoldsNoStoredState() async {
        _ = await DataClassifier.shared.classify("passport 123456789")
        let children = Mirror(reflecting: DataClassifier.shared).children
            .filter { !($0.label ?? "").hasPrefix("$") }
            .map { "\($0.label ?? "?"): \(type(of: $0.value))" }
        XCTAssertTrue(children.isEmpty, "Stored: \(children)")
    }

    /// Témoin : la même inspection voit bien un cache quand il y en a un.
    func test_inspection_detectsACacheOnAnActor() {
        actor CachingClassifier { var cache: [String: String] = ["k": "v"] }
        let stored = Mirror(reflecting: CachingClassifier()).children
            .filter { !($0.label ?? "").hasPrefix("$") }
        XCTAssertEqual(stored.map(\.label), ["cache"])
    }
}
