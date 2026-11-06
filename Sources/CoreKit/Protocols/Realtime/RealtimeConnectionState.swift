// MARK: - CoreKit/Realtime/RealtimeConnectionState.swift
//
// Module  : CoreKit
// Rôle    : Machine à états de la connexion temps réel.
//           Observable par les features pour adapter l'UI
//           (banner "reconnexion...", désactiver bouton envoyer, etc.).
//
// Design  : Enum avec associated values pour porter le contexte de chaque état.
//           Equatable pour les comparaisons directes dans les ViewModels.
//           Aucune technologie — les transports mappent leurs états vers ces cas.
//
// Pattern : Équivalent conceptuel du CircuitBreaker HTTP, mais pour une
//           connexion persistante unique avec des transitions formelles.
//
// Transitions valides :
//   disconnected → connecting → authenticating → connected
//   connected → reconnecting → connecting → ...
//   connected → suspended (background iOS)
//   suspended → connecting (retour foreground)
//   * → disconnected (erreur fatale ou user-initiated)

import Foundation

// MARK: - RealtimeConnectionState

/// État courant de la connexion temps réel.
///
/// Les features observent cet état via `observeConnectionState()` pour adapter l'UI.
///
/// ```swift
/// for await state in realtime.observeConnectionState() {
///     switch state {
///     case .connected:
///         hideBanner()
///     case .reconnecting(let attempt, let nextRetry):
///         showBanner("Reconnexion (\(attempt))… retry dans \(Int(nextRetry))s")
///     case .disconnected(let reason):
///         showBanner("Déconnecté : \(reason)")
///     default:
///         break
///     }
///  }
/// ```
public enum RealtimeConnectionState: Sendable {

    /// Pas de connexion active.
    /// Le `reason` indique pourquoi (déconnexion volontaire, erreur, etc.).
    case disconnected(reason: DisconnectReason)

    /// Connexion TCP/TLS en cours d'établissement.
    case connecting

    /// Connexion TCP établie, authentification en cours (MQTT CONNECT, WS handshake auth).
    case authenticating

    /// Connexion établie et authentifiée — prêt à publier/souscrire.
    case connected

    /// Connexion perdue, reconnexion automatique en cours.
    /// - `attempt`: numéro de la tentative courante (1-based).
    /// - `nextRetryIn`: secondes avant la prochaine tentative.
    case reconnecting(attempt: Int, nextRetryIn: TimeInterval)

    /// Connexion suspendue (iOS background, throttle thermique).
    /// Le client reprendra automatiquement au retour en foreground.
    case suspended(reason: SuspendReason)
}

// MARK: - Equatable (manual — TimeInterval comparison with tolerance)

extension RealtimeConnectionState: Equatable {
    public static func == (lhs: RealtimeConnectionState, rhs: RealtimeConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected(let l), .disconnected(let r)):
            return l == r
        case (.connecting, .connecting):
            return true
        case (.authenticating, .authenticating):
            return true
        case (.connected, .connected):
            return true
        case (.reconnecting(let la, _), .reconnecting(let ra, _)):
            // On compare l'attempt, pas le delay (qui est un calcul dynamique)
            return la == ra
        case (.suspended(let l), .suspended(let r)):
            return l == r
        default:
            return false
        }
    }
}

// MARK: - DisconnectReason

/// Raison de la déconnexion.
///
/// Permet aux features de distinguer une déconnexion volontaire (logout)
/// d'une perte réseau ou d'une erreur d'authentification.
public enum DisconnectReason: Sendable, Equatable {

    /// L'utilisateur ou la feature a demandé la déconnexion (logout, écran quitté).
    case userInitiated

    /// Le réseau est devenu indisponible (WiFi + Cellular perdus).
    case networkLost

    /// Le broker/serveur a fermé la connexion.
    case serverClosed(code: Int?)

    /// Le token JWT a expiré et le refresh a échoué.
    case tokenExpired

    /// Erreur de protocole (MQTT malformé, WS frame invalide).
    case protocolError(description: String)

    /// iOS a suspendu l'app en background et la connexion a été fermée.
    case backgroundSuspended

    /// Tous les transports de la fallback chain ont échoué.
    case allTransportsFailed

    /// La configuration est invalide (host, port, credentials).
    case invalidConfiguration

    /// Jamais connecté — état initial au lancement.
    case initial
}

// MARK: - SuspendReason

/// Raison de la suspension (état `.suspended`).
public enum SuspendReason: Sendable, Equatable {

    /// L'app est passée en background iOS.
    case backgrounded

    /// Le device est en état thermique critique — connexion réduite.
    case thermalThrottling

    /// Le device est en Low Power Mode — connexion réduite.
    case lowPowerMode
}

// MARK: - Convenience Properties

extension RealtimeConnectionState {

    /// `true` si le client est connecté et prêt à envoyer/recevoir.
    public var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    /// `true` si le client tente activement de se connecter ou reconnecter.
    public var isTransitioning: Bool {
        switch self {
        case .connecting, .authenticating, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// `true` si le client peut accepter des messages à envoyer
    /// (connecté, ou reconnecting avec offline queue active).
    public var canAcceptOutgoingMessages: Bool {
        switch self {
        case .connected, .reconnecting:
            return true
        default:
            return false
        }
    }

    /// `true` si l'état indique une situation d'erreur qui nécessite une action utilisateur.
    public var requiresUserAction: Bool {
        if case .disconnected(let reason) = self {
            switch reason {
            case .tokenExpired, .invalidConfiguration:
                return true
            default:
                return false
            }
        }
        return false
    }

    /// Description courte pour l'UI (banners, status indicators).
    public var displayDescription: String {
        switch self {
        case .disconnected(let reason):
            switch reason {
            case .initial:                  return "Non connecté"
            case .userInitiated:            return "Déconnecté"
            case .networkLost:              return "Réseau indisponible"
            case .serverClosed:             return "Serveur indisponible"
            case .tokenExpired:             return "Session expirée"
            case .protocolError:            return "Erreur de connexion"
            case .backgroundSuspended:      return "Suspendu"
            case .allTransportsFailed:      return "Connexion impossible"
            case .invalidConfiguration:     return "Configuration invalide"
            }
        case .connecting:
            return "Connexion…"
        case .authenticating:
            return "Authentification…"
        case .connected:
            return "Connecté"
        case .reconnecting(let attempt, _):
            return "Reconnexion (\(attempt))…"
        case .suspended(let reason):
            switch reason {
            case .backgrounded:             return "En arrière-plan"
            case .thermalThrottling:        return "Réduit (thermique)"
            case .lowPowerMode:             return "Réduit (économie d'énergie)"
            }
        }
    }
}
