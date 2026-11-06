//
//  RecipientResolutionTests.swift
//  FeatureChatTests
//
//  Chapitre 10 — le bénéficiaire est établi par le backend, jamais déduit.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

// MARK: - Doublure

/// Résolveur scriptable. Enregistre les saisies reçues pour vérifier que la
/// **nature** de la saisie atteint bien le backend sans être aplatie en chemin.
actor MockRecipientResolver: RecipientResolving {

    private(set) var received: [RecipientInput] = []
    private var result: Result<ResolvedRecipient, FinanceError>

    init(result: Result<ResolvedRecipient, FinanceError> = .failure(.recipientUnresolved(reason: .undetermined))) {
        self.result = result
    }

    func setResult(_ value: Result<ResolvedRecipient, FinanceError>) { result = value }

    func resolve(_ input: RecipientInput) async -> Result<ResolvedRecipient, FinanceError> {
        received.append(input)
        return result
    }
}

enum RecipientFixtures {

    static func actor(
        type: FinancialActorType = .user,
        verification: VerificationStatus = .verified,
        permissions: Set<FinancialPermission> = [.read, .initiate]
    ) -> FinancialActor {
        FinancialActor(
            actorID: "actor-1",
            type: type,
            displayName: "Jean D.",
            verification: verification,
            jurisdiction: "BI",
            permissions: permissions
        )
    }

    static func resolved(
        verification: VerificationStatus = .verified,
        isNew: Bool = false,
        risk: RecipientRiskSignal = .none,
        coolingOffUntil: Date? = nil
    ) -> ResolvedRecipient {
        ResolvedRecipient(
            recipientID: "rcpt-1",
            actor: actor(verification: verification),
            isNewToSender: isNew,
            riskSignal: risk,
            coolingOffUntil: coolingOffUntil,
            resolvedAt: Date()
        )
    }
}

// MARK: - Fermé par défaut

final class ClosedRecipientResolverTests: XCTestCase {

    /// Tant que le contrat backend n'existe pas, aucune saisie ne devient un
    /// bénéficiaire. C'est la protection qui rend le chapitre 10 livrable sans
    /// backend : le code existe intégralement, rien n'est atteignable.
    func test_closedResolverRefusesEverything() async {
        let resolver = ClosedRecipientResolver()
        for input in [RecipientInput.phoneNumber("25761000000"),
                      .walletHandle("@jean"),
                      .merchantCode("M-42"),
                      .qrPayload("payload")] {
            let result = await resolver.resolve(input)
            guard case .failure(let error) = result else {
                return XCTFail("\(input) doit être refusée")
            }
            XCTAssertEqual(error, .recipientUnresolved(reason: .undetermined))
        }
    }

    /// **Pas `notFound`.** Dire « ce numéro n'existe pas » est une affirmation que
    /// le client n'est pas en position de faire — et qui pousse l'utilisateur à
    /// ressaisir un bénéficiaire pourtant correct.
    func test_closedResolverNeverClaimsNotFound() async {
        let result = await ClosedRecipientResolver().resolve(.phoneNumber("25761000000"))
        guard case .failure(.recipientUnresolved(let reason)) = result else {
            return XCTFail("échec attendu")
        }
        XCTAssertNotEqual(reason, .notFound)
    }
}

// MARK: - Nature de la saisie

final class RecipientInputTests: XCTestCase {

    /// La nature de la saisie doit atteindre le backend intacte. L'aplatir en
    /// `String` obligerait quelqu'un à deviner si « 25761… » est un numéro ou un
    /// code marchand — et ce quelqu'un serait le client.
    func test_inputKindSurvivesToTheResolver() async {
        let resolver = MockRecipientResolver()
        _ = await resolver.resolve(.merchantCode("M-42"))
        _ = await resolver.resolve(.phoneNumber("25761000000"))

        let received = await resolver.received
        XCTAssertEqual(received, [.merchantCode("M-42"), .phoneNumber("25761000000")])
    }
}

