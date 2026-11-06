//
//  Reconnectionmanager.swift
//  AppModules
//
//  Created by Asyst on 6/3/26.
//

// MARK: - RealtimeKit/Reconnection/ReconnectionManager.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Gestion de la reconnexion automatique avec exponential backoff + jitter.
//           Joue le rôle du CircuitBreaker de NetworkKit, mais pour une connexion
//           persistante unique au lieu d'endpoints HTTP multiples.
//
// Design  : Actor pour le thread safety.
//           Le RealtimeClient appelle nextDelay(attempt:) à chaque tentative.
//           Le manager calcule le délai optimal et retourne nil quand
//           le nombre maximum de tentatives est atteint.
//
// Algorithme :
//   delay = min(baseDelay × 2^(attempt-1), maxDelay)
//   jitter = delay × random(jitterRange)
//   finalDelay = delay + jitter
//
//   Exemple avec baseDelay=1s, maxDelay=60s, jitter 0…0.3 :
//     Attempt 1 → ~1.0s – 1.3s
//     Attempt 2 → ~2.0s – 2.6s
//     Attempt 3 → ~4.0s – 5.2s
//     Attempt 4 → ~8.0s – 10.4s
//     Attempt 5 → ~16s  – 20.8s
//     Attempt 6 → ~32s  – 41.6s
//     Attempt 7 → ~60s  – 60s (plafonné)
//
// Reset : Quand la connexion tient plus longtemps que `resetAfterConnectedFor`,
//         le compteur revient à 0. Ça évite qu'une déconnexion brève après
//         30 minutes de stabilité recommence à attempt 15.

import Foundation
import WaanguCoreKit

// MARK: - ReconnectionManager

