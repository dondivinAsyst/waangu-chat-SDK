import Testing
import Foundation
@testable import WaanguCoreKit

/// Chaos, crash et concurrence — Bloc 8, §29, §30, §31.
///
/// Ces tests ne vérifient pas qu'un cas nominal fonctionne. Ils vérifient
/// qu'aucune combinaison de duplication, de réordonnancement, de perte et de
/// crash ne produit une incohérence irréversible — ce que le §30 formule ainsi :
/// « aucune combinaison de crash ne doit créer une incohérence irréversible ».
///
/// L'injecteur et le simulateur vivent dans la cible de test et non dans
/// CoreKit : livrer un échafaudage de chaos dans le binaire de production
/// donnerait à quelqu'un le moyen de l'activer.
// `.serialized` : deux tests partagent `BackgroundRefreshCoordinator.shared`. En
// parallèle, l'un remplaçait le travail de l'autre pendant son exécution, et le
// test de concurrence échouait selon l'ordonnancement — un défaut du test, pas
// du coordinateur, qui pose son verrou avant toute suspension.
@Suite("Bloc 8 — chaos, crash et concurrence", .serialized)
struct Bloc8ChaosCrashTests {

    // MARK: - Injecteur (§29)

    /// Ce que le réseau peut faire de pire.
    enum NetworkChaos: CaseIterable, Sendable {
        case offline
        case highLatency
        case packetLoss
        case randomDisconnect
        case serverTimeout
        case duplicateResponse
        case delayedResponse
    }

    /// Un flux d'événements soumis au chaos.
    struct ChaoticStream {

        let events: [(sequence: Int64, id: String)]

        /// Applique un chaos et rend ce que le client recevrait réellement.
        func delivered(under chaos: NetworkChaos) -> [(sequence: Int64, id: String)] {
            switch chaos {
            case .offline, .serverTimeout:
                return []
            case .packetLoss:
                // Un événement sur trois se perd.
                return events.enumerated().filter { $0.offset % 3 != 1 }.map(\.element)
            case .duplicateResponse:
                return events + events
            case .delayedResponse, .randomDisconnect:
                // Réordonnancement : la seconde moitié arrive avant la première.
                let half = events.count / 2
                return Array(events[half...]) + Array(events[..<half])
            case .highLatency:
                return events
            }
        }
    }

    /// L'état local, tel que le garderait un client.
    struct LocalState {
        var lastApplied: Int64?
        var seen: Set<String> = []
        var appliedOrder: [Int64] = []

        /// Applique un événement si — et seulement si — le garde l'autorise.
        mutating func apply(sequence: Int64, id: String) -> SequenceVerdict {
            let verdict = SequenceGuard.verdict(
                incoming: sequence, lastApplied: lastApplied,
                eventID: id, seenEventIDs: seen
            )
            if verdict.permitsApplication {
                seen.insert(id)
                lastApplied = sequence
                appliedOrder.append(sequence)
            }
            return verdict
        }
    }

    private var stream: ChaoticStream {
        ChaoticStream(events: (1...12).map { (Int64($0), "e\($0)") })
    }

    // MARK: - §29 — invariants sous chaos

    /// « No duplicate » (§29).
    @Test("Aucun chaos ne produit une double application", arguments: NetworkChaos.allCases)
    func noDuplicateUnderChaos(chaos: NetworkChaos) {
        var state = LocalState()
        for event in stream.delivered(under: chaos) {
            _ = state.apply(sequence: event.sequence, id: event.id)
        }
        // Chaque séquence appliquée l'est au plus une fois.
        #expect(Set(state.appliedOrder).count == state.appliedOrder.count)
    }

    /// « No stale financial authority » (§29) — une version ancienne n'écrase rien.
    @Test("Aucun chaos ne fait reculer l'état local", arguments: NetworkChaos.allCases)
    func stateNeverGoesBackwards(chaos: NetworkChaos) {
        var state = LocalState()
        for event in stream.delivered(under: chaos) {
            _ = state.apply(sequence: event.sequence, id: event.id)
        }
        // Les séquences appliquées sont strictement croissantes.
        #expect(state.appliedOrder == state.appliedOrder.sorted())
    }

    /// « No lost message » — la perte est *détectée*, pas silencieuse.
    @Test("Une perte de paquets produit un trou détecté, jamais un saut silencieux")
    func packetLossIsDetected() {
        var state = LocalState()
        var gaps = 0

        for event in stream.delivered(under: .packetLoss) {
            if case .gap = state.apply(sequence: event.sequence, id: event.id) {
                gaps += 1
            }
        }

        // L'essentiel : le client sait qu'il lui manque quelque chose. Un
        // client qui appliquerait les événements survivants sans rien
        // remarquer afficherait un état faux en se croyant à jour.
        #expect(gaps > 0)
    }

    @Test("Une réponse dupliquée n'a aucun effet supplémentaire")
    func duplicateResponseHasNoEffect() {
        var single = LocalState()
        for event in stream.events {
            _ = single.apply(sequence: event.sequence, id: event.id)
        }

        var doubled = LocalState()
        for event in stream.delivered(under: .duplicateResponse) {
            _ = doubled.apply(sequence: event.sequence, id: event.id)
        }

        #expect(single.appliedOrder == doubled.appliedOrder)
    }