// MARK: - Ce que le bénéficiaire autorise

final class ResolvedRecipientPolicyTests: XCTestCase {

    func test_blockedRecipientAllowsNothing() {
        XCTAssertFalse(RecipientFixtures.resolved(risk: .blocked).allowsPayment())
    }

    /// Une vérification retirée est plus grave qu'une absence de vérification.
    func test_revokedVerificationAllowsNothing() {
        XCTAssertFalse(RecipientFixtures.resolved(verification: .revoked).allowsPayment())
    }

    func test_coolingOffBlocksPaymentUntilItExpires() {
        let future = Date().addingTimeInterval(3_600)
        let past = Date().addingTimeInterval(-3_600)
        XCTAssertFalse(RecipientFixtures.resolved(coolingOffUntil: future).allowsPayment())
        XCTAssertTrue(RecipientFixtures.resolved(coolingOffUntil: past).allowsPayment())
    }

    func test_verifiedRecipientWithNoSignalIsAllowed() {
        XCTAssertTrue(RecipientFixtures.resolved().allowsPayment())
    }

    /// L'avertissement se déclenche sur trois causes indépendantes.
    func test_warningTriggersOnNewRiskOrWeakVerification() {
        XCTAssertTrue(RecipientFixtures.resolved(isNew: true).warrantsConfirmationWarning)
        XCTAssertTrue(RecipientFixtures.resolved(risk: .unusualAmount).warrantsConfirmationWarning)
        XCTAssertTrue(RecipientFixtures.resolved(verification: .unverified).warrantsConfirmationWarning)
        XCTAssertFalse(RecipientFixtures.resolved().warrantsConfirmationWarning)
    }
}

// MARK: - Décodage défensif

final class ActorDecodingTests: XCTestCase {

    private func decode<T: Decodable>(_ type: T.Type, _ raw: String) throws -> T {
        try JSONDecoder().decode(type, from: Data("\"\(raw)\"".utf8))
    }

    /// Un statut de vérification inconnu ne devient jamais `verified`.
    func test_unknownVerificationNeverBecomesVerified() throws {
        XCTAssertEqual(try decode(VerificationStatus.self, "SOMETHING_NEW"), .unverified)
    }

    /// **Inverse de `PaymentStatus`, et volontairement.** Un signal de risque
    /// qu'on ne sait pas interpréter ne doit pas disparaître de l'interface.
    func test_unknownRiskSignalIsTreatedAsPresent() throws {
        let decoded = try decode(RecipientRiskSignal.self, "SOMETHING_NEW")
        XCTAssertNotEqual(decoded, RecipientRiskSignal.none, "un risque inconnu ne s'efface pas")
    }

    /// Un type d'acteur inconnu fait échouer le décodage plutôt que de se replier.
    /// Traiter une institution inconnue comme un particulier changerait les règles
    /// applicables — il n'y a pas de repli sûr.
    func test_unknownActorTypeFailsRatherThanFallingBack() {
        XCTAssertThrowsError(try decode(FinancialActorType.self, "SPACE_BANK"))
    }

    func test_trustBadgeOnlyForVerifiedAndOfficial() {
        XCTAssertTrue(VerificationStatus.verified.showsTrustBadge)
        XCTAssertTrue(VerificationStatus.officialAccount.showsTrustBadge)
        XCTAssertFalse(VerificationStatus.unverified.showsTrustBadge)
        XCTAssertFalse(VerificationStatus.pending.showsTrustBadge)
        XCTAssertFalse(VerificationStatus.revoked.showsTrustBadge)
    }

    /// Une permission inconnue est ignorée, jamais accordée.
    func test_unknownPermissionIsIgnoredNotGranted() {
        let decoded = FinancialPermission.decodeTolerantly(["READ", "TELEPORT", "REFUND"])
        XCTAssertEqual(decoded, [.read, .refund])
    }
}
