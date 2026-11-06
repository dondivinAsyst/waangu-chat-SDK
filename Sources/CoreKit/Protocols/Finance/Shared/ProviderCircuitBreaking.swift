//
//  ProviderCircuitBreaking.swift
//  CoreKit
//
//  Coupe-circuit par fournisseur — Bloc 4 §21 (GAP-11).
//

import Foundation

/// État d'un coupe-circuit pour un couple (fournisseur, opération).
///
/// `NetworkKit` porte déjà un `CircuitBreakerService`, mais **global au
/// client** : un fournisseur en panne ferait alors basculer les appels vers
/// tous les autres. La segmentation est ce qui distingue « REGIDESO ne répond
/// plus » de « le réseau est coupé ».
public enum ProviderCircuitState: String, Codable, Sendable, Equatable {
    case closed, open, halfOpen

    /// `true` si une tentative est permise.
    ///
    /// `halfOpen` laisse passer **une** tentative de sondage : c'est ce qui
    /// permet de refermer le circuit sans attendre qu'un humain le fasse.
    public var allowsAttempt: Bool { self != .open }
}

/// Clé de segmentation.
///
/// Le couple, pas le seul fournisseur : chez un même opérateur, la consultation
/// de facture peut répondre alors que l'exécution de paiement est tombée.
/// Fermer les deux sur un échec de l'une prive l'utilisateur d'une information
/// qui, elle, fonctionne.
public struct ProviderCircuitKey: Hashable, Sendable, Codable {
    public let providerID: String
    public let operation: String

    public init(providerID: String, operation: String) {
        self.providerID = providerID
        self.operation = operation
    }
}

/// Politique de coupure. **BACKEND SOURCE OF TRUTH** pour les seuils.
public struct ProviderCircuitPolicy: Sendable, Codable, Hashable {

    public let failureThreshold: Int
    public let openDuration: TimeInterval
    /// Succès consécutifs requis en `halfOpen` pour refermer.
    public let successesToClose: Int

    public init(failureThreshold: Int = 5, openDuration: TimeInterval = 30,
                successesToClose: Int = 2) {
        self.failureThreshold = failureThreshold
        self.openDuration = openDuration
        self.successesToClose = successesToClose
    }

    /// Repli conservateur : ouvre vite, referme prudemment.
    public static let `default` = ProviderCircuitPolicy()
}

/// Coupe-circuit segmenté, pur et testable.
public actor ProviderCircuitBreaker {

    private struct Entry {
        var state: ProviderCircuitState = .closed
        var consecutiveFailures = 0
        var consecutiveSuccesses = 0
        var openedAt: Date?
    }

    private var entries: [ProviderCircuitKey: Entry] = [:]
    private let policy: ProviderCircuitPolicy

    public init(policy: ProviderCircuitPolicy = .default) {
        self.policy = policy
    }

    /// L'état courant, en tenant compte du temps écoulé.
    public func state(for key: ProviderCircuitKey, now: Date = Date()) -> ProviderCircuitState {
        guard let entry = entries[key] else { return .closed }

        // Le passage `open → halfOpen` est fonction du temps, pas d'un
        // événement : sans lui, un circuit ouvert le resterait jusqu'à ce que
        // quelqu'un tente un appel — c'est-à-dire jamais, puisqu'il est ouvert.
        if entry.state == .open, let openedAt = entry.openedAt,
           now.timeIntervalSince(openedAt) >= policy.openDuration {
            return .halfOpen
        }
        return entry.state
    }

    public func allowsAttempt(for key: ProviderCircuitKey, now: Date = Date()) -> Bool {
        state(for: key, now: now).allowsAttempt
    }

    public func recordSuccess(for key: ProviderCircuitKey, now: Date = Date()) {
        var entry = entries[key] ?? Entry()
        let effective = state(for: key, now: now)

        entry.consecutiveFailures = 0

        if effective == .halfOpen {
            entry.consecutiveSuccesses += 1
            if entry.consecutiveSuccesses >= policy.successesToClose {
                entry = Entry()  // refermé, compteurs remis à zéro
            } else {
                entry.state = .halfOpen
                entry.openedAt = nil
            }
        } else {
            entry = Entry()
        }
        entries[key] = entry
    }

    public func recordFailure(for key: ProviderCircuitKey, now: Date = Date()) {
        var entry = entries[key] ?? Entry()
        entry.consecutiveSuccesses = 0
        entry.consecutiveFailures += 1

        // Un échec en sondage rouvre immédiatement : le fournisseur n'est pas
        // rétabli, et insister ne ferait qu'allonger l'incident.
        if state(for: key, now: now) == .halfOpen || entry.consecutiveFailures >= policy.failureThreshold {
            entry.state = .open
            entry.openedAt = now
        }
        entries[key] = entry
    }

    /// Remise à zéro — changement de compte, kill switch levé.
    public func reset() { entries.removeAll() }

    /// Fournisseurs actuellement coupés, pour l'observabilité.
    public func openCircuits(now: Date = Date()) -> [ProviderCircuitKey] {
        entries.keys.filter { state(for: $0, now: now) == .open }
    }
}
