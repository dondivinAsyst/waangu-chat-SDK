import Testing
import Foundation
@testable import WaanguCoreKit

/// Incidents et réconciliation — Bloc 6, chapitre 53.
@Suite("Bloc 6 — réconciliation")
struct Bloc6ReconciliationTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func subject(_ system: TruthSystem, _ id: String = "o-1") -> ReconciliationSubject {
        ReconciliationSubject(system: system, objectID: id, objectType: "payment")
    }

    // MARK: - Ouverture d'un dossier

    /// Avec un seul système, il n'y a pas de désaccord à constater : c'est une
    /// réclamation, et elle passe par le support.
    @Test("Un dossier exige au moins deux systèmes en désaccord")
    func caseRequiresTwoSystems() {
        let single = ReconciliationRequest(kind: .debitWithoutOrder,
                                           subjects: [subject(.ledger)])
        let pair = ReconciliationRequest(kind: .debitWithoutOrder,
                                         subjects: [subject(.ledger), subject(.merchantBackend)])
        #expect(!single.isSubmittable)
        #expect(pair.isSubmittable)
    }

    /// Deux objets du **même** système ne sont pas un désaccord.
    @Test("Deux objets du même système ne suffisent pas")
    func sameSystemTwiceIsNotADiscrepancy() {
        let request = ReconciliationRequest(
            kind: .duplicateDebit,
            subjects: [subject(.ledger, "o-1"), subject(.ledger, "o-2")]
        )
        #expect(!request.isSubmittable)
    }

    @Test("Un désaccord de nature inconnue ne s'ouvre pas")
    func unknownKindIsNotSubmittable() {
        let request = ReconciliationRequest(
            kind: .unknown, subjects: [subject(.ledger), subject(.cardSystem)]
        )
        #expect(!request.isSubmittable)
    }

    // MARK: - Urgence

    /// Décide de l'urgence : un désaccord sans débit constaté peut attendre,
    /// un double débit non.
    @Test("Les désaccords avec débit sont distingués")
    func debitedFundsAreDistinguished() {
        #expect(ReconciliationKind.duplicateDebit.involvesDebitedFunds)
        #expect(ReconciliationKind.debitWithoutOrder.involvesDebitedFunds)
        #expect(ReconciliationKind.atmDispenseFailure.involvesDebitedFunds)
        #expect(ReconciliationKind.missingRefund.involvesDebitedFunds)

        #expect(!ReconciliationKind.orderWithoutDebit.involvesDebitedFunds)
        #expect(!ReconciliationKind.missingContribution.involvesDebitedFunds)
        // Un désaccord incompris n'est pas présumé urgent — ni présumé bénin :
        // il est simplement non classé, et le dossier reste ouvert.
        #expect(!ReconciliationKind.unknown.involvesDebitedFunds)
    }

    @Test("Une nature inconnue ne fait pas échouer le décodage")
    func unknownKindDegrades() throws {
        let decoded = try JSONDecoder().decode(ReconciliationKind.self,
                                               from: Data(#""NEW_CASE""#.utf8))
        #expect(decoded == .unknown)
    }

    // MARK: - Instantanés de vérité

    private func bundle(financial: Bool, merchant: Bool, card: Bool) -> TruthSnapshotBundle {
        TruthSnapshotBundle(
            caseID: "r-1", capturedAt: Date(),
            financial: financial ? FinancialTruthSnapshot(
                reference: FinancialReference(type: .payment, id: "p-1", version: 2,
                                              correlationID: CorrelationId()),
                status: .confirmed, amount: money(12_000), objectRevision: 2,
                observedAt: Date()) : nil,
            merchant: merchant ? MerchantTruthSnapshot(
                merchantID: "m-1", orderID: "o-1", merchantStateKey: "order.unpaid",
                amount: money(12_000), observedAt: Date()) : nil,
            card: card ? CardTruthSnapshot(
                cardID: "c-1", transactionID: "t-1", state: .captured,
                authorizedAmount: money(12_000), capturedAmount: money(12_000),
                observedAt: Date()) : nil
        )
    }

    /// **Un système absent n'est pas un système d'accord.** C'est un système
    /// qui n'a pas répondu, et conclure d'un silence serait la faute que ce
    /// dossier existe pour éviter.
    @Test("Un seul système qui répond ne conclut rien")
    func singleRespondentIsInconclusive() {
        #expect(!bundle(financial: true, merchant: false, card: false).isConclusive)
        #expect(!bundle(financial: false, merchant: false, card: false).isConclusive)
        #expect(bundle(financial: true, merchant: true, card: false).isConclusive)
        #expect(bundle(financial: true, merchant: true, card: true).isConclusive)
    }

    @Test("Les systèmes ayant répondu sont énumérés")
    func respondingSystemsAreListed() {
        let full = bundle(financial: true, merchant: true, card: true)
        #expect(full.respondingSystems.count == 3)
        #expect(full.respondingSystems.contains(.ledger))
        #expect(full.respondingSystems.contains(.merchantBackend))
        #expect(full.respondingSystems.contains(.cardSystem))

        let partial = bundle(financial: false, merchant: true, card: false)
        #expect(partial.respondingSystems == [.merchantBackend])
    }

    /// Les instantanés partagent **un seul** instant de capture : pris à des
    /// moments différents, ils décriraient un désaccord qui n'a jamais existé.
    @Test("Le groupe porte un instant de capture unique")
    func bundleSharesOneCaptureInstant() {
        let now = Date()
        let group = TruthSnapshotBundle(caseID: "r-1", capturedAt: now)
        #expect(group.capturedAt == now)
        #expect(!group.isConclusive)
    }

    // MARK: - Machine d'état

    /// Une escalade attend le partenaire. Revenir en revue effacerait cette
    /// attente et ferait repartir le délai à zéro.
    @Test("Une escalade ne revient pas en revue")
    func escalationDoesNotGoBack() {
        #expect(!ReconciliationStateMachine.isAllowed(from: .escalated, to: .underReview))
        #expect(!ReconciliationStateMachine.isAllowed(from: .escalated, to: .gatheringTruth))
        #expect(ReconciliationStateMachine.isAllowed(from: .escalated, to: .resolved))
    }

    @Test("Rien ne sort d'un dossier clos")
    func terminalCasesHaveNoExit() {
        #expect(ReconciliationStateMachine.allowedTransitions(from: .resolved).isEmpty)
        #expect(ReconciliationStateMachine.allowedTransitions(from: .closedNoAction).isEmpty)
        #expect(ReconciliationState.resolved.isTerminal)
        #expect(ReconciliationState.closedNoAction.isTerminal)
        #expect(!ReconciliationState.escalated.isTerminal)
    }

    /// Un examen peut redemander des pièces : c'est le seul retour en arrière
    /// légitime, et il est explicite.
    @Test("L'examen peut redemander des pièces")
    func reviewCanRequestMoreEvidence() {
        #expect(ReconciliationStateMachine.isAllowed(from: .underReview, to: .awaitingEvidence))
    }

    @Test("Un état inconnu peut se résoudre vers n'importe quel état connu")
    func unknownStateCanResolve() {
        #expect(ReconciliationStateMachine.isAllowed(from: .unknown, to: .resolved))
        #expect(ReconciliationStateMachine.isAllowed(from: .unknown, to: .escalated))
    }

    @Test("Un état inconnu ne fait pas échouer le décodage")
    func unknownStateDegrades() throws {
        let decoded = try JSONDecoder().decode(ReconciliationState.self,
                                               from: Data(#""NEW""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.isTerminal)
    }

    // MARK: - Escalade

    /// Un partenaire hors délai doit se voir : sinon un dossier dort chez
    /// quelqu'un d'autre sans que personne le relance.
    @Test("Un partenaire hors délai est détecté")
    func overduePartnerIsDetected() {
        let now = Date()
        func escalation(respondBy: Date?) -> PartnerEscalation {
            PartnerEscalation(id: "e-1", target: .cardNetwork, openedAt: now,
                              respondBy: respondBy, statusKey: "sent")
        }
        #expect(escalation(respondBy: now.addingTimeInterval(-1)).isOverdue(at: now))
        #expect(!escalation(respondBy: now.addingTimeInterval(3600)).isOverdue(at: now))
        // Sans échéance, pas de retard : l'absence de délai n'est pas un délai
        // dépassé.
        #expect(!escalation(respondBy: nil).isOverdue(at: now))
    }

    // MARK: - Dossier

    @Test("Un dossier en attente de pièces réclame l'utilisateur")
    func awaitingEvidenceRequestsUser() {
        func caseIn(_ state: ReconciliationState) -> ReconciliationCase {
            ReconciliationCase(
                id: "r-1", kind: .duplicateDebit, state: state,
                omnichannelCorrelationID: "omni-1",
                subjects: [subject(.ledger), subject(.merchantBackend)],
                openedAt: Date(), updatedAt: Date()
            )
        }
        #expect(caseIn(.awaitingEvidence).awaitsUserAction)
        #expect(!caseIn(.underReview).awaitsUserAction)
        #expect(!caseIn(.resolved).awaitsUserAction)
    }

    /// Le faisceau de pièces est une **référence**, jamais les pièces : un
    /// dossier voyage dans les journaux et les tickets, qui ne sont pas
    /// autorisés à porter un relevé bancaire.
    @Test("Les pièces sont référencées, pas embarquées")
    func evidenceIsReferencedNotEmbedded() {
        let bundleRef = EvidenceBundleReference(id: "ev-1", kindKey: "receipts",
                                                itemCount: 3, collectedAt: Date())
        #expect(bundleRef.itemCount == 3)
        #expect(bundleRef.id == "ev-1")
    }

    @Test("Une issue inconnue ne se lit pas comme un succès")
    func unknownOutcomeIsNotSuccess() throws {
        let decoded = try JSONDecoder().decode(ReconciliationOutcome.self,
                                               from: Data(#""SETTLED_SOMEHOW""#.utf8))
        #expect(decoded == .unknown)
        #expect(decoded != .corrected)
        #expect(decoded != .refunded)
    }

    // MARK: - Défaut fermé

    @Test("Le défaut fermé n'ouvre aucun dossier")
    func closedDefaultRefuses() async {
        let provider = ClosedReconciliationProvider()
        let idempotency = IdempotencyContext.new(deviceID: "device")
        let request = ReconciliationRequest(
            kind: .duplicateDebit,
            subjects: [subject(.ledger), subject(.merchantBackend)]
        )

        #expect(await provider.open(request, idempotency: idempotency).isFailureResult)
        #expect(await provider.cases(cursor: nil).isFailureResult)
        #expect(await provider.truthSnapshots(caseID: "r-1").isFailureResult)
        #expect(await provider.escalate(caseID: "r-1", to: .cardNetwork,
                                        idempotency: idempotency).isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
