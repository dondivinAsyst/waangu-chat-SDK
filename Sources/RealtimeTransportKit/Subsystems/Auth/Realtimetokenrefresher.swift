//
//  Realtimetokenrefresher.swift
//  AppModules
//
//  Created by Asyst on 6/3/26.
//

// MARK: - RealtimeKit/Auth/RealtimeTokenRefresher.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Refresh proactif du JWT sur une connexion temps réel vivante.
//           DIFFÉRENT du refresh HTTP : en HTTP, on refresh entre deux requêtes.
//           En realtime, la connexion est ouverte et le JWT expire PENDANT la session.
//
// Flow proactif :
//   1. Le RealtimeClient passe les credentials initiales à startMonitoring()
//   2. Le refresher calcule : refreshAt = expiresAt - threshold
//   3. Il dort jusqu'à refreshAt
//   4. Il appelle delegate.realtimeClientNeedsToken() pour un nouveau token
//   5. Il notifie le RealtimeClient via onNewCredentials
//   6. Le RealtimeClient ré-authentifie sur la connexion existante
//   7. Le refresher recommence le cycle avec les nouveaux credentials
//
// Flow réactif (fallback) :
//   Si le broker rejette le token (TransportConnectionEvent.authenticationRejected),
//   le RealtimeClient appelle refreshNow() pour déclencher un refresh immédiat.
//
// Design  : Pas un actor — c'est une classe utilitaire qui lance des Tasks.
//           Le cycle de monitoring vit dans une Task détenue par le RealtimeClient.
//           Thread safety assurée par l'actor RealtimeClient parent.

import Foundation
import WaanguCoreKit

// MARK: - RealtimeTokenRefresher

/// Surveille l'expiration du JWT et déclenche le refresh proactif.
///
/// En HTTP, le token est rafraîchi entre deux requêtes indépendantes.
/// En realtime, la connexion persiste et le token expire pendant la session.
/// Le refresher anticipe l'expiration et renouvelle avant la coupure.
///
/// ```swift
/// // Utilisé dans RealtimeClient.startTokenRefreshMonitoring() :
/// await tokenRefresher.startMonitoring(
///     credentials: credentials,
///     delegate: authDelegate,
///     onNewCredentials: { newCredentials in
///         let success = try await transport.reauthenticate(with: newCredentials)
///         if !success { /* reconnect */ }
///     }
/// )
/// ```
final class RealtimeTokenRefresher: Sendable {

    // MARK: - Configuration

    /// Durée avant l'expiration à laquelle déclencher le refresh.
    /// Ex: 60s → le refresh est déclenché 60 secondes avant l'expiry du JWT.
    private let threshold: TimeInterval

    /// Nombre maximum de tentatives en cas d'échec du refresh.
    private let maxRetries: Int

    /// Délai de base entre les retries (exponential backoff).
    private let retryBaseDelay: TimeInterval

    // MARK: - Init

    /// Crée un token refresher.
    ///
    /// - Parameters:
    ///   - threshold: Secondes avant expiration pour déclencher le refresh.
    ///   - maxRetries: Tentatives max si le refresh échoue.
    ///   - retryBaseDelay: Délai de base entre les retries.
    init(
        threshold: TimeInterval = 60,
        maxRetries: Int = 3,
        retryBaseDelay: TimeInterval = 2.0
    ) {
        self.threshold = threshold
        self.maxRetries = maxRetries
        self.retryBaseDelay = retryBaseDelay
    }

    // MARK: - Monitoring

    /// Démarre la surveillance proactive du token.
    ///
    /// Cette méthode boucle indéfiniment (jusqu'à annulation de la Task parente).
    /// À chaque cycle :
    /// 1. Calcule quand le token doit être rafraîchi
    /// 2. Dort jusqu'à ce moment
    /// 3. Demande un nouveau token au delegate
    /// 4. Notifie le RealtimeClient via le callback
    /// 5. Recommence avec les nouveaux credentials
    ///
    /// - Parameters:
    ///   - credentials: Les credentials initiales (avec expiresAt pour le calcul).
    ///   - delegate: Le delegate qui fournit les nouveaux tokens.
    ///   - onNewCredentials: Callback appelé avec les credentials frais.
    ///                       Le RealtimeClient ré-authentifie sur la connexion vivante.
    func startMonitoring(
        credentials: RealtimeCredentials,
        delegate: any RealtimeAuthDelegate,
        onNewCredentials: @Sendable @escaping (RealtimeCredentials) async throws -> Void
    ) async {
        var currentCredentials = credentials

        // Boucle de monitoring — tourne jusqu'à annulation de la Task.
        while !Task.isCancelled {

            // 1. Calculer le délai avant le prochain refresh.
            let sleepDuration = timeUntilRefresh(for: currentCredentials)

            guard let sleepDuration else {
                // Pas de expiresAt → pas de refresh proactif possible.
                // On attend un signal réactif (broker rejection).
                // Dormir longtemps et re-vérifier périodiquement.
                await sleepOrCancel(seconds: 300)  // 5 min check interval
                continue
            }

            // 2. Dormir jusqu'au moment du refresh.
            if sleepDuration > 0 {
                let interrupted = await sleepOrCancel(seconds: sleepDuration)
                if interrupted { return }
            }

            // 3. Rafraîchir le token (avec retries).
            let result = await attemptRefresh(
                delegate: delegate,
                onNewCredentials: onNewCredentials
            )

            switch result {
            case .success(let newCredentials):
                currentCredentials = newCredentials

            case .failure:
                // Tous les retries ont échoué → signaler au delegate.
                await delegate.realtimeClientDidFailAuthentication(
                    error: .tokenRefreshFailed(
                        underlyingReason: "Proactive refresh failed after \(maxRetries) retries"
                    )
                )
                // Arrêter le monitoring — le RealtimeClient gérera
                // la déconnexion via handleTransportEvent(.authenticationRejected).
                return
            }
        }
    }

