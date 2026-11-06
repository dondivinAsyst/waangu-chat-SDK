//
//  FieldGovernanceTests.swift
//  CoreKitTests
//
//  Bloc 9, §5 — revue de sécurité au niveau du champ.
//

import XCTest
@testable import WaanguCoreKit

/// Vérifie que le registre de champs est cohérent, et que sa détection de
/// violations attrape réellement les quatre défauts qu'elle décrit.
///
/// `FieldGovernance` portait la logique sans aucun test : une règle de
/// gouvernance non vérifiée est une intention, pas une garde.
final class FieldGovernanceTests: XCTestCase {

    private func field(
        _ name: String, sensitive: Bool = false, source: FieldSource = .backend,
        writable: Bool = false, persisted: Bool = false,
        auditable: Bool = true, redacted: Bool = true, protected: Bool = false
    ) -> FieldGovernance {
        FieldGovernance(
            fieldName: name, domain: "test", type: "String", required: false,
            sensitive: sensitive, sourceOfTruth: source, writableByClient: writable,
            persistedLocally: persisted, auditable: auditable, redactedInLogs: redacted,
            protectedStorageOnly: protected, contractVersion: "test"
        )
    }

    // MARK: - Les quatre violations

    /// Un champ dont la vérité est au backend mais que le client peut écrire
    /// laisse l'appareil décider d'une valeur financière.
    func test_backendFieldWritableByClientIsAViolation() {
        XCTAssertTrue(
            field("amount", source: .backend, writable: true)
                .violations.contains(.backendFieldWritableByClient)
        )
    }

    /// Un champ sensible non redacté finit en clair dans un journal consulté
    /// après incident — au moment précis où il ne doit pas y être.
    func test_sensitiveFieldMustBeRedacted() {
        XCTAssertTrue(
            field("pin", sensitive: true, redacted: false)
                .violations.contains(.sensitiveFieldNotRedacted)
        )
    }

    /// Un champ sensible persisté survit à la perte de l'appareil.
    func test_sensitiveFieldMustNotBePersisted() {
        XCTAssertTrue(
            field("cvv", sensitive: true, persisted: true)
                .violations.contains(.sensitiveFieldPersisted)
        )
    }

    /// Le trousseau est une persistance **acceptable** pour un champ sensible :
    /// c'est la distinction qui manquait, et qu'un registre incohérent a révélée.
    func test_protectedStorageIsNotAViolation() {
        XCTAssertFalse(
            field("refreshToken", sensitive: true, persisted: true, protected: true)
                .violations.contains(.sensitiveFieldPersisted),
            "Un champ sensible conservé au trousseau ne viole pas la règle du §5."
        )
        XCTAssertTrue(
            field("refreshToken", sensitive: true, persisted: true, protected: false)
                .violations.contains(.sensitiveFieldPersisted),
            "…mais hors stockage protégé, si."
        )
    }

    func test_complianceFieldMustBeAuditable() {
        XCTAssertTrue(
            field("amlDecision", source: .compliance, auditable: false)
                .violations.contains(.complianceFieldNotAuditable)
        )
    }

    func test_coherentFieldHasNoViolations() {
        XCTAssertTrue(field("quoteHash").isCoherent)
    }

    // MARK: - Le registre réel

    /// Le registre livré ne doit contenir aucun champ incohérent. C'est
    /// l'assertion qui compte : les tests précédents vérifient la règle, celui-ci
    /// vérifie qu'on la respecte.
    func test_registryHasNoIncoherentEntries() {
        let broken = FinancialFieldRegistry.entries.filter { !$0.isCoherent }

        XCTAssertTrue(
            broken.isEmpty,
            "Champs incohérents : " + broken.map { "\($0.fieldName)=\($0.violations)" }
                .joined(separator: ", ")
        )
    }

    /// Les champs que le §5 interdit dans les journaux doivent tous être
    /// présents **et** marqués sensibles. Un champ absent du registre n'a
    /// aucune règle attachée.
    func test_forbiddenFieldsAreRegisteredAndSensitive() {
        let names = Set(FinancialFieldRegistry.entries.map { $0.fieldName.lowercased() })

        for forbidden in ["pin", "otp", "cvv", "pan", "refreshtoken"] {
            XCTAssertTrue(names.contains(forbidden),
                          "« \(forbidden) » doit figurer au registre pour avoir une règle.")
        }

        for entry in FinancialFieldRegistry.entries
        where ["pin", "otp", "cvv", "pan"].contains(entry.fieldName.lowercased()) {
            XCTAssertTrue(entry.sensitive, "\(entry.fieldName) doit être marqué sensible")
            XCTAssertTrue(entry.redactedInLogs, "\(entry.fieldName) doit être redacté")
            XCTAssertFalse(entry.persistedLocally, "\(entry.fieldName) ne doit pas être persisté")
        }
    }

    /// Aucun champ à vérité backend n'est écrivable par le client.
    func test_noBackendTruthIsClientWritable() {
        let offenders = FinancialFieldRegistry.entries
            .filter { $0.sourceOfTruth == .backend && $0.writableByClient }

        XCTAssertTrue(offenders.isEmpty,
                      "Écrivables à tort : " + offenders.map(\.fieldName).joined(separator: ", "))
    }
}