    /// « No infinite retry » (§29).
    @Test("Le backoff finit par cesser de réessayer")
    func retryTerminates() {
        let policy = RetryPolicy.read
        var attempt = 1
        var retries = 0

        while case .retry = SyncError.timeout.disposition(attempt: attempt, policy: policy) {
            retries += 1
            attempt += 1
            if retries > 100 { break }   // garde-fou du test lui-même
        }

        #expect(retries < policy.maxAttempts + 1)
        // Une fois les tentatives épuisées, on interroge au lieu de rejouer.
        #expect(SyncError.timeout.disposition(attempt: 99, policy: policy) == .requery)
    }

    // MARK: - §30 — cohérence au crash

    /// Les points de crash énumérés par le §30.
    enum CrashPoint: CaseIterable {
        case afterEnqueue
        case afterLocalWrite
        case beforeRequest
        case afterRequest
        case beforeResponse
        case afterResponse
        case beforeDBCommit
        case afterDBCommit
        case beforeCursorCommit
        case afterCursorCommit
    }

    /// Simule une page appliquée puis interrompue, puis un redémarrage.
    ///
    /// Le curseur n'est committé qu'après les données — c'est l'ordre que
    /// ``SyncCursorPersisting`` rend obligatoire. La question du §30 est :
    /// après un crash à ce point précis, la reprise converge-t-elle ?
    private func simulateCrashThenRestart(at point: CrashPoint) -> LocalState {
        var state = LocalState()
        let page = stream.events

        // Application de la page.
        let committedData: Bool
        let committedCursor: Bool

        switch point {
        case .afterEnqueue, .afterLocalWrite, .beforeRequest,
             .afterRequest, .beforeResponse, .afterResponse, .beforeDBCommit:
            committedData = false
            committedCursor = false
        case .afterDBCommit, .beforeCursorCommit:
            committedData = true
            committedCursor = false
        case .afterCursorCommit:
            committedData = true
            committedCursor = true
        }

        if committedData {
            for event in page {
                _ = state.apply(sequence: event.sequence, id: event.id)
            }
        }

        // Redémarrage : on rejoue depuis le curseur committé. S'il ne l'a pas
        // été, la page entière revient — c'est le cas qui exige l'idempotence.
        if !committedCursor {
            for event in page {
                _ = state.apply(sequence: event.sequence, id: event.id)
            }
        }

        return state
    }

    @Test("Aucun point de crash ne produit un doublon après reprise",
          arguments: CrashPoint.allCases)
    func noCrashPointDuplicates(point: CrashPoint) {
        let state = simulateCrashThenRestart(at: point)
        #expect(Set(state.appliedOrder).count == state.appliedOrder.count)
    }

    @Test("Tout point de crash converge vers le même état",
          arguments: CrashPoint.allCases)
    func everyCrashPointConverges(point: CrashPoint) {
        let state = simulateCrashThenRestart(at: point)
        // Douze événements, appliqués une fois chacun, dans l'ordre.
        #expect(state.appliedOrder == (1...12).map(Int64.init))
        #expect(state.lastApplied == 12)
    }

    /// `CURSOR_COMMITS_ONLY_AFTER_DATA_COMMIT` (§33).
    @Test("Un curseur committé avant ses données ferait sauter la page")
    func cursorBeforeDataWouldSkip() {
        // Ce test décrit l'inversion interdite, pour qu'elle soit visible.
        // On committe le curseur sans appliquer les données, puis on reprend.
        var state = LocalState()
        let skippedCursor: Int64 = 12          // curseur avancé…
        // …alors qu'aucun événement n'a été appliqué.
        #expect(state.lastApplied == nil)

        // La reprise repart après le curseur : les douze événements sont
        // perdus, définitivement et sans erreur.
        _ = state.apply(sequence: skippedCursor + 1, id: "e13")

        #expect(state.appliedOrder == [13])
        #expect(!state.appliedOrder.contains(1))

        // C'est précisément ce que la signature de `SyncCursorPersisting`
        // rend impossible à écrire : elle exige un `CommitReceipt`.
    }

    // MARK: - §31 — concurrence

    @Test("Deux réveils de fond concurrents ne lancent qu'une exécution")
    func concurrentBackgroundRunsAreSerialised() async {
        let coordinator = BackgroundRefreshCoordinator.shared
        let counter = RunCounter()

        await coordinator.setWork { _ in
            await counter.increment()
            try? await Task.sleep(nanoseconds: 50_000_000)
            return .completed
        }

        let budget = BackgroundBudget(
            deadline: Date(timeIntervalSinceNow: 30), hasNetwork: true
        )

        async let first = coordinator.run(budget: budget)
        async let second = coordinator.run(budget: budget)
        let outcomes = await [first, second]

        // L'un s'exécute, l'autre est refusé — jamais deux synchronisations
        // concurrentes sur la même base.
        #expect(outcomes.contains(.alreadyRunning))
        #expect(await counter.value == 1)
    }

    @Test("Sans réseau, le travail de fond ne démarre pas")
    func backgroundSkipsWithoutNetwork() async {
        let coordinator = BackgroundRefreshCoordinator.shared
        await coordinator.setWork { _ in .completed }

        let outcome = await coordinator.run(budget: BackgroundBudget(
            deadline: Date(timeIntervalSinceNow: 30), hasNetwork: false
        ))

        #expect(outcome == .skipped)
    }

    /// Compteur isolé, pour observer la concurrence sans course.
    actor RunCounter {
        private(set) var value = 0
        func increment() { value += 1 }
    }
}
