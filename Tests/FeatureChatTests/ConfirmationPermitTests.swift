//
//  ConfirmationPermitTests.swift
//  FeatureChatTests
//
//  Chapitre 13 — les scénarios obligatoires 11 à 16 du Bloc 2.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

private enum SnapshotFixtures {

    static func make(
        amount: Decimal = 5_000,
        currency: String = "BIF",
        fee: Decimal? = 25,
        feeCurrency: String? = "BIF",
        rate: Decimal? = nil,
        recipientID: String = "rcpt-1",
        verification: VerificationStatus = .verified,
        compliance: ComplianceState = .approved,
        version: Int = 3,
        capturedAt: Date = Date(timeIntervalSince1970: 1_000)
    ) -> ConfirmationSnapshot {
        ConfirmationSnapshot(
            reference: FinanceFixtures.reference(version: version),
            amount: amount,
            currency: currency,
            feeAmount: fee,
            feeCurrency: feeCurrency,
            exchangeRate: rate,
            recipientID: recipientID,
            recipientVerification: verification,
            complianceState: compliance,
            capturedAt: capturedAt
        )
    }
}

// MARK: - Détection de divergence — scénarios 13 à 16

final class ConfirmationSnapshotTests: XCTestCase {

    func test_identicalConditionsProduceNoDivergence() {
        let a = SnapshotFixtures.make()
        XCTAssertTrue(a.matches(SnapshotFixtures.make()))
        XCTAssertEqual(a.divergences(from: SnapshotFixtures.make()), [])
    }

    /// Scénario 13 — bénéficiaire modifié entre l'aperçu et la confirmation.
    func test_recipientChangeIsDetected() {
        let before = SnapshotFixtures.make()
        let after = SnapshotFixtures.make(recipientID: "rcpt-2")
        XCTAssertEqual(before.divergences(from: after), [.recipient])
    }

    /// Scénario 14 — frais modifiés.
    func test_feeChangeIsDetected() {
        let before = SnapshotFixtures.make(fee: 25)
        let after = SnapshotFixtures.make(fee: 400)
        XCTAssertEqual(before.divergences(from: after), [.fee])
    }

    /// Scénario 15 — taux de change modifié.
    func test_exchangeRateChangeIsDetected() {
        let before = SnapshotFixtures.make(rate: 1.0)
        let after = SnapshotFixtures.make(rate: 1.3)
        XCTAssertEqual(before.divergences(from: after), [.exchangeRate])
    }

    /// Scénario 16 — la conformité passe de `approved` à `approvalRequired`.
    func test_complianceChangeIsDetected() {
        let before = SnapshotFixtures.make(compliance: .approved)
        let after = SnapshotFixtures.make(compliance: .approvalRequired)
        XCTAssertEqual(before.divergences(from: after), [.compliance])
    }

    /// Une vérification qui se dégrade entre l'aperçu et la confirmation compte
    /// autant qu'un changement de bénéficiaire.
    func test_verificationDowngradeIsDetected() {
        let before = SnapshotFixtures.make(verification: .verified)
        let after = SnapshotFixtures.make(verification: .revoked)
        XCTAssertEqual(before.divergences(from: after), [.recipientVerification])
    }

    /// Une révision plus récente n'est pas en soi une divergence décisionnelle :
    /// le backend en produit pour des raisons qui ne changent rien pour
    /// l'utilisateur. C'est le contenu qui compte, pas le compteur.
    func test_versionBumpAloneIsNotADivergence() {
        let before = SnapshotFixtures.make(version: 3)
        let after = SnapshotFixtures.make(version: 9)
        XCTAssertEqual(before.divergences(from: after), [])
    }

    /// Un rafraîchissement portant sur un **autre objet** n'est pas une
    /// divergence de conditions : c'est un défaut de dispatch, et l'exécuter
    /// paierait autre chose que ce qui a été montré.
    func test_differentObjectIsFlaggedAsIdentityDivergence() {
        let before = SnapshotFixtures.make()
        let other = ConfirmationSnapshot(
            reference: FinanceFixtures.reference(id: "autre-objet", version: 3),
            amount: 5_000, currency: "BIF",
            feeAmount: 25, feeCurrency: "BIF", exchangeRate: nil,
            recipientID: "rcpt-1", recipientVerification: .verified,
            complianceState: .approved, capturedAt: Date(timeIntervalSince1970: 1_000)
        )
        XCTAssertTrue(before.divergences(from: other).contains(.objectIdentity))
    }

    func test_multipleDivergencesAreAllReported() {
        let before = SnapshotFixtures.make(amount: 5_000, fee: 25)
        let after = SnapshotFixtures.make(amount: 9_000, fee: 400)
        let fields = before.divergences(from: after)
        XCTAssertTrue(fields.contains(.amount))
        XCTAssertTrue(fields.contains(.fee))
    }
}

// MARK: - Empreinte

final class DecisionHashTests: XCTestCase {

    /// Deux captures des mêmes conditions à des instants différents doivent
    /// produire la même empreinte — sinon le contrôle serait inopérant, chaque
    /// empreinte étant unique.
    func test_hashIgnoresCaptureTime() {
        let a = SnapshotFixtures.make(capturedAt: Date(timeIntervalSince1970: 1_000))
        let b = SnapshotFixtures.make(capturedAt: Date(timeIntervalSince1970: 9_999))
        XCTAssertEqual(a.decisionHash, b.decisionHash)
    }

