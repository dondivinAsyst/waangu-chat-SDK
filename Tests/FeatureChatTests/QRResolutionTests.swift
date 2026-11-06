//
//  QRResolutionTests.swift
//  FeatureChatTests
//
//  Chapitre 22 — aucun QR n'est exécutable sans résolution serveur.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

actor MockQRResolver: QRResolving {
    private(set) var receivedNonces: [String] = []
    private(set) var receivedPayloads: [String] = []
    private var result: Result<ResolvedQR, FinanceError>

    init(_ result: Result<ResolvedQR, FinanceError> = .failure(.capabilityUnavailable)) {
        self.result = result
    }

    func resolve(payload: String, nonce: String) async -> Result<ResolvedQR, FinanceError> {
        receivedPayloads.append(payload)
        receivedNonces.append(nonce)
        return result
    }
}

private enum QRFixtures {
    static func resolved(
        kind: QRKind = .merchant,
        verification: VerificationStatus = .verified,
        actions: Set<FinancialPermission> = [.read, .initiate],
        expiresAt: Date? = nil,
        external: Bool = false
    ) -> ResolvedQR {
        ResolvedQR(
            reference: FinanceFixtures.reference(),
            kind: kind,
            counterparty: FinancialActor(
                actorID: "merchant-1",
                type: .merchant,
                displayName: "Boutique Centrale",
                verification: verification
            ),
            amount: 2_500,
            currency: "BIF",
            allowedActions: actions,
            expiresAt: expiresAt,
            isExternalOrigin: external
        )
    }
}

// MARK: - La règle du chapitre

final class ClosedQRResolverTests: XCTestCase {

    /// **La règle devient vraie par conception, plus par absence de scanner.**
    /// Le scanner peut exister : sans backend, rien ne se résout, donc rien ne
    /// s'exécute.
    func test_closedResolverExecutesNothing() async {
        let result = await ClosedQRResolver().resolve(payload: "n'importe quoi", nonce: "n1")
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }
}

// MARK: - Anti-rejeu

final class QRNonceTests: XCTestCase {

    /// Deux scans ne partagent jamais un nonce, même du même QR.
    func test_everyScanGetsAFreshNonce() {
        let a = QRNonce.fresh()
        let b = QRNonce.fresh()
        XCTAssertNotEqual(a.value, b.value)
    }

    /// Le nonce doit atteindre le backend : c'est lui qui transforme un rejeu en
    /// refus explicite plutôt qu'en second débit.
    func test_nonceReachesTheBackend() async {
        let resolver = MockQRResolver()
        let nonce = QRNonce.fresh()
        _ = await resolver.resolve(payload: "payload-1", nonce: nonce.value)

        let received = await resolver.receivedNonces
        XCTAssertEqual(received, [nonce.value])
    }

    /// La charge est transmise **telle quelle**, jamais interprétée côté client.
    func test_payloadIsForwardedUninterpreted() async {
        let resolver = MockQRResolver()
        let raw = "00020101021229...falsifiable"
        _ = await resolver.resolve(payload: raw, nonce: "n")

        let received = await resolver.receivedPayloads
        XCTAssertEqual(received, [raw])
    }
}

// MARK: - Gardes

final class ResolvedQRGuardTests: XCTestCase {

    func test_validQRAllowsPayment() {
        XCTAssertTrue(QRFixtures.resolved().allowsPayment())
    }

    /// QR expiré.
    func test_expiredQRAllowsNothing() {
        let expired = QRFixtures.resolved(expiresAt: Date().addingTimeInterval(-1))
        XCTAssertTrue(expired.isExpired())
        XCTAssertFalse(expired.allowsPayment())
    }

    /// Contrepartie dont la vérification a été retirée — plus grave qu'une
    /// absence de vérification.
    func test_revokedCounterpartyAllowsNothing() {
        XCTAssertFalse(QRFixtures.resolved(verification: .revoked).allowsPayment())
    }

    /// **Les actions viennent du backend.** Un QR marchand sans `initiate`
    /// n'autorise pas un paiement, quoi qu'en dise son type.
    func test_actionsComeFromBackendNotFromKind() {
        let readOnly = QRFixtures.resolved(kind: .merchant, actions: [.read])
        XCTAssertFalse(readOnly.allowsPayment(), "le type marchand ne suffit pas")
    }

    /// Quarantaine des QR d'origine externe : ils n'ont pas été scannés par la
    /// caméra sous les yeux de l'utilisateur.
    func test_externalQRRequiresQuarantineWarning() {
        XCTAssertTrue(QRFixtures.resolved(external: true).requiresQuarantineWarning)
        XCTAssertFalse(QRFixtures.resolved(external: false).requiresQuarantineWarning)
    }

    func test_unverifiedCounterpartyAlsoWarns() {
        XCTAssertTrue(QRFixtures.resolved(verification: .unverified).requiresQuarantineWarning)
    }

    /// Un type de QR inconnu fait échouer le décodage plutôt que de se replier :
    /// rendre un QR marchand comme un QR utilisateur changerait les
    /// vérifications applicables.
    func test_unknownQRKindFailsRatherThanFallingBack() {
        XCTAssertThrowsError(
            try JSONDecoder().decode(QRKind.self, from: Data("\"CRYPTO_WORMHOLE\"".utf8))
        )
    }
}
