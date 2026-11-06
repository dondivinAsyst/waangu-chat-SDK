import Testing
import Foundation
@testable import WaanguCoreKit

/// Paiement de proximité — Bloc 6, chapitre 47.
///
/// Couvre le P0-8 et les sept impossibilités du chapitre : rejeu, double
/// paiement, changement de marchand, de montant, de terminal, paiement hors
/// session et après expiration.
@Suite("Bloc 6 — paiement de proximité")
struct Bloc6ProximityTests {

    private let bif = CurrencyCode(code: "BIF", exponent: 0)
    private func money(_ v: Int64) -> Money { Money(minorUnits: v, currency: bif) }

    private func terminal(
        terminalID: String = "term-1",
        merchantID: String = "m-1",
        amount: Int64 = 12_000,
        hash: String = "h-abc"
    ) -> TerminalIdentitySnapshot {
        TerminalIdentitySnapshot(
            terminalID: terminalID, merchantID: merchantID,
            merchantDisplayName: "Pharmacie", amount: money(amount),
            presentedHash: hash, capturedAt: Date()
        )
    }

    private func session(
        expiresIn: TimeInterval = 60,
        state: ProximitySessionState = .open,
        relay: RelayRiskLevel = .low,
        pinned: TerminalIdentitySnapshot? = nil,
        now: Date = Date()
    ) -> ProximityPaymentSession {
        ProximityPaymentSession(
            id: "s-1", terminal: pinned ?? terminal(), nonce: "n-1",
            openedAt: now, expiresAt: now.addingTimeInterval(expiresIn),
            state: state, relayRisk: RelayRiskResult(level: relay),
            requiresStepUp: false
        )
    }

    // MARK: - Les changements interdits

    /// Changement de montant : le terminal réclame autre chose que ce qui a
    /// été épinglé.
    @Test("Un montant modifié invalide la session")
    func amountChangeDetected() {
        let pinned = session(pinned: terminal(amount: 12_000))
        #expect(pinned.validate(presented: terminal(amount: 99_000)) == .amountChanged)
    }

    @Test("Un terminal substitué est détecté")
    func terminalChangeDetected() {
        let pinned = session(pinned: terminal(terminalID: "term-1"))
        #expect(pinned.validate(presented: terminal(terminalID: "term-9")) == .terminalChanged)
    }

    @Test("Un marchand substitué est détecté")
    func merchantChangeDetected() {
        let pinned = session(pinned: terminal(merchantID: "m-1"))
        #expect(pinned.validate(presented: terminal(merchantID: "m-9")) == .merchantChanged)
    }

    /// L'empreinte attrape ce que les trois autres champs laisseraient passer :
    /// une trame rejouée porte les mêmes identifiants mais pas la même charge.
    @Test("Une charge utile modifiée est détectée")
    func payloadChangeDetected() {
        let pinned = session(pinned: terminal(hash: "h-abc"))
        #expect(pinned.validate(presented: terminal(hash: "h-xyz")) == .payloadChanged)
    }

    @Test("Un terminal identique ne produit aucun écart")
    func identicalTerminalMatches() {
        let source = terminal()
        #expect(session(pinned: source).validate(presented: source) == nil)
        #expect(source.matches(source))
    }

    // MARK: - Expiration et état

    /// Une session de proximité vit le temps d'un geste. Confirmer après coup
    /// est le « paiement après expiration » que le chapitre interdit.
    @Test("Une session expirée n'est pas confirmable")
    func expiredSessionIsNotConfirmable() {
        let now = Date()
        let live = session(expiresIn: 60, now: now)
        #expect(live.isConfirmable(at: now))
        #expect(!live.isConfirmable(at: now.addingTimeInterval(120)))
        #expect(live.hasExpired(at: now.addingTimeInterval(120)))
    }

    /// Hors de l'état `open`, rien ne se confirme — y compris une session déjà
    /// complétée, ce qui interdit le double paiement.
    @Test("Seule une session ouverte se confirme")
    func onlyOpenSessionConfirms() {
        for state in [ProximitySessionState.completed, .cancelled, .expired,
                      .rejected, .confirming, .unknown] {
            #expect(!session(state: state).isConfirmable())
        }
        #expect(session(state: .open).isConfirmable())
    }

