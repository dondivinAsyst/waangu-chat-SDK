//
//  DisputePrefillTests.swift
//  FeatureChatTests
//
//  Chapitre 25 — l'utilisateur ne recopie rien à la main.
//

import XCTest
@testable import WaanguFeatureChat
import WaanguCoreKit

final class DisputePrefillTests: XCTestCase {

    private let reference = FinanceFixtures.reference(version: 7)

    private func draft(
        reason: DisputeReason = .duplicateDebit,
        conversation: String? = "conv-9"
    ) -> DisputeDraft {
        .prefilled(
            from: reference,
            observedStatus: .completed,
            reason: reason,
            conversationID: conversation
        )
    }

    // MARK: - Préremplissage

    /// **L'exigence du chapitre.** Quelqu'un qui vient de subir un débit qu'il
    /// conteste est la dernière personne à qui demander de retranscrire un
    /// identifiant de corrélation à la main.
    func test_everythingKnownIsPrefilled() {
        let d = draft()
        XCTAssertEqual(d.reference, reference)
        XCTAssertEqual(d.observedStatus, .completed)
        XCTAssertEqual(d.conversationID, "conv-9")
        XCTAssertEqual(d.prefilledFieldCount, 4)
    }

    /// **La corrélation est reprise telle quelle, jamais régénérée.** Une
    /// corrélation neuve couperait le lien avec les traces de l'opération
    /// contestée — précisément ce que le support doit retrouver.
    func test_correlationIsReusedNotRegenerated() {
        XCTAssertEqual(draft().correlationID, reference.correlationID)
    }

    /// Le statut enregistré est celui que l'utilisateur **voyait**, pas celui du
    /// moment où le support ouvre le dossier.
    func test_observedStatusIsCapturedAtFilingTime() {
        let d = DisputeDraft.prefilled(
            from: reference, observedStatus: .unknown, reason: .unknownPayment
        )
        XCTAssertEqual(d.observedStatus, .unknown)
    }

    /// Le seul champ que l'utilisateur remplit reste vide au départ.
    func test_onlyDescriptionIsLeftToTheUser() {
        XCTAssertTrue(draft().description.isEmpty)
    }

    // MARK: - Consentement

    /// **Sans valeur par défaut, et à `false`.** Un consentement présumé n'en
    /// est pas un : un litige transmet l'opération et son contexte à un tiers.
    func test_consentIsNeverPresumed() {
        XCTAssertFalse(draft().sharingConsent)
        XCTAssertFalse(draft().isSubmittable)
    }

    /// Le consentement est requis **même sans preuve jointe** : le dossier
    /// lui-même part chez le partenaire.
    func test_consentRequiredEvenWithoutEvidence() {
        let described = DisputeDraft(
            reference: reference,
            reason: .wrongAmount,
            description: "Le montant débité ne correspond pas.",
            correlationID: reference.correlationID,
            observedStatus: .completed,
            sharingConsent: false,
            evidenceReferences: []
        )
        XCTAssertFalse(described.isSubmittable, "décrit mais non consenti")
    }

    func test_submittableOnceDescribedAndConsented() {
        let ready = DisputeDraft(
            reference: reference,
            reason: .wrongAmount,
            description: "Le montant débité ne correspond pas.",
            correlationID: reference.correlationID,
            observedStatus: .completed,
            sharingConsent: true
        )
        XCTAssertTrue(ready.isSubmittable)
    }

    /// Une description faite d'espaces n'est pas une description.
    func test_whitespaceDescriptionIsNotEnough() {
        let blank = DisputeDraft(
            reference: reference, reason: .fraud, description: "   \n  ",
            correlationID: reference.correlationID, observedStatus: .completed,
            sharingConsent: true
        )
        XCTAssertFalse(blank.isSubmittable)
    }

    // MARK: - Motifs

    func test_allTenReasonsExist() {
        XCTAssertEqual(DisputeReason.allCases.count, 10)
    }

    // MARK: - Fermé par défaut

    /// Le dépôt échoue sans backend — mais le **préremplissage fonctionne**,
    /// parce que c'est du calcul local sur des données déjà possédées. L'écran
    /// peut donc être construit et éprouvé avant le contrat.
    func test_prefillWorksWithoutBackend() async {
        let service = ClosedDisputeFiling()
        let d = draft()

        XCTAssertEqual(d.prefilledFieldCount, 4, "le préremplissage n'attend rien")

        let filed = await service.file(d, idempotency: FinanceFixtures.idempotency())
        guard case .failure(let error) = filed else { return XCTFail("le dépôt doit échouer") }
        XCTAssertEqual(error, .capabilityUnavailable)
    }

    /// Le client ne décide pas de ce qui constitue une preuve recevable.
    func test_noEvidenceAcceptedWithoutContract() async {
        let result = await ClosedDisputeFiling().allowedEvidence(for: .fraud)
        guard case .success(let kinds) = result else { return XCTFail("attendu") }
        XCTAssertTrue(kinds.isEmpty)
    }
}
