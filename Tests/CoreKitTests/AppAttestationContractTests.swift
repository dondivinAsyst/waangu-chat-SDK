//
//  AppAttestationContractTests.swift
//  CoreKitTests
//
//  Bloc 9, G9-03 — preuve (niveau 6) du contrat d'attestation.
//

import XCTest
@testable import WaanguCoreKit

/// Fige les invariants du §13 au niveau du contrat.
///
/// `AppAttestService` lui-même n'est pas testable ici : `DCAppAttestService`
/// rend `isSupported == false` sur simulateur, et une attestation réelle exige
/// un appareil physique **et** un backend qui la vérifie. Ce qui est vérifiable
/// sans eux, ce sont les propriétés du contrat — et ce sont précisément celles
/// qu'une implémentation ultérieure peut casser sans s'en apercevoir.
final class AppAttestationContractTests: XCTestCase {

    // MARK: - Le verdict appartient au serveur

    /// Les quatre verdicts du §12 existent et portent les valeurs de transport
    /// attendues. Un renommage silencieux ferait décoder « BLOCKED » en
    /// `nil`, et un `nil` mal traité s'interprète vite comme « pas de
    /// restriction ».
    func test_decision_wireValuesAreStable() {
        XCTAssertEqual(DeviceTrustDecision.trusted.rawValue, "TRUSTED")
        XCTAssertEqual(DeviceTrustDecision.limited.rawValue, "LIMITED")
        XCTAssertEqual(DeviceTrustDecision.stepUp.rawValue, "STEP_UP")
        XCTAssertEqual(DeviceTrustDecision.blocked.rawValue, "BLOCKED")
    }

    func test_decision_decodesFromServerPayload() throws {
        let json = Data(#"["TRUSTED","LIMITED","STEP_UP","BLOCKED"]"#.utf8)
        let decoded = try JSONDecoder().decode([DeviceTrustDecision].self, from: json)

        XCTAssertEqual(decoded, [.trusted, .limited, .stepUp, .blocked])
    }

    /// Un verdict inconnu ne doit **pas** se décoder en silence. Le §17
    /// impose fail-closed : une valeur non reconnue doit remonter une erreur,
    /// que l'appelant traduira en refus, plutôt que devenir une valeur par
    /// défaut permissive.
    func test_decision_unknownValueFailsToDecode() {
        let json = Data(#"["SOMETHING_NEW"]"#.utf8)

        XCTAssertThrowsError(
            try JSONDecoder().decode([DeviceTrustDecision].self, from: json),
            "Un verdict inconnu doit lever, pas retomber sur une valeur permissive."
        )
    }

    // MARK: - L'attestation est liée à une requête

    /// Une inscription et une assertion ne se confondent pas : le serveur les
    /// traite différemment, et confondre les deux ferait accepter une
    /// inscription là où une assertion liée à la requête est exigée.
    func test_attestation_distinguishesEnrollmentFromAssertion() {
        let enrollment = DeviceAttestation(
            keyID: "k", payload: Data([0x01]), challenge: "c", isEnrollment: true
        )
        let assertion = DeviceAttestation(
            keyID: "k", payload: Data([0x01]), challenge: "c", isEnrollment: false
        )

        XCTAssertNotEqual(enrollment, assertion)
        XCTAssertTrue(enrollment.isEnrollment)
        XCTAssertFalse(assertion.isEnrollment)
    }

    /// Deux attestations pour le même défi mais des charges différentes sont
    /// distinctes. Si l'égalité ignorait la charge, un cache mal conçu
    /// resservirait une assertion pour une autre requête — exactement le rejeu
    /// que la liaison aux données doit empêcher.
    func test_attestation_payloadParticipatesInIdentity() {
        let a = DeviceAttestation(
            keyID: "k", payload: Data([0x01]), challenge: "same", isEnrollment: false
        )
        let b = DeviceAttestation(
            keyID: "k", payload: Data([0x02]), challenge: "same", isEnrollment: false
        )

        XCTAssertNotEqual(a, b)
    }

    /// Le défi participe à l'identité : une attestation rejouée avec un autre
    /// défi ne doit pas être considérée comme la même.
    func test_attestation_challengeParticipatesInIdentity() {
        let a = DeviceAttestation(
            keyID: "k", payload: Data([0x01]), challenge: "challenge-1", isEnrollment: false
        )
        let b = DeviceAttestation(
            keyID: "k", payload: Data([0x01]), challenge: "challenge-2", isEnrollment: false
        )

        XCTAssertNotEqual(a, b)
    }

    // MARK: - Erreurs

    /// `unsupported` doit rester distinct de `notEnrolled` : le premier est un
    /// appareil non éligible (simulateur, matériel ancien), le second un
    /// appareil éligible pas encore inscrit. Les confondre ferait boucler une
    /// inscription qui ne peut pas aboutir.
    func test_errors_unsupportedIsNotNotEnrolled() {
        XCTAssertNotEqual(AppAttestationError.unsupported, .notEnrolled)
    }

    func test_errors_carryFailureReason() {
        let error = AppAttestationError.attestationFailed(reason: "refus Apple")

        guard case .attestationFailed(let reason) = error else {
            return XCTFail("cas inattendu")
        }
        XCTAssertEqual(reason, "refus Apple")
    }
}