    @Test("Un état de session inconnu ne confirme rien")
    func unknownSessionStateBlocks() throws {
        let decoded = try JSONDecoder().decode(ProximitySessionState.self,
                                               from: Data(#""NEW""#.utf8))
        #expect(decoded == .unknown)
        #expect(!session(state: decoded).isConfirmable())
    }

    // MARK: - Relais

    @Test("Un risque de relais bloquant empêche le paiement")
    func blockedRelayPreventsPayment() {
        #expect(!session(relay: .blocked).isConfirmable())
        #expect(session(relay: .low).isConfirmable())
        #expect(session(relay: .elevated).isConfirmable())
    }

    /// Un risque élevé force l'authentification même sous le plafond sans
    /// contact : c'est le seul moyen de distinguer le porteur d'un relais.
    @Test("Un risque élevé force le step-up")
    func elevatedRelayForcesStepUp() {
        #expect(RelayRiskResult(level: .elevated).forcesStepUp)
        #expect(!RelayRiskResult(level: .low).forcesStepUp)
        #expect(RelayRiskResult(level: .low).permitsPayment)
        #expect(!RelayRiskResult(level: .blocked).permitsPayment)
    }

    /// Le sens de la dégradation compte : traiter un signal incompris comme
    /// bénin annulerait la protection le jour où le backend en ajoute un.
    @Test("Un niveau de relais inconnu est traité comme élevé")
    func unknownRelayDegradesToElevated() throws {
        let decoded = try JSONDecoder().decode(RelayRiskLevel.self,
                                               from: Data(#""EXTREME""#.utf8))
        #expect(decoded == .elevated)
        #expect(decoded != .low)
    }

    // MARK: - Attestation

    /// Une attestation vieillie ne vaut plus rien : l'appareil a pu changer
    /// d'état entre-temps.
    @Test("Une attestation périmée est refusée")
    func staleAttestationRejected() {
        let now = Date()
        let fresh = DeviceAttestationResult(attestationToken: "t", deviceBindingID: "d",
                                            capturedAt: now)
        let stale = DeviceAttestationResult(attestationToken: "t", deviceBindingID: "d",
                                            capturedAt: now.addingTimeInterval(-300))
        #expect(fresh.isFresh(at: now))
        #expect(!stale.isFresh(at: now))
    }

    // MARK: - Issue (§19)

    /// Le cœur du double débit : « incertain » n'est pas « échoué ». Les
    /// confondre fait réessayer une opération qui avait abouti.
    @Test("Incertain n'est jamais échoué")
    func uncertainIsNotFailed() {
        #expect(ProximityPaymentTruth.unknown.requiresRequery)
        #expect(ProximityPaymentTruth.pending.requiresRequery)
        #expect(ProximityPaymentTruth.processing.requiresRequery)

        #expect(!ProximityPaymentTruth.unknown.permitsRetry)
        #expect(!ProximityPaymentTruth.pending.permitsRetry)
        #expect(!ProximityPaymentTruth.processing.permitsRetry)

        // Seul un échec avéré autorise une nouvelle tentative.
        #expect(ProximityPaymentTruth.failed.permitsRetry)
        #expect(!ProximityPaymentTruth.failed.requiresRequery)
    }

    @Test("Seul confirmed se présente comme abouti")
    func onlyConfirmedIsSettled() {
        #expect(ProximityPaymentTruth.confirmed.isSettled)
        for truth in [ProximityPaymentTruth.pending, .processing, .unknown, .failed, .reversed] {
            #expect(!truth.isSettled)
        }
    }

    /// Une issue d'un type que ce client ne connaît pas ne s'affiche ni comme
    /// réussie, ni comme échouée : elle se requête.
    @Test("Une issue inconnue exige une requête, pas un rejeu")
    func unknownTruthRequiresRequery() throws {
        let decoded = try JSONDecoder().decode(ProximityPaymentTruth.self,
                                               from: Data(#""SOMETHING""#.utf8))
        #expect(decoded == .unknown)
        #expect(decoded.requiresRequery)
        #expect(!decoded.permitsRetry)
        #expect(!decoded.isSettled)
    }

    // MARK: - Défaut fermé

    @Test("Le défaut fermé n'ouvre aucune session")
    func closedDefaultRefuses() async {
        let provider = ClosedProximityPaymentSessioning()
        let idempotency = IdempotencyContext.new(deviceID: "device")
        let attestation = DeviceAttestationResult(attestationToken: "t",
                                                  deviceBindingID: "d", capturedAt: Date())

        #expect(await provider.capability().isFailureResult)
        #expect(await provider.open(terminal: terminal(), attestation: attestation,
                                    idempotency: idempotency).isFailureResult)
        #expect(await provider.confirm(session: session(), idempotency: idempotency,
                                       stepUp: nil).isFailureResult)
        #expect(await provider.requery(sessionID: "s-1").isFailureResult)
    }
}

private extension Result {
    var isFailureResult: Bool {
        if case .failure = self { return true }
        return false
    }
}
