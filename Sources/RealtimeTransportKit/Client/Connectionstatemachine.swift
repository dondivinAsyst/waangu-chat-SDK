//
//  Connectionstatemachine.swift
//  AppModules
//
//  Created by Asyst on 6/3/26.
//

// MARK: - RealtimeKit/Client/ConnectionStateMachine.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Machine à états formelle pour la connexion temps réel.
//           Valide les transitions, empêche les états incohérents,
//           et émet les changements via AsyncStream pour le RealtimeClient.
//
// Design  : Vit à l'intérieur de l'actor RealtimeClient (pas un actor lui-même).
//           Le RealtimeClient est le seul à muter l'état — thread safety garantie
//           par l'isolation de l'actor parent.
//
//           Transitions valides :
//           ┌──────────────────────────────────────────────────────┐
//           │  disconnected ──→ connecting ──→ authenticating      │
//           │       ↑                              │               │
//           │       │                              ↓               │
//           │       │◄──── reconnecting ◄──── connected            │
//           │       │                              │               │
//           │       │                              ↓               │
//           │       │◄─────────────────────── suspended            │
//           │       │                              │               │
//           │       │◄─── (any fatal error) ◄──────┘               │
//           └──────────────────────────────────────────────────────┘
//
// Pattern : Même rôle que le CircuitBreaker HTTP, mais pour une connexion
//           persistante avec des transitions formellement définies.

import Foundation
import WaanguCoreKit

// MARK: - ConnectionStateMachine

/// Machine à états de la connexion temps réel.
///
/// Garantit que seules les transitions valides sont effectuées.
/// Émet chaque changement d'état via un `AsyncStream` consommé par
/// le `RealtimeClient` et propagé vers les features.
///
/// **Non thread-safe en isolation** — conçue pour vivre à l'intérieur
/// de l'actor `RealtimeClient` qui garantit l'accès séquentiel.
final class ConnectionStateMachine: Sendable {

    // MARK: - State Storage

    /// État courant — lecture seule depuis l'extérieur.
    private(set) var currentState: RealtimeConnectionState

    /// Continuation pour émettre les changements d'état.
    private let continuation: AsyncStream<RealtimeConnectionState>.Continuation

    /// Stream public des changements d'état.
    let stateStream: AsyncStream<RealtimeConnectionState>

    /// Delegate pour les métriques (changements d'état).
    private let metricsDelegate: (any RealtimeMetricsDelegate)?

    // MARK: - Init

    /// Crée la machine à états dans l'état initial `.disconnected(.initial)`.
    init(metricsDelegate: (any RealtimeMetricsDelegate)? = nil) {
        self.currentState = .disconnected(reason: .initial)
        self.metricsDelegate = metricsDelegate

        // Créer le stream + continuation avant toute transition.
        var storedContinuation: AsyncStream<RealtimeConnectionState>.Continuation!
        self.stateStream = AsyncStream { continuation in
            storedContinuation = continuation
        }
        self.continuation = storedContinuation

        // Émettre l'état initial.
        storedContinuation.yield(.disconnected(reason: .initial))
    }

    deinit {
        continuation.finish()
    }

    // MARK: - Transitions

    /// Tente une transition vers un nouvel état.
    ///
    /// Si la transition est invalide, elle est ignorée et loggée.
    /// Si la transition est valide, l'état est mis à jour et émis sur le stream.
    ///
    /// - Parameter newState: L'état cible.
    /// - Returns: `true` si la transition a été effectuée.
    @discardableResult
    func transition(to newState: RealtimeConnectionState) -> Bool {
        guard isValidTransition(from: currentState, to: newState) else {
            logInvalidTransition(from: currentState, to: newState)
            return false
        }

        let previousState = currentState
        currentState = newState
        continuation.yield(newState)

        // Métriques
        Task { [metricsDelegate] in
            await metricsDelegate?.didChangeConnectionState(from: previousState, to: newState)
        }

        return true
    }

    /// Force une transition vers `.disconnected` — toujours valide depuis n'importe quel état.
    ///
    /// Utilisé pour les erreurs fatales (token expiré, config invalide)
    /// où la machine à états doit être reset sans vérification.
    func forceDisconnect(reason: DisconnectReason) {
        let previousState = currentState
        let newState = RealtimeConnectionState.disconnected(reason: reason)
        currentState = newState
        continuation.yield(newState)

        Task { [metricsDelegate] in
            await metricsDelegate?.didChangeConnectionState(from: previousState, to: newState)
        }
    }

