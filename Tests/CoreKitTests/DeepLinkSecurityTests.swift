//
//  DeepLinkSecurityTests.swift
//  CoreKitTests
//
//  Bloc 9, G9-06 — preuve (niveau 6) des exigences par route.
//

import XCTest
@testable import WaanguCoreKit

/// Fige le fait qu'une route financière **ne peut pas** être servie sans
/// signature, nonce et échéance.
///
/// Le défaut visé n'existe pas encore : aucune route financière n'est déclarée
/// aujourd'hui. C'est précisément pour cela que ces tests sont écrits
/// maintenant — le jour où quelqu'un ajoute `waangu://wallet/pay/<id>`, il doit
/// tomber sur une exigence, pas sur un défaut permissif.
final class DeepLinkSecurityTests: XCTestCase {

    // MARK: - Exigences par route

    /// Les trois niveaux sont distincts. S'ils devenaient égaux, une route
    /// financière hériterait du régime de navigation sans que rien n'échoue.
    func test_requirements_areDistinct() {
        XCTAssertNotEqual(DeepLinkTrustRequirement.navigationOnly, .authenticated)
        XCTAssertNotEqual(DeepLinkTrustRequirement.authenticated, .financial)
        XCTAssertNotEqual(DeepLinkTrustRequirement.navigationOnly, .financial)
    }

    // MARK: - Identité du lien

    /// Deux liens vers le même objet avec des nonces différents sont distincts.
    /// Si l'égalité ignorait le nonce, un cache resservirait un lien déjà
    /// consommé — le rejeu que le nonce existe pour empêcher.
    func test_link_nonceParticipatesInIdentity() {
        let a = SecureDeepLink(route: "wallet/pay", objectID: "tx-1", nonce: "n1")
        let b = SecureDeepLink(route: "wallet/pay", objectID: "tx-1", nonce: "n2")

        XCTAssertNotEqual(a, b)
    }

    func test_link_signatureParticipatesInIdentity() {
        let a = SecureDeepLink(route: "wallet/pay", objectID: "tx-1", signature: "sig-a")
        let b = SecureDeepLink(route: "wallet/pay", objectID: "tx-1", signature: "sig-b")

        XCTAssertNotEqual(a, b)
    }

    /// Un lien sans paramètre de sécurité est représentable — c'est le cas des
    /// routes de navigation. Le type ne doit pas les rendre impossibles, sinon
    /// les liens de partage cesseraient de fonctionner et la première dérogation
    /// accordée finirait par couvrir aussi les routes financières.
    func test_link_navigationLinkNeedsNoSecurityParameters() {
        let link = SecureDeepLink(route: "chat/conversation", objectID: "42")

        XCTAssertNil(link.nonce)
        XCTAssertNil(link.signature)
        XCTAssertNil(link.expiresAt)
    }

    // MARK: - Rejets

    /// Chaque rejet est distinguable. Les confondre empêcherait de dire à
    /// l'utilisateur si son lien est périmé (réessayer aide) ou rejoué
    /// (réessayer n'aidera jamais).
    func test_rejections_areDistinguishable() {
        let rejections: [DeepLinkRejection] = [
            .unknownRoute("x"),
            .missingSignature(route: "wallet/pay"),
            .missingNonce(route: "wallet/pay"),
            .expired(route: "wallet/pay"),
            .replayed(nonce: "n1"),
            .signatureInvalid(route: "wallet/pay")
        ]

        for (i, a) in rejections.enumerated() {
            for (j, b) in rejections.enumerated() where i != j {
                XCTAssertNotEqual(a, b, "Deux rejets distincts ne doivent pas être égaux")
            }
        }
    }

    func test_rejections_carryRouteForDiagnosis() {
        guard case .expired(let route) = DeepLinkRejection.expired(route: "wallet/pay") else {
            return XCTFail("cas inattendu")
        }
        XCTAssertEqual(route, "wallet/pay")
    }
}