/// Gère la reconnexion automatique avec exponential backoff et jitter.
///
/// Utilisé par le `RealtimeClient` quand le transport perd la connexion.
/// Le manager ne se connecte pas lui-même — il calcule le délai optimal
/// et laisse le client décider quand et comment reconnecter.
///
/// ```swift
/// // Dans RealtimeClient.startReconnection() :
/// let attempt = (stateMachine.reconnectionAttempt ?? 0) + 1
/// let delay = await reconnectionManager.nextDelay(attempt: attempt)
///
/// guard let delay else {
///     // Max attempts atteint → abandon.
///     stateMachine.forceDisconnect(reason: .allTransportsFailed)
///     return
/// }
///
/// stateMachine.transition(to: .reconnecting(attempt: attempt, nextRetryIn: delay))
/// try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
/// try await connect()
/// ```
actor ReconnectionManager {

    // MARK: - Properties

    /// Politique de reconnexion (immutable après init).
    private let policy: ReconnectionPolicy

    /// Timestamp de la dernière connexion réussie.
    /// Utilisé pour le reset automatique du compteur.
    private var lastConnectedAt: Date?

    /// Durée totale passée en reconnexion depuis la dernière connexion stable.
    private var totalReconnectionDuration: TimeInterval = 0

    /// Timestamp du début du cycle de reconnexion courant.
    private var reconnectionStartedAt: Date?

    // MARK: - Init

    /// Crée un manager avec la politique donnée.
    ///
    /// - Parameter policy: Politique de reconnexion (`.standard`, `.aggressive`, `.conservative`).
    init(policy: ReconnectionPolicy) {
        self.policy = policy
    }

    // MARK: - Public API

    /// Calcule le délai avant la prochaine tentative de reconnexion.
    ///
    /// - Parameter attempt: Numéro de la tentative (1-based).
    /// - Returns: Le délai en secondes, ou `nil` si le nombre maximum
    ///            de tentatives est atteint (→ abandon).
    func nextDelay(attempt: Int) -> TimeInterval? {
        // Vérifier le max attempts (0 = infini).
        if policy.maxAttempts > 0, attempt > policy.maxAttempts {
            return nil
        }

        // Marquer le début du cycle si c'est la première tentative.
        if attempt == 1 {
            reconnectionStartedAt = Date()
        }

        // Calculer le délai avec exponential backoff.
        let exponentialDelay = calculateExponentialDelay(attempt: attempt)

        // Ajouter le jitter.
        let jitteredDelay = applyJitter(to: exponentialDelay)

        // Plafonner au maxDelay.
        let finalDelay = min(jitteredDelay, policy.maxDelay)

        return max(finalDelay, 0)
    }

    /// Reset le manager après une connexion réussie.
    ///
    /// Appelé par le `RealtimeClient` quand la connexion est établie.
    /// Enregistre le timestamp pour le reset automatique.
    func reset() {
        let now = Date()

        // Calculer la durée du cycle de reconnexion (pour les métriques).
        if let started = reconnectionStartedAt {
            totalReconnectionDuration += now.timeIntervalSince(started)
        }

        lastConnectedAt = now
        reconnectionStartedAt = nil
    }

    /// Vérifie si le compteur devrait être reset automatiquement.
    ///
    /// Si la connexion a tenu plus longtemps que `resetAfterConnectedFor`,
    /// on considère que la connexion est stable et on repart de zéro.
    ///
    /// - Returns: `true` si le reset automatique a été appliqué.
    func shouldResetCounter() -> Bool {
        guard let lastConnected = lastConnectedAt else {
            return false
        }
        let stableDuration = Date().timeIntervalSince(lastConnected)
        return stableDuration >= policy.resetAfterConnectedFor
    }

    /// La durée totale passée en reconnexion (pour les métriques).
    func totalTimeInReconnection() -> TimeInterval {
        var total = totalReconnectionDuration
        if let started = reconnectionStartedAt {
            total += Date().timeIntervalSince(started)
        }
        return total
    }

    /// La politique courante (pour l'inspection dans les tests).
    func currentPolicy() -> ReconnectionPolicy {
        policy
    }

    // MARK: - Private — Exponential Backoff

    /// Calcule le délai exponentiel brut (sans jitter).
    ///
    /// Formule : `baseDelay × 2^(attempt - 1)`
    /// Plafonné à `maxDelay`.
    private func calculateExponentialDelay(attempt: Int) -> TimeInterval {
        // Protéger contre les overflow pour les très grands attempt numbers.
        let exponent = min(attempt - 1, 30)  // 2^30 ≈ 1 milliard — largement suffisant

        let rawDelay = policy.baseDelay * pow(2.0, Double(exponent))

        // Plafonner immédiatement pour éviter les valeurs astronomiques.
        return min(rawDelay, policy.maxDelay)
    }

    /// Applique un jitter aléatoire au délai.
    ///
    /// Le jitter empêche le "thundering herd" — si 1000 clients
    /// se déconnectent en même temps, ils ne retentent pas tous
    /// exactement au même moment.
    ///
    /// Formule : `delay + delay × random(jitterRange)`
    private func applyJitter(to delay: TimeInterval) -> TimeInterval {
        let range = policy.jitterRange
        guard range.upperBound > 0 else { return delay }

        let jitterFactor = Double.random(in: range)
        return delay + (delay * jitterFactor)
    }
}

// MARK: - ReconnectionManager + Diagnostics

extension ReconnectionManager {

    /// Snapshot de l'état courant du manager (pour le debugging/métriques).
    struct Snapshot: Sendable {
        let policy: ReconnectionPolicy
        let lastConnectedAt: Date?
        let isInReconnectionCycle: Bool
        let totalReconnectionDuration: TimeInterval
    }

    /// Retourne un snapshot de l'état courant.
    func snapshot() -> Snapshot {
        Snapshot(
            policy: policy,
            lastConnectedAt: lastConnectedAt,
            isInReconnectionCycle: reconnectionStartedAt != nil,
            totalReconnectionDuration: totalTimeInReconnection()
        )
    }
}