    /// Reset la machine à l'état initial sans émettre d'événement.
    ///
    /// Utilisé uniquement lors du teardown/reconfiguration.
    func reset() {
        currentState = .disconnected(reason: .initial)
    }

    // MARK: - Transition Validation

    /// Vérifie si une transition est valide selon les règles de la machine à états.
    private func isValidTransition(
        from current: RealtimeConnectionState,
        to next: RealtimeConnectionState
    ) -> Bool {
        switch (current, next) {

        // --- FROM disconnected ---
        // On ne peut que commencer à se connecter.
        case (.disconnected, .connecting):
            return true

        // --- FROM connecting ---
        // Soit on passe à l'authentification, soit on échoue.
        case (.connecting, .authenticating):
            return true
        case (.connecting, .connected):
            // Certains transports n'ont pas de phase d'auth séparée.
            return true
        case (.connecting, .disconnected):
            return true

        // --- FROM authenticating ---
        // Soit l'auth réussit, soit elle échoue.
        case (.authenticating, .connected):
            return true
        case (.authenticating, .disconnected):
            return true

        // --- FROM connected ---
        // On peut se reconnecter, se suspendre, ou se déconnecter.
        case (.connected, .reconnecting):
            return true
        case (.connected, .suspended):
            return true
        case (.connected, .disconnected):
            return true

        // --- FROM reconnecting ---
        // On retente la connexion, on réussit, ou on abandonne.
        case (.reconnecting, .connecting):
            return true
        case (.reconnecting, .connected):
            // Reconnexion directe réussie (sans passer par connecting).
            return true
        case (.reconnecting, .reconnecting):
            // Incrémentation du compteur de tentatives.
            return true
        case (.reconnecting, .disconnected):
            // Max attempts atteint ou erreur fatale.
            return true

        // --- FROM suspended ---
        // Retour en foreground → on reconnecte.
        case (.suspended, .connecting):
            return true
        case (.suspended, .reconnecting):
            return true
        case (.suspended, .disconnected):
            return true

        // Toute autre transition est invalide.
        default:
            return false
        }
    }

    // MARK: - Logging

    private func logInvalidTransition(
        from: RealtimeConnectionState,
        to: RealtimeConnectionState
    ) {
        #if DEBUG
        print("[RealtimeKit] ⚠️ Invalid state transition: \(from.debugLabel) → \(to.debugLabel)")
        #endif
    }
}

// MARK: - Query Helpers

extension ConnectionStateMachine {

    /// `true` si la connexion est active et prête.
    var isConnected: Bool {
        currentState.isConnected
    }

    /// `true` si le client est en train de se connecter ou reconnecter.
    var isTransitioning: Bool {
        currentState.isTransitioning
    }

    /// `true` si le client peut accepter des messages sortants
    /// (connecté ou reconnecting avec offline queue).
    var canAcceptOutgoing: Bool {
        currentState.canAcceptOutgoingMessages
    }

    /// `true` si la machine est dans l'état initial (jamais connecté).
    var isInitial: Bool {
        if case .disconnected(let reason) = currentState, case .initial = reason {
            return true
        }
        return false
    }

    /// Le numéro de tentative de reconnexion courante, ou `nil`.
    var reconnectionAttempt: Int? {
        if case .reconnecting(let attempt, _) = currentState {
            return attempt
        }
        return nil
    }
}

// MARK: - Debug Labels

extension RealtimeConnectionState {

    /// Label court pour le debugging et le logging.
    var debugLabel: String {
        switch self {
        case .disconnected(let reason):
            return "disconnected(\(reason))"
        case .connecting:
            return "connecting"
        case .authenticating:
            return "authenticating"
        case .connected:
            return "connected"
        case .reconnecting(let attempt, let delay):
            return "reconnecting(attempt:\(attempt), nextIn:\(String(format: "%.1f", delay))s)"
        case .suspended(let reason):
            return "suspended(\(reason))"
        }
    }
}
