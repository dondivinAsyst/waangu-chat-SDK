import Testing
import Foundation
@testable import WaanguCoreKit

/// Porte d'action et moteur de confidentialité — §22, §24.
@Suite("Bloc 6 — porte d'action et confidentialité")
struct Bloc6GovernanceTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func context(
        integrity: [String] = [], knownDevice: Bool = true,
        firstTime: Bool = false, external: Bool = false
    ) -> RiskContext {
        RiskContext(
            deviceBindingID: "d-1", integritySignals: integrity,
            isKnownDevice: knownDevice, isFirstTimeCounterparty: firstTime,
            originatedFromExternalLink: external,
            correlationID: CorrelationId(), observedAt: Date()
        )
    }

    // MARK: - Porte d'action (§22)

    /// Un silence n'autorise rien — mais ce n'est pas non plus un refus.
    /// Les confondre ferait annoncer une décision que personne n'a prise.
    @Test("Le défaut fermé ne tranche pas, il s'abstient")
    func closedGateAbstains() async {
        let gate = ClosedFinancialActionGate()
        let decision = await gate.authorize(
            action: .merchantPayment(merchantID: "m-1", amount: money(5_000)),
            context: context()
        )
        #expect(decision == .undetermined(reasonKey: "finance.gate.unavailable"))
        #expect(!decision.permitsImmediateExecution)
        // Surtout pas un refus : réessayer garde un sens.
        if case .denied = decision { Issue.record("un refus a été fabriqué") }
    }

    /// **La seule exception, et elle est motivée.** Bloquer le gel pendant une
    /// panne laisserait une carte compromise active au pire moment.
    @Test("Le gel de carte passe même sans backend")
    func freezePassesWhenGateUnavailable() async {
        let gate = ClosedFinancialActionGate()
        let decision = await gate.authorize(action: .cardFreeze(cardID: "c-1"),
                                            context: context())
        #expect(decision == .allowed)
    }

    /// Le dégel remet la carte en circulation : il n'a pas l'exemption.
    @Test("Le dégel n'a pas l'exemption du gel")
    func unfreezeHasNoExemption() async {
        let gate = ClosedFinancialActionGate()
        let decision = await gate.authorize(action: .cardUnfreeze(cardID: "c-1"),
                                            context: context())
        #expect(!decision.permitsImmediateExecution)
        #expect(!FinancialAction.cardUnfreeze(cardID: "c-1").reducesExposure)
        #expect(FinancialAction.cardFreeze(cardID: "c-1").reducesExposure)
    }

    @Test("Les actions qui déplacent de l'argent sont distinguées")
    func moneyMovingActionsAreDistinguished() {
        #expect(FinancialAction.merchantPayment(merchantID: "m", amount: money(1)).movesMoney)
        #expect(FinancialAction.largePayment(amount: money(1)).movesMoney)
        #expect(FinancialAction.collectionDisbursement(campaignID: "c", amount: money(1)).movesMoney)
        #expect(FinancialAction.internationalPayment(corridorID: "x", amount: money(1)).movesMoney)

        #expect(!FinancialAction.cardFreeze(cardID: "c").movesMoney)
        #expect(!FinancialAction.chargeback(transactionID: "t").movesMoney)
        #expect(!FinancialAction.cardProvisioning(cardID: "c").movesMoney)
    }

    /// « Refusé » et « il manque une authentification » appellent des réactions
    /// opposées. Les confondre ferait abandonner un geste réalisable.
    @Test("Un step-up requis n'est pas un refus")
    func stepUpIsNotDenial() {
        let stepUp = AuthorizationDecision.requiresStepUp(level: .biometric, reasonKey: "k")
        let denied = AuthorizationDecision.denied(reasonKey: "k")

        #expect(!stepUp.permitsImmediateExecution)
        #expect(stepUp.requiredStepUpLevel == .biometric)
        #expect(denied.requiredStepUpLevel == nil)
        #expect(stepUp != denied)
    }

    @Test("Le contexte signale ce qui mérite attention")
    func contextFlagsAttention() {
        #expect(!context().warrantsAttention)
        #expect(context(integrity: ["jailbreak"]).warrantsAttention)
        #expect(context(knownDevice: false).warrantsAttention)
        #expect(context(external: true).warrantsAttention)
    }

    @Test("Chaque action porte une clé d'audit distincte")
    func auditKeysAreDistinct() {
        let actions: [FinancialAction] = [
            .merchantPayment(merchantID: "m", amount: money(1)),
            .cardFreeze(cardID: "c"), .cardUnfreeze(cardID: "c"),
            .cardReplacement(cardID: "c", reason: .stolen),
            .cardProvisioning(cardID: "c"), .largePayment(amount: money(1)),
            .internationalPayment(corridorID: "x", amount: money(1)),
            .chargeback(transactionID: "t"), .beneficiarySensitive(beneficiaryID: "b"),
            .collectionDisbursement(campaignID: "c", amount: money(1)),
        ]
        #expect(Set(actions.map(\.auditKey)).count == actions.count)
    }

    // MARK: - Confidentialité (§24)

    private let policy = DefaultDataExposurePolicy()
    private let engine = FinancialPrivacyEngine()

    /// **Aucune finalité ne justifie un secret.** Ni le support, ni la fraude,
    /// ni le titulaire lui-même.
    @Test("Un secret ne s'expose à personne, pour aucune raison")
    func secretsNeverExposed() {
        let recipients: [Recipient] = [
            .accountHolder, .conversationParticipant(actorID: "u"),
            .merchant(merchantID: "m"), .support(caseID: "s"),
            .nativeApp(appID: "a"), .telemetry,
        ]
        for recipient in recipients {
            for purpose in [Purpose.displayToOwner, .executePayment, .resolveDispute,
                            .customerSupport, .fraudInvestigation, .diagnostics] {
                #expect(!policy.canExpose(dataClass: .secret, recipient: recipient,
                                          purpose: purpose),
                        "un secret est passé vers \(recipient) pour \(purpose)")
            }
        }
    }

    /// Sans cette borne, partager une opération dans un groupe révélerait la
    /// situation financière de celui qui la partage.
    @Test("Un participant de conversation ne voit rien au-delà du conversationnel")
    func participantSeesOnlyConversational() {
        let participant = Recipient.conversationParticipant(actorID: "u")
        #expect(policy.canExpose(dataClass: .publicInfo, recipient: participant,
                                 purpose: .displayToOwner))
        #expect(policy.canExpose(dataClass: .conversational, recipient: participant,
                                 purpose: .displayToOwner))
        #expect(!policy.canExpose(dataClass: .transactional, recipient: participant,
                                  purpose: .displayToOwner))
        #expect(!policy.canExpose(dataClass: .sensitive, recipient: participant,
                                  purpose: .displayToOwner))
    }

    /// Une trace se conserve, se copie, et se lit par des gens qui n'ont jamais
    /// consenti à voir ces données.
    @Test("La télémétrie ne reçoit que du public et du conversationnel")
    func telemetryStaysShallow() {
        #expect(policy.canExpose(dataClass: .conversational, recipient: .telemetry,
                                 purpose: .diagnostics))
        #expect(!policy.canExpose(dataClass: .transactional, recipient: .telemetry,
                                  purpose: .diagnostics))
        #expect(!policy.canExpose(dataClass: .sensitive, recipient: .telemetry,
                                  purpose: .diagnostics))
        // Même du conversationnel n'y va pas pour de l'analyse.
        #expect(!policy.canExpose(dataClass: .conversational, recipient: .telemetry,
                                  purpose: .analytics))
    }

    /// La finalité est le second terme de la règle : la même donnée se justifie
    /// pour un remboursement et pas pour de la publicité.
    @Test("La finalité change le verdict à donnée constante")
    func purposeChangesVerdict() {
        let merchant = Recipient.merchant(merchantID: "m")
        #expect(policy.canExpose(dataClass: .transactional, recipient: merchant,
                                 purpose: .executePayment))
        #expect(!policy.canExpose(dataClass: .transactional, recipient: merchant,
                                  purpose: .analytics))
    }

    @Test("Le support voit large, mais pas les secrets ni pour du diagnostic")
    func supportIsBoundedByPurpose() {
        let support = Recipient.support(caseID: "s")
        #expect(policy.canExpose(dataClass: .highlySensitive, recipient: support,
                                 purpose: .fraudInvestigation))
        #expect(!policy.canExpose(dataClass: .highlySensitive, recipient: support,
                                  purpose: .diagnostics))
        #expect(!policy.canExpose(dataClass: .secret, recipient: support,
                                  purpose: .fraudInvestigation))
    }

    @Test("Le titulaire voit ses données, sauf pour de l'analyse")
    func ownerSeesOwnData() {
        #expect(policy.canExpose(dataClass: .highlySensitive, recipient: .accountHolder,
                                 purpose: .displayToOwner))
        #expect(!policy.canExpose(dataClass: .conversational, recipient: .accountHolder,
                                  purpose: .analytics))
    }

    // MARK: - Application

    /// « Masqué » et « refusé » ne s'affichent pas pareil : les confondre ferait
    /// disparaître une ligne là où `••••` suffisait.
    @Test("Le moteur distingue exposé, masqué et retenu")
    func engineDistinguishesOutcomes() {
        let exposed = engine.expose("Boutique", dataClass: .conversational,
                                    to: .conversationParticipant(actorID: "u"),
                                    for: .displayToOwner)
        #expect(exposed == .exposed("Boutique"))

        let masked = engine.expose("4242424242424242", dataClass: .highlySensitive,
                                   to: .accountHolder, for: .displayToOwner)
        #expect(masked == .masked("•••• 4242"))

        let withheld = engine.expose("secret", dataClass: .secret,
                                     to: .accountHolder, for: .displayToOwner)
        #expect(withheld.displayValue == nil)
        if case .withheld = withheld {} else { Issue.record("un secret a été exposé") }
    }

    /// Garder quatre caractères sur cinq ne masque rien.
    @Test("Une valeur courte est masquée entièrement")
    func shortValuesFullyMasked() {
        #expect(FinancialPrivacyEngine.mask("12345") == "•••••")
        #expect(FinancialPrivacyEngine.mask("12") == "••••")
        #expect(FinancialPrivacyEngine.mask("4242424242424242") == "•••• 4242")
    }

    /// Le sens de la dégradation est tout : se tromper vers `secret` masque une
    /// donnée anodine, se tromper vers `publicInfo` expose un PAN.
    @Test("Une classe inconnue devient secret")
    func unknownClassBecomesSecret() throws {
        let decoded = try JSONDecoder().decode(FinancialDataClass.self, from: Data("99".utf8))
        #expect(decoded == .secret)
        #expect(decoded.isNeverExposable)
    }

    @Test("Les seuils de masquage et d'audit suivent la sensibilité")
    func thresholdsFollowSensitivity() {
        #expect(!FinancialDataClass.transactional.requiresMasking)
        #expect(FinancialDataClass.highlySensitive.requiresMasking)

        #expect(!FinancialDataClass.conversational.requiresAudit)
        #expect(FinancialDataClass.sensitive.requiresAudit)
        #expect(FinancialDataClass.secret.requiresAudit)
    }

    @Test("Les classes s'ordonnent par sensibilité croissante")
    func classesAreOrdered() {
        #expect(FinancialDataClass.publicInfo < FinancialDataClass.conversational)
        #expect(FinancialDataClass.transactional < FinancialDataClass.sensitive)
        #expect(FinancialDataClass.highlySensitive < FinancialDataClass.secret)
    }
}
