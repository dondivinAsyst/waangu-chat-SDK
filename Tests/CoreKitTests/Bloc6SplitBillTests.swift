import Testing
import Foundation
@testable import WaanguCoreKit

/// Partage d'addition — Bloc 6, chapitre 50.
///
/// Couvre le P0-5 : aucun débit sans consentement, relances bornées,
/// confidentialité des parts, et aucun calcul financier définitif côté client.
@Suite("Bloc 6 — partage d'addition")
struct Bloc6SplitBillTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func participant(
        id: String = "u-1",
        share: Int64 = 5_000,
        contributed: Int64 = 0,
        consent: SplitParticipantConsent = .pending,
        excluded: Bool = false,
        reminders: Int = 0,
        lastReminded: Date? = nil
    ) -> SplitParticipant {
        SplitParticipant(
            userID: id, displayName: "Participant", share: money(share),
            contributed: money(contributed), consent: consent, isExcluded: excluded,
            reminderCount: reminders, lastRemindedAt: lastReminded
        )
    }

    // MARK: - Consentement (P0-5)

    /// L'invariant du §50 : un seul état autorise un mouvement d'argent.
    @Test("Seul un consentement accepté autorise un débit")
    func onlyAcceptedCanBeDebited() {
        #expect(SplitParticipantConsent.accepted.canBeDebited)
        #expect(!SplitParticipantConsent.pending.canBeDebited)
        #expect(!SplitParticipantConsent.declined.canBeDebited)
        #expect(!SplitParticipantConsent.expired.canBeDebited)
        #expect(!SplitParticipantConsent.unknown.canBeDebited)
    }

    /// Un consentement d'un état que ce client ne connaît pas est traité comme
    /// non consenti. L'inverse débiterait sur une valeur incomprise.
    @Test("Un consentement inconnu ne débite pas")
    func unknownConsentDoesNotDebit() throws {
        let decoded = try JSONDecoder().decode(SplitParticipantConsent.self,
                                               from: Data(#""SOMETHING""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.canBeDebited)
    }

    // MARK: - Reste dû

    @Test("Le reste dû est la différence entre la part et le versé")
    func outstandingIsShareMinusContributed() {
        #expect(participant(share: 5_000, contributed: 2_000).outstanding?.minorUnits == 3_000)
        #expect(participant(share: 5_000, contributed: 5_000).outstanding?.minorUnits == 0)
        // Jamais négatif : un versement en trop n'est pas une dette du groupe.
        #expect(participant(share: 5_000, contributed: 9_000).outstanding?.minorUnits == 0)
    }

    @Test("Un participant exclu ne doit rien")
    func excludedOwesNothing() {
        #expect(!participant(share: 5_000, excluded: true).hasOutstandingAmount)
        #expect(participant(share: 5_000, excluded: false).hasOutstandingAmount)
    }

    // MARK: - Relances bornées

    private let policy = SplitReminderPolicy(maxPerParticipant: 3, minimumInterval: 86_400)

    /// Le §50 interdit les relances illimitées : sans borne, un partage devient
    /// un canal que le destinataire ne peut pas couper.
    @Test("Le plafond de relances est respecté")
    func reminderCapIsEnforced() {
        #expect(policy.allowsReminder(for: participant(reminders: 2)))
        #expect(!policy.allowsReminder(for: participant(reminders: 3)))
        #expect(!policy.allowsReminder(for: participant(reminders: 9)))
    }

    @Test("Deux relances rapprochées sont refusées")
    func reminderIntervalIsEnforced() {
        let now = Date()
        #expect(!policy.allowsReminder(for: participant(lastReminded: now.addingTimeInterval(-3_600)),
                                       at: now))
        #expect(policy.allowsReminder(for: participant(lastReminded: now.addingTimeInterval(-90_000)),
                                      at: now))
    }

    /// Relancer quelqu'un qui a refusé et ne doit rien n'a pas d'objet.
    @Test("On ne relance pas un participant à jour")
    func noReminderForSettledParticipant() {
        let settled = participant(share: 5_000, contributed: 5_000, consent: .accepted)
        #expect(!policy.allowsReminder(for: settled))

        let declined = participant(share: 5_000, contributed: 0, consent: .declined)
        // Il reste un montant dû, donc la relance garde un sens tant que
        // l'organisateur ne l'a pas exclu — c'est au backend de trancher.
        #expect(policy.allowsReminder(for: declined))
    }

    // MARK: - Confidentialité

    /// Sans portée, participer à un dîner révèle à tout le groupe qui a payé,
    /// qui traîne, et qui a refusé.
    @Test("La portée restreinte masque les parts des autres")
    func ownShareOnlyHidesOthers() {
        let scope = SplitPrivacyScope.ownShareOnly
        #expect(!scope.canSeeOtherShares(isOrganizer: false))
        #expect(!scope.canSeeAggregate(isOrganizer: false))
        // L'organisateur voit tout : c'est lui qui doit relancer.
        #expect(scope.canSeeOtherShares(isOrganizer: true))
        #expect(scope.canSeeAggregate(isOrganizer: true))
    }

    @Test("La portée agrégée montre l'avancement sans le détail")
    func aggregateShowsProgressOnly() {
        let scope = SplitPrivacyScope.aggregateOnly
        #expect(scope.canSeeAggregate(isOrganizer: false))
        #expect(!scope.canSeeOtherShares(isOrganizer: false))
    }

    /// Une portée inconnue retombe sur la plus restrictive : l'inverse
    /// exposerait des montants qu'une version plus récente masquait.
    @Test("Une portée inconnue retombe sur la plus restrictive")
    func unknownScopeFallsBackToStrictest() throws {
        let decoded = try JSONDecoder().decode(SplitPrivacyScope.self,
                                               from: Data(#""NEW_SCOPE""#.utf8))
        #expect(decoded == .ownShareOnly)
        #expect(!decoded.canSeeOtherShares(isOrganizer: false))
    }

    // MARK: - Brouillon

    private func draft(strategy: SplitStrategy, participants: [String] = ["u-1", "u-2"]) -> SplitBillDraft {
        SplitBillDraft(labelKey: "Dîner", total: money(9_000),
                       participantIDs: participants, strategy: strategy,
                       privacyScope: .ownShareOnly)
    }

    @Test("Un partage sans participant ou sans montant est mal formé")
    func draftRequiresParticipantsAndAmount() {
        #expect(draft(strategy: .equal).isSubmittable)
        #expect(!draft(strategy: .equal, participants: []).isSubmittable)

        let zero = SplitBillDraft(labelKey: "Dîner", total: money(0),
                                  participantIDs: ["u-1"], strategy: .equal,
                                  privacyScope: .ownShareOnly)
        #expect(!zero.isSubmittable)
    }

    /// Une répartition personnalisée doit couvrir chaque participant nommé.
    @Test("Une répartition personnalisée exige une valeur par participant")
    func customStrategyNeedsEveryParticipant() {
        #expect(draft(strategy: .custom(["u-1": 5_000, "u-2": 4_000])).isSubmittable)
        #expect(!draft(strategy: .custom(["u-1": 9_000])).isSubmittable)
        #expect(!draft(strategy: .custom(["u-1": 5_000, "u-9": 4_000])).isSubmittable)
    }

    /// Un poids négatif rendrait une part négative.
    @Test("Un poids nul ou négatif est refusé")
    func nonPositiveWeightsRejected() {
        #expect(!draft(strategy: .proportional(["u-1": 2, "u-2": 0])).isSubmittable)
        #expect(!draft(strategy: .proportional(["u-1": 2, "u-2": -1])).isSubmittable)
        #expect(draft(strategy: .proportional(["u-1": 2, "u-2": 1])).isSubmittable)
    }

    /// La somme déclarée sert à **prévenir** l'organisateur, pas à débiter.
    @Test("La somme déclarée n'existe que pour la répartition explicite")
    func declaredSumOnlyForExplicitStrategies() {
        #expect(SplitStrategy.equal.declaredSum == nil)
        #expect(SplitStrategy.custom(["u-1": 5_000, "u-2": 4_000]).declaredSum == 9_000)
        #expect(SplitStrategy.proportional(["u-1": 2, "u-2": 1]).declaredSum == 3)
    }

    // MARK: - État du règlement

    @Test("Seuls les partages ouverts acceptent des contributions")
    func onlyOpenAcceptsContributions() {
        #expect(SplitSettlementState.open.acceptsContributions)
        #expect(SplitSettlementState.partiallySettled.acceptsContributions)
        #expect(!SplitSettlementState.settled.acceptsContributions)
        #expect(!SplitSettlementState.closed.acceptsContributions)
        #expect(!SplitSettlementState.unknown.acceptsContributions)
    }

    // MARK: - Aucun calcul définitif côté client

    /// Le reste se déduit de deux montants **serveur**. Recomposer `collected`
    /// depuis la liste des participants produirait un second chiffre.
    @Test("Le reste à collecter vient des totaux serveur")
    func remainingComesFromServerTotals() {
        let split = SplitBill(
            id: "s-1", labelKey: "Dîner", organizerID: "u-1",
            total: money(9_000), collected: money(4_000),
            participants: [participant(id: "u-1"), participant(id: "u-2")],
            strategy: .equal, state: .partiallySettled,
            privacyScope: .ownShareOnly,
            reminderPolicy: policy, createdAt: Date(), updatedAt: Date()
        )
        #expect(split.remaining?.minorUnits == 5_000)
        #expect(split.isOrganizer("u-1"))
        #expect(!split.isOrganizer("u-2"))
        #expect(split.participant("u-2") != nil)
        #expect(split.participant("u-9") == nil)
    }

    // MARK: - Défaut fermé

    /// Le défaut ne tient **aucun état local** : un partage mémorisé côté
    /// client est un registre financier que le client n'a pas le droit d'être.
    @Test("Le défaut fermé refuse tout et ne mémorise rien")
    func closedDefaultRefuses() async {
        let manager = ClosedSplitBillManager()
        let idempotency = IdempotencyContext.new(deviceID: "device")

        #expect(await manager.splits(cursor: nil).isFailureResult)
        #expect(await manager.create(draft(strategy: .equal), idempotency: idempotency).isFailureResult)
        #expect(await manager.respond(splitID: "s-1", response: .accept,
                                      idempotency: idempotency).isFailureResult)
        #expect(await manager.contribute(splitID: "s-1", amount: money(1_000),
                                         idempotency: idempotency, stepUp: nil).isFailureResult)
        // Le second appel échoue comme le premier : aucun état n'a été retenu.
        #expect(await manager.splits(cursor: nil).isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