    // MARK: - Refresh immédiat (réactif)

    /// Déclenche un refresh immédiat du token.
    ///
    /// Appelé par le RealtimeClient quand le broker rejette le token courant
    /// (TransportConnectionEvent.authenticationRejected).
    ///
    /// - Parameters:
    ///   - delegate: Le delegate qui fournit le nouveau token.
    ///   - onNewCredentials: Callback avec les credentials frais.
    /// - Returns: Les nouveaux credentials, ou `nil` si le refresh a échoué.
    func refreshNow(
        delegate: any RealtimeAuthDelegate,
        onNewCredentials: @Sendable @escaping (RealtimeCredentials) async throws -> Void
    ) async -> RealtimeCredentials? {
        let result = await attemptRefresh(
            delegate: delegate,
            onNewCredentials: onNewCredentials
        )
        switch result {
        case .success(let credentials):
            return credentials
        case .failure:
            return nil
        }
    }

    // MARK: - Private — Refresh Logic

    /// Tente de rafraîchir le token avec retries et exponential backoff.
    private func attemptRefresh(
        delegate: any RealtimeAuthDelegate,
        onNewCredentials: @Sendable @escaping (RealtimeCredentials) async throws -> Void
    ) async -> RefreshResult {

        for attempt in 1...maxRetries {
            guard !Task.isCancelled else { return .failure }

            do {
                // Demander un nouveau token au delegate (→ AuthKit).
                let newCredentials = try await delegate.realtimeClientNeedsToken()

                // Notifier le RealtimeClient pour ré-authentifier.
                try await onNewCredentials(newCredentials)

                #if DEBUG
                print("[RealtimeKit] Token refreshed proactively (attempt \(attempt))")
                #endif

                return .success(newCredentials)

            } catch {
                #if DEBUG
                print("[RealtimeKit] Token refresh attempt \(attempt)/\(maxRetries) failed: \(error)")
                #endif

                // Exponential backoff avant le retry.
                if attempt < maxRetries {
                    let delay = retryBaseDelay * pow(2.0, Double(attempt - 1))
                    let interrupted = await sleepOrCancel(seconds: delay)
                    if interrupted { return .failure }
                }
            }
        }

        return .failure
    }

    // MARK: - Private — Timing

    /// Calcule le temps restant avant de déclencher le refresh.
    ///
    /// - Parameter credentials: Les credentials avec expiresAt.
    /// - Returns: Secondes avant le refresh, ou `nil` si pas de expiresAt.
    ///            Retourne `0` si le token est déjà expiré ou bientôt expiré.
    private func timeUntilRefresh(for credentials: RealtimeCredentials) -> TimeInterval? {
        guard let expiresAt = credentials.expiresAt else {
            return nil
        }

        let now = Date()
        let refreshAt = expiresAt.addingTimeInterval(-threshold)
        let remaining = refreshAt.timeIntervalSince(now)

        // Si le moment du refresh est déjà passé → refresh immédiat.
        return max(remaining, 0)
    }

    // MARK: - Private — Sleep Helper

    /// Dort pendant la durée donnée, ou retourne `true` si la Task a été annulée.
    @discardableResult
    private func sleepOrCancel(seconds: TimeInterval) async -> Bool {
        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            return false
        } catch {
            // CancellationError → la Task parente a été annulée.
            return true
        }
    }
}

// MARK: - RefreshResult

/// Résultat interne d'une tentative de refresh.
private enum RefreshResult {
    case success(RealtimeCredentials)
    case failure
}
