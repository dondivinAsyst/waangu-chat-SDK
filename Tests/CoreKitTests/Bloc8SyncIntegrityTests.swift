import Testing
import Foundation
@testable import WaanguCoreKit

/// Intégrité de synchronisation — Bloc 8, §15, §16, §19, §20, §33.
///
/// Les tests sont nommés d'après les invariants du §33 quand ils en couvrent
/// un. Un test qui ne sait dire que « refusé » laisserait passer la
/// disparition d'un contrôle : chaque cas nomme donc ce qu'il protège.
@Suite("Bloc 8 — intégrité de la synchronisation")
struct Bloc8SyncIntegrityTests {

    // MARK: - Séquences (§15)

    @Test("Le suivant attendu s'applique")
    func nextSequenceApplies() {
        #expect(SequenceGuard.verdict(
            incoming: 5, lastApplied: 4, eventID: "e5", seenEventIDs: []
        ) == .apply)
    }

    /// `DUPLICATE_EVENT_CANNOT_DUPLICATE_EFFECT` (§33).
    @Test("Un événement déjà vu est un doublon, quelle que soit sa séquence")
    func duplicateByEventID() {
        // Même séquence que l'attendu, mais l'identifiant est connu : c'est un
        // rejeu. Le contrôle par identifiant doit précéder celui de position,
        // sinon un événement arrivé par MQTT puis par l'API compte deux fois.
        #expect(SequenceGuard.verdict(
            incoming: 5, lastApplied: 4, eventID: "e5", seenEventIDs: ["e5"]
        ) == .duplicate)
    }

    @Test("Une séquence déjà appliquée est un doublon")
    func duplicateBySequence() {
        #expect(SequenceGuard.verdict(
            incoming: 4, lastApplied: 4, eventID: "other", seenEventIDs: []
        ) == .duplicate)
    }

    /// `OLD_VERSION_CANNOT_OVERWRITE_NEW_VERSION` (§33).
    @Test("Une version antérieure n'écrase jamais une plus récente")
    func staleIsRejected() {
        #expect(SequenceGuard.verdict(
            incoming: 2, lastApplied: 7, eventID: "e2", seenEventIDs: []
        ) == .stale)
    }

    @Test("Un saut de séquence est un trou, pas une application")
    func gapIsDetected() {
        let verdict = SequenceGuard.verdict(
            incoming: 9, lastApplied: 4, eventID: "e9", seenEventIDs: []
        )
        #expect(verdict == .gap(expected: 5, received: 9))
        #expect(!verdict.permitsApplication)
    }

    @Test("Une séquence non positive impose une requête")
    func invalidSequenceRequeries() {
        #expect(SequenceGuard.verdict(
            incoming: 0, lastApplied: 3, eventID: "e0", seenEventIDs: []
        ) == .requery)
    }

    @Test("Le premier événement d'un flux vide s'applique")
    func firstEventApplies() {
        #expect(SequenceGuard.verdict(
            incoming: 42, lastApplied: nil, eventID: "e42", seenEventIDs: []
        ) == .apply)
    }

    /// §32 — property-based : appliquer deux fois vaut appliquer une fois.
    @Test("Rejouer une séquence entière ne produit aucune seconde application")
    func replayIsIdempotent() {
        var seen: Set<String> = []
        var last: Int64?
        var applied = 0

        let stream: [(Int64, String)] = (1...20).map { (Int64($0), "e\($0)") }

        // Premier passage.
        for (seq, id) in stream where SequenceGuard.verdict(
            incoming: seq, lastApplied: last, eventID: id, seenEventIDs: seen
        ).permitsApplication {
            applied += 1
            seen.insert(id)
            last = seq
        }
        #expect(applied == 20)

        // Rejeu intégral : aucune application supplémentaire.
        for (seq, id) in stream where SequenceGuard.verdict(
            incoming: seq, lastApplied: last, eventID: id, seenEventIDs: seen
        ).permitsApplication {
            applied += 1
        }
        #expect(applied == 20)
    }

    @Test("Des événements réordonnés ne s'appliquent pas dans le désordre")
    func reorderedEventsDoNotApply() {
        // 5 arrive avant 4 : c'est un trou, pas une application anticipée.
        #expect(!SequenceGuard.verdict(
            incoming: 5, lastApplied: 3, eventID: "e5", seenEventIDs: []
        ).permitsApplication)
    }

    // MARK: - Erreurs (§9, §39)

    /// §9 — ces erreurs ne doivent **jamais** produire un retry automatique.
    @Test("Les erreurs non rejouables ne rendent jamais .retry", arguments: [
        SyncError.unauthorized,
        SyncError.forbidden,
        SyncError.conflict(objectID: "o-1"),
        SyncError.expired,
        SyncError.malformedPayload(reason: "x"),
        SyncError.permanentFailure(code: "unprocessable"),
        SyncError.foreignScope,
        SyncError.revoked
    ])
    func nonRetryableNeverRetries(error: SyncError) {
        if case .retry = error.disposition(attempt: 1) {
            Issue.record("\(error) a produit un retry, ce que le §9 interdit")
        }
    }

    /// `REVOKED_DEVICE_CANNOT_SYNC_SENSITIVE_DATA` (§33).
    @Test("Une révocation purge et arrête")
    func revocationPurges() {
        #expect(SyncError.revoked.disposition(attempt: 1) == .purgeAndStop)
    }

    /// `UNKNOWN_PAYMENT_OUTCOME_REQUIRES_REQUERY` (§33).
    @Test("Une issue inconnue se requête, elle ne se rejoue pas")
    func unknownOutcomeRequeries() {
        #expect(SyncError.unknownOutcome(operationID: "op-1")
            .disposition(attempt: 1) == .requery)
    }

    @Test("Un curseur invalide impose une resynchronisation complète")
    func invalidCursorForcesFullResync() {
        #expect(SyncError.invalidCursor.disposition(attempt: 1) == .fullResync)
    }

    @Test("Le Retry-After du serveur l'emporte sur le backoff local")
    func retryAfterWins() {
        #expect(SyncError.serverUnavailable(retryAfter: 42)
            .disposition(attempt: 1) == .retry(after: 42))
    }

    @Test("Hors ligne n'épuise pas les tentatives")
    func offlineDoesNotBurnAttempts() {
        // Le réseau reviendra : compter cette absence comme un échec ferait
        // atteindre le dead-letter sans qu'aucune requête soit partie.
        #expect(SyncError.offline.disposition(attempt: 99) == .retry(after: 0))
    }

    @Test("Chaque erreur porte une clé d'affichage distincte du générique")
    func everyErrorHasItsOwnMessage() {
        let errors: [SyncError] = [
            .offline, .timeout, .unauthorized, .forbidden,
            .conflict(objectID: nil), .stale, .expired, .revoked,
            .invalidCursor, .malformedPayload(reason: "x"),
            .serverUnavailable(retryAfter: nil),
            .unknownOutcome(operationID: nil),
            .permanentFailure(code: "z"), .foreignScope
        ]
        let keys = Set(errors.map(\.displayMessageKey))
        // §39 : jamais « une erreur est survenue » pour tout le monde.
        #expect(keys.count == errors.count)
    }

    // MARK: - Correspondance HTTP (§28)

    @Test("Un 500 sur une mutation devient une issue inconnue, pas un timeout")
    func mutationServerErrorIsUnknownOutcome() {
        // La différence entre un débit et deux : une écriture qui a échoué en
        // apparence peut avoir abouti côté serveur.
        #expect(SyncError.from(statusCode: 500, isMutation: true, operationID: "op-9")
            == .unknownOutcome(operationID: "op-9"))
    }

    @Test("Un 500 sur une lecture reste une indisponibilité")
    func readServerErrorIsUnavailable() {
        #expect(SyncError.from(statusCode: 500, isMutation: false)
            == .serverUnavailable(retryAfter: nil))
    }

    @Test("Le succès ne produit aucune erreur", arguments: [200, 201, 204, 299])
    func successMapsToNil(code: Int) {
        #expect(SyncError.from(statusCode: code) == nil)
    }

    @Test("Un 410 signale un curseur périmé")
    func goneMeansInvalidCursor() {
        #expect(SyncError.from(statusCode: 410) == .invalidCursor)
    }

    // MARK: - Liaison du step-up (§19)

    private func attestation(
        device: String = "dev-1",
        session: String? = "sess-1",
        correlation: CorrelationId = CorrelationId(value: "corr-1"),
        satisfiedAt: Date = Date()
    ) -> StepUpAttestation {
        StepUpAttestation(
            level: .biometric,
            correlationID: correlation,
            deviceID: device,
            sessionID: session,
            satisfiedAt: satisfiedAt
        )
    }

    private func requirement(
        device: String = "dev-1",
        session: String = "sess-1",
        correlation: CorrelationId = CorrelationId(value: "corr-1")
    ) -> StepUpBindingRequirement {
        StepUpBindingRequirement(
            expectedDeviceID: device,
            expectedSessionID: session,
            expectedCorrelationID: correlation
        )
    }

    @Test("Une attestation correctement liée est acceptée")
    func boundAttestationPasses() {
        #expect(attestation().bindingRejection(against: requirement()) == nil)
    }

    @Test("Une attestation d'un autre appareil est refusée")
    func wrongDeviceRejected() {
        #expect(attestation(device: "dev-2")
            .bindingRejection(against: requirement()) == .wrongDevice)
    }

    /// Le cœur du §19 : une preuve iOS ne devient pas une autorisation ailleurs.
    @Test("Une attestation d'une autre session est refusée")
    func wrongSessionRejected() {
        #expect(attestation(session: "sess-2")
            .bindingRejection(against: requirement()) == .wrongSession)
    }

    @Test("Une attestation sans session est refusée, pas acceptée par défaut")
    func unboundSessionRejected() {
        // Une preuve qui ne dit pas à quelle session elle appartient vaudrait
        // pour toutes — c'est exactement ce que le §19 interdit.
        #expect(attestation(session: nil)
            .bindingRejection(against: requirement()) == .unboundSession)
    }

    @Test("Une attestation obtenue pour un autre objet est refusée")
    func wrongPurposeRejected() {
        #expect(attestation(correlation: CorrelationId(value: "autre"))
            .bindingRejection(against: requirement()) == .wrongPurpose)
    }

    @Test("Une attestation trop ancienne est refusée")
    func staleAttestationRejected() {
        let old = attestation(satisfiedAt: Date(timeIntervalSinceNow: -600))
        #expect(old.bindingRejection(against: requirement()) == .tooOld)
    }

    @Test("Un mauvais appareil est un incident, pas une erreur d'usage")
    func wrongDeviceIsIncident() {
        #expect(StepUpBindingRejection.wrongDevice.isSecurityIncident)
        #expect(StepUpBindingRejection.wrongSession.isSecurityIncident)
        #expect(!StepUpBindingRejection.tooOld.isSecurityIncident)
    }

    // MARK: - Confiance d'appareil (§18, §33)

    @Test("Un appareil révoqué ne synchronise rien de sensible")
    func revokedDeviceCannotSync() {
        #expect(!DeviceTrustLevel.revoked.permitsSensitiveSync)
        #expect(!DeviceTrustLevel.revoked.permitsMutation)
    }

    @Test("Un niveau de confiance inconnu ne vaut pas confiance")
    func unknownTrustIsNotTrusted() {
        // Un backend qui ajoute un niveau ne doit pas voir ce client
        // l'interpréter comme « de confiance ».
        #expect(!DeviceTrustLevel.unknown.permitsSensitiveSync)
        #expect(!DeviceTrustLevel.suspicious.permitsMutation)
    }

    @Test("Seul un appareil de confiance peut muter")
    func onlyTrustedMutates() {
        #expect(DeviceTrustLevel.trusted.permitsMutation)
        #expect(!DeviceTrustLevel.known.permitsMutation)
        #expect(DeviceTrustLevel.known.permitsSensitiveSync)
    }

    @Test("La révocation vide l'outbox sans la republier")
    func revocationDiscardsOutbox() {
        // Republier depuis un appareil révoqué est précisément ce que la
        // révocation cherche à empêcher.
        #expect(DeviceRevocationEffect.complete.discardsOutboxWithoutFlush)
        #expect(DeviceRevocationEffect.complete.purgesFinancialCache)
    }

    // MARK: - Tâches de fond (§20)

    @Test("Une tâche de fond n'exécute jamais de mutation financière")
    func backgroundNeverMutatesMoney() {
        let budget = BackgroundBudget(
            deadline: Date(timeIntervalSinceNow: 30), hasNetwork: true
        )
        #expect(!budget.permitsFinancialMutation)
    }

    @Test("Un budget épuisé n'autorise pas une nouvelle unité de travail")
    func exhaustedBudgetStops() {
        let budget = BackgroundBudget(
            deadline: Date(timeIntervalSinceNow: 2), hasNetwork: true
        )
        #expect(!budget.permitsMoreWork(estimated: 8))
        #expect(budget.permitsMoreWork(estimated: 0.5))
    }

    @Test("Un travail partiel compte comme un succès")
    func partialIsSuccess() {
        // Rapporter un échec ferait baisser la priorité des réveils suivants,
        // punissant une exécution correcte.
        #expect(BackgroundOutcome.partial.isSuccess)
        #expect(BackgroundOutcome.completed.isSuccess)
        #expect(!BackgroundOutcome.expired.isSuccess)
    }

    // MARK: - Validation (§16)

    @Test("Un événement d'un autre périmètre ne s'applique pas")
    func foreignScopeDoesNotApply() {
        #expect(!ValidationVerdict.foreignScope.permitsApplication)
        #expect(!ValidationVerdict.malformed(reason: "x").permitsApplication)
        #expect(ValidationVerdict.valid.permitsApplication)
    }

    @Test("Une fuite cross-account est un incident de sécurité")
    func foreignScopeIsIncident() {
        #expect(SyncError.foreignScope.isSecurityIncident)
        #expect(!SyncError.offline.isSecurityIncident)
    }
}
