import Testing
import Foundation
@testable import WaanguCoreKit

/// Cartes et transactions cartes — Bloc 6, chapitres 48 et 49.
///
/// Couvre le P0-6 : les cartes ne doivent jamais se réduire à
/// `success / failed`, et `AUTHORIZED ≠ CAPTURED ≠ SETTLED`.
@Suite("Bloc 6 — cartes")
struct Bloc6CardTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func transaction(
        state: CardTransactionState,
        authorized: Int64 = 15_000,
        captured: Int64? = nil,
        settled: Int64? = nil
    ) -> CardTransaction {
        CardTransaction(
            id: "t-1", cardID: "c-1",
            reference: FinancialReference(type: .payment, id: "p-1", version: 1,
                                          correlationID: CorrelationId()),
            state: state, authorizedAmount: money(authorized),
            capturedAmount: captured.map(money), settledAmount: settled.map(money),
            merchantNameKey: "Station", occurredAt: Date(), updatedAt: Date()
        )
    }

    // MARK: - Les trois temps (P0-6)

    /// Le cas qui donne son sens au chapitre : la station réserve 150,
    /// capture 40. Afficher l'autorisation comme un débit ferait attendre un
    /// prélèvement qui n'aura jamais lieu.
    @Test("Le montant affiché suit le plus définitif des trois")
    func displayedAmountFollowsMostFinal() {
        #expect(transaction(state: .authorized).displayedAmount.authority == .authorized)
        #expect(transaction(state: .authorized).displayedAmount.amount.minorUnits == 15_000)

        let captured = transaction(state: .captured, captured: 4_000)
        #expect(captured.displayedAmount.authority == .captured)
        #expect(captured.displayedAmount.amount.minorUnits == 4_000)

        let settled = transaction(state: .settled, captured: 4_000, settled: 4_000)
        #expect(settled.displayedAmount.authority == .settled)
    }

    /// Une autorisation **n'a pas déplacé d'argent**. C'est toute la distinction
    /// que le chapitre 49 interdit d'effacer.
    @Test("Une autorisation n'a pas déplacé d'argent")
    func authorizationHasNotMovedMoney() {
        #expect(!CardTransactionState.authorized.hasMovedMoney)
        #expect(!CardTransactionState.pending.hasMovedMoney)
        #expect(!CardTransactionState.reversed.hasMovedMoney)
        #expect(!CardTransactionState.declined.hasMovedMoney)

        #expect(CardTransactionState.captured.hasMovedMoney)
        #expect(CardTransactionState.settled.hasMovedMoney)
        #expect(CardTransactionState.chargedBack.hasMovedMoney)
    }

    /// Contester une réservation n'a pas de sens : rien n'a été débité, et
    /// l'annuler relève du marchand, pas du réseau.
    @Test("Une autorisation seule n'est pas contestable")
    func authorizationIsNotDisputable() {
        #expect(!transaction(state: .authorized).isDisputable())
        #expect(transaction(state: .captured, captured: 4_000).isDisputable())
        #expect(transaction(state: .settled, settled: 4_000).isDisputable())
    }

    // MARK: - Machine d'état

    /// Une autorisation ne va **jamais** directement au règlement : le
    /// règlement suppose une capture.
    @Test("Une autorisation ne peut pas se régler sans capture")
    func authorizedCannotSettleDirectly() {
        #expect(!CardTransactionStateMachine.isAllowed(from: .authorized, to: .settled))
        #expect(CardTransactionStateMachine.isAllowed(from: .authorized, to: .captured))
        #expect(CardTransactionStateMachine.isAllowed(from: .captured, to: .settled))
    }

    @Test("Rien ne sort d'un état terminal")
    func terminalStatesHaveNoExit() {
        for terminal in [CardTransactionState.declined, .reversed, .expired, .chargedBack] {
            #expect(CardTransactionStateMachine.allowedTransitions(from: terminal).isEmpty)
            #expect(terminal.isTerminal)
        }
    }

    /// Un message en retard ne doit pas faire reculer l'affichage.
    @Test("Une transition en arrière est interdite")
    func backwardTransitionForbidden() {
        #expect(!CardTransactionStateMachine.isAllowed(from: .settled, to: .authorized))
        #expect(!CardTransactionStateMachine.isAllowed(from: .captured, to: .pending))

        if case .forbidden(let reason) =
            CardTransactionStateMachine.verdict(from: .settled, to: .authorized) {
            #expect(reason.contains("SETTLED"))
        } else {
            Issue.record("une régression a été autorisée")
        }
    }

    /// Un état identique est toujours permis : les messages se répètent.
    @Test("Rester dans le même état est permis")
    func sameStateIsAllowed() {
        #expect(CardTransactionStateMachine.isAllowed(from: .captured, to: .captured))
        #expect(CardTransactionStateMachine.verdict(from: .captured, to: .captured) == .allowed)
    }

    /// Un état inconnu se résout vers n'importe quel état connu : c'est le sens
    /// même d'une requête de clarification (§19).
    @Test("Un état inconnu peut se résoudre, mais exige une requête")
    func unknownResolvesAndRequiresRequery() {
        #expect(CardTransactionStateMachine.isAllowed(from: .unknown, to: .settled))
        #expect(CardTransactionState.unknown.requiresRequery)
        #expect(CardTransactionState.pending.requiresRequery)
        #expect(!CardTransactionState.settled.requiresRequery)
        // Ni succès, ni échec.
        #expect(!CardTransactionState.unknown.hasMovedMoney)
        #expect(!CardTransactionState.unknown.isTerminal)
    }

    @Test("Un état de transaction inconnu devient .unknown, pas une erreur")
    func unknownTransactionStateDegrades() throws {
        let decoded = try JSONDecoder().decode(CardTransactionState.self,
                                               from: Data(#""NEW_STATE""#.utf8))
        #expect(decoded == .unknown)
        #expect(decoded != .settled)
    }

    // MARK: - 3D Secure

    /// `attempted` transfère la responsabilité sans prouver l'identité. Les
    /// confondre laisserait croire à une authentification qui n'a pas eu lieu.
    @Test("Une tentative 3DS n'est pas une authentification")
    func attemptedIsNotAuthenticated() {
        #expect(ThreeDSecureResult.authenticated.isAuthenticated)
        #expect(!ThreeDSecureResult.attempted.isAuthenticated)
        #expect(!ThreeDSecureResult.failed.isAuthenticated)
        #expect(!ThreeDSecureResult.unknown.isAuthenticated)
    }

    @Test("Un résultat 3DS inconnu ne vaut pas authentification")
    func unknown3DSIsNotAuthentication() throws {
        let decoded = try JSONDecoder().decode(ThreeDSecureResult.self,
                                               from: Data(#""SOMETHING""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.isAuthenticated)
    }

    // MARK: - État de la carte

    /// Une carte bloquée ne se dégèle pas : le blocage vient de l'émetteur, et
    /// proposer le geste produirait un échec incompris.
    @Test("Une carte bloquée n'est ni gelable ni dégelable")
    func blockedCardCannotBeToggled() {
        #expect(!CardStatus.blocked.isFreezable)
        #expect(!CardStatus.blocked.isUnfreezable)
        #expect(!CardStatus.blocked.canTransact)
        // Elle reste remplaçable — c'est même le geste attendu.
        #expect(CardStatus.blocked.isReplaceable)
    }

    @Test("Seule une carte active peut payer et être gelée")
    func onlyActiveCardTransacts() {
        #expect(CardStatus.active.canTransact)
        #expect(CardStatus.active.isFreezable)
        #expect(!CardStatus.frozen.canTransact)
        #expect(CardStatus.frozen.isUnfreezable)
        #expect(!CardStatus.expired.canTransact)
    }

    @Test("Un état de carte inconnu n'autorise aucune opération")
    func unknownCardStatusAllowsNothing() throws {
        let decoded = try JSONDecoder().decode(CardStatus.self, from: Data(#""NEW""#.utf8))
        #expect(decoded == .unknown)
        #expect(!decoded.canTransact)
        #expect(!decoded.isFreezable)
        #expect(!decoded.isUnfreezable)
        #expect(!decoded.isReplaceable)
    }

    /// Une carte volée reste utilisable jusqu'à la réception de la nouvelle :
    /// c'est exactement la fenêtre que la fraude exploite.
    @Test("Vol et compromission exigent un blocage immédiat")
    func stolenRequiresImmediateBlock() {
        #expect(CardReplacementReason.stolen.requiresImmediateBlock)
        #expect(CardReplacementReason.compromised.requiresImmediateBlock)
        #expect(!CardReplacementReason.lost.requiresImmediateBlock)
        #expect(!CardReplacementReason.damaged.requiresImmediateBlock)
        #expect(!CardReplacementReason.expired.requiresImmediateBlock)
    }

    // MARK: - Surface sûre (§21)

    /// Le contrôle est le type lui-même : ces champs n'existent pas, donc rien
    /// ne peut les afficher.
    @Test("La présentation sûre ne montre que quatre chiffres")
    func safePresentationShowsOnlyLast4() {
        let card = SafeCardPresentation(
            id: "c-1", brand: "visa", last4: "4242", status: .active,
            form: .virtual, currency: "BIF", nickname: "Courses"
        )
        #expect(card.maskedLabel == "•••• 4242")
        #expect(card.last4.count == 4)
    }

    /// Un réseau nouveau ne doit pas faire échouer le décodage de toute la
    /// liste des cartes — d'où la chaîne libre plutôt qu'une énumération.
    @Test("Une forme de carte inconnue devient .unknown")
    func unknownCardFormDegrades() throws {
        let decoded = try JSONDecoder().decode(CardForm.self, from: Data(#""HOLOGRAM""#.utf8))
        #expect(decoded == .unknown)
    }

    // MARK: - Provisioning

    @Test("Une capacité de provisioning sans handoff est inutilisable")
    func provisioningNeedsHandoff() {
        let now = Date()
        #expect(!CardProvisioningCapability(cardID: "c-1", isAvailable: true).isUsable(at: now))
        #expect(CardProvisioningCapability(cardID: "c-1", isAvailable: true,
                                           handoffID: "h-1").isUsable(at: now))
        #expect(!CardProvisioningCapability(cardID: "c-1", isAvailable: true, handoffID: "h-1",
                                            expiresAt: now.addingTimeInterval(-1)).isUsable(at: now))
    }

    // MARK: - Défauts fermés

    @Test("Les défauts fermés des cartes refusent tout")
    func closedDefaultsRefuse() async {
        let idempotency = IdempotencyContext.new(deviceID: "device")

        #expect(await ClosedCardManager().cards().isFailureResult)
        #expect(await ClosedCardManager()
            .setFrozen(cardID: "c-1", isFrozen: true, idempotency: idempotency,
                       stepUp: nil).isFailureResult)
        #expect(await ClosedCardTransactionProvider()
            .transactions(cardID: "c-1", cursor: nil).isFailureResult)
        #expect(await ClosedCardTransactionProvider()
            .reportUnrecognized(transactionID: "t-1", idempotency: idempotency,
                                stepUp: nil).isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
