//
//  TokenRotationContractTests.swift
//  CoreKitTests
//
//  Bloc 9, §9 — preuve du contrat de rotation.
//

import XCTest
@testable import WaanguCoreKit

/// Fige la règle que le vrai IAM devra respecter à l'identique.
final class TokenRotationContractTests: XCTestCase {

    /// La famille est portée par le couple : sans elle, une révocation ne peut
    /// atteindre que le jeton présenté, pas la copie détenue par l'attaquant.
    func test_rotatedTokens_carryFamily() {
        let t = RotatedTokens(accessToken: "a", refreshToken: "r",
                              familyID: "fam-1", accessExpiresAt: Date())
        XCTAssertEqual(t.familyID, "fam-1")
    }

    /// Une réutilisation détectée doit **nommer la famille** : c'est ce qu'on
    /// révoque, et une erreur qui ne la porte pas rend la révocation impossible.
    func test_reuseDetected_namesTheFamilyToRevoke() {
        guard case .reuseDetected(let family) =
                TokenRotationError.reuseDetected(familyID: "fam-9") else {
            return XCTFail("cas inattendu")
        }
        XCTAssertEqual(family, "fam-9")
    }

    /// Réutilisation et famille révoquée sont deux états distincts : le premier
    /// est une alerte de sécurité, le second sa conséquence. Les confondre
    /// empêcherait de distinguer une attaque d'une déconnexion volontaire.
    func test_reuseIsDistinctFromRevoked() {
        XCTAssertNotEqual(
            TokenRotationError.reuseDetected(familyID: "f"),
            TokenRotationError.familyRevoked(familyID: "f")
        )
    }

    /// Une autorité absente **refuse** : elle ne rend jamais un couple de jetons
    /// par défaut, sans quoi l'absence de service vaudrait authentification.
    func test_unavailableAuthority_refuses() async {
        let result = await UnavailableTokenRotation().rotate(refreshToken: "r")

        guard case .failure(let error) = result else {
            return XCTFail("Une autorité absente ne doit pas délivrer de jetons")
        }
        XCTAssertEqual(error, .unreachable)
    }

    /// Même règle pour l'attestation : pas de vérificateur, pas de confiance.
    func test_unavailableVerifier_refusesRatherThanTrusting() async {
        let attestation = DeviceAttestation(keyID: "k", payload: Data([1]),
                                            challenge: "c", isEnrollment: false)
        let result = await UnavailableAttestationVerifier()
            .verify(attestation, expectedChallenge: "c")

        guard case .failure(let error) = result else {
            return XCTFail("Un vérificateur absent ne doit pas accorder la confiance")
        }
        XCTAssertEqual(error, .unreachable)
    }

    /// Un défi qui ne correspond pas est un rejeu : l'erreur doit le dire
    /// distinctement d'une charge malformée, car la réponse diffère.
    func test_challengeMismatchIsDistinctFromMalformed() {
        XCTAssertNotEqual(
            AttestationVerificationError.challengeMismatch,
            AttestationVerificationError.malformed
        )
    }
}