    func test_hashChangesWithEveryDecisionField() {
        let base = SnapshotFixtures.make().decisionHash
        XCTAssertNotEqual(base, SnapshotFixtures.make(amount: 9_000).decisionHash)
        XCTAssertNotEqual(base, SnapshotFixtures.make(fee: 400).decisionHash)
        XCTAssertNotEqual(base, SnapshotFixtures.make(rate: 2).decisionHash)
        XCTAssertNotEqual(base, SnapshotFixtures.make(recipientID: "rcpt-2").decisionHash)
        XCTAssertNotEqual(base, SnapshotFixtures.make(verification: .unverified).decisionHash)
        XCTAssertNotEqual(base, SnapshotFixtures.make(compliance: .denied).decisionHash)
    }

    /// La révision ne fait pas partie de l'empreinte, comme elle ne fait pas
    /// partie des divergences.
    func test_hashIgnoresVersion() {
        XCTAssertEqual(
            SnapshotFixtures.make(version: 3).decisionHash,
            SnapshotFixtures.make(version: 42).decisionHash
        )
    }
}

// MARK: - Permis — scénarios 11 et 12

final class ExecutionPermitTests: XCTestCase {

    private func permit(
        for snapshot: ConfirmationSnapshot,
        expiresIn: TimeInterval = 300
    ) -> ExecutionPermit {
        ExecutionPermit(
            permitID: "permit-1",
            objectID: snapshot.reference.id,
            snapshotHash: snapshot.decisionHash,
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    func test_permitAuthorisesTheSnapshotItWasIssuedFor() {
        let snapshot = SnapshotFixtures.make()
        XCTAssertTrue(permit(for: snapshot).authorizes(snapshot))
    }

    /// Scénario 11 — permis expiré.
    func test_expiredPermitAuthorisesNothing() {
        let snapshot = SnapshotFixtures.make()
        let stale = permit(for: snapshot, expiresIn: -1)
        XCTAssertFalse(stale.authorizes(snapshot))
        XCTAssertTrue(stale.isExpired())
    }

    /// **Le point du chapitre 13.** Un permis valide dans le temps n'autorise
    /// toujours rien si les conditions ont changé — c'est ce que la clé
    /// d'idempotence, seule, ne sait pas empêcher.
    func test_validPermitStillRefusesChangedConditions() {
        let agreed = SnapshotFixtures.make(fee: 25)
        let issued = permit(for: agreed)
        let changed = SnapshotFixtures.make(fee: 400)

        XCTAssertFalse(issued.isExpired(), "le permis est encore valide dans le temps")
        XCTAssertFalse(issued.authorizes(changed), "mais pas pour ces conditions-là")
    }

    /// Un permis n'est pas transférable d'un objet à un autre.
    func test_permitIsBoundToItsObject() {
        let snapshot = SnapshotFixtures.make()
        let foreign = ExecutionPermit(
            permitID: "permit-1",
            objectID: "autre-objet",
            snapshotHash: snapshot.decisionHash,
            issuedAt: Date(),
            expiresAt: Date().addingTimeInterval(300)
        )
        XCTAssertFalse(foreign.authorizes(snapshot))
    }

    /// Scénario 12 — un permis déjà consommé rend l'issue ambiguë : l'opération
    /// existe peut-être. On réconcilie, on ne rejoue pas.
    func test_consumedPermitRequiresReconciliationNotRetry() {
        let error = FinanceError.executionPermitConsumed
        XCTAssertFalse(error.isSafeToRetry)
        XCTAssertTrue(error.requiresReconciliation)
    }

    func test_expiredPermitIsNotBlindlyRetryable() {
        XCTAssertFalse(FinanceError.executionPermitExpired.isSafeToRetry)
    }
}

// MARK: - Fermé par défaut

final class ClosedExecutionPermitTests: XCTestCase {

    /// Sans contrat backend, aucun permis n'est émis — donc aucune confirmation
    /// n'aboutit. Le code du chapitre 13 existe intégralement et reste inerte.
    func test_closedIssuerEmitsNothing() async {
        let issuer = ClosedExecutionPermitIssuer()
        let result = await issuer.issue(
            for: SnapshotFixtures.make(),
            idempotency: FinanceFixtures.idempotency(),
            stepUp: nil
        )
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }

        // Ni expiré, ni consommé : l'opération n'a jamais pu commencer, et le dire
        // autrement enverrait l'utilisateur reprendre un parcours inexistant.
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    func test_closedIssuerConsumesNothing() async {
        let result = await ClosedExecutionPermitIssuer().consume(
            ExecutionPermit(
                permitID: "p", objectID: "o", snapshotHash: "h",
                issuedAt: Date(), expiresAt: Date().addingTimeInterval(60)
            )
        )
        guard case .failure(let error) = result else { return XCTFail("doit refuser") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }
}

// MARK: - ComplianceState

final class ComplianceStateTests: XCTestCase {

    /// Fermé par défaut : seuls `approved` et `notApplicable` laissent passer.
    func test_onlyApprovedStatesAllowExecution() {
        XCTAssertTrue(ComplianceState.approved.allowsExecution)
        XCTAssertTrue(ComplianceState.notApplicable.allowsExecution)
        for blocked in [ComplianceState.pending, .approvalRequired, .denied, .blocked] {
            XCTAssertFalse(blocked.allowsExecution, "\(blocked) ne doit pas laisser exécuter")
        }
    }

    /// Un état de conformité inconnu n'est jamais `approved`.
    func test_unknownComplianceStateIsNeverApproved() throws {
        let decoded = try JSONDecoder().decode(
            ComplianceState.self,
            from: Data("\"SOMETHING_NEW\"".utf8)
        )
        XCTAssertFalse(decoded.allowsExecution)
    }
}
