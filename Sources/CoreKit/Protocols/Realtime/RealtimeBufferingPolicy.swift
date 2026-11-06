// MARK: - CoreKit/Realtime/RealtimeBufferingPolicy.swift
//
// Module  : CoreKit
// Rôle    : Stratégies de backpressure pour les souscriptions temps réel.
//           Aucun équivalent dans NetworkKit (HTTP est request/response one-shot).
//
// Design  : En realtime, un topic peut pousser 60 messages/seconde (GPS tracking).
//           Sans buffering policy, l'AsyncStream explose la mémoire ou drop
//           silencieusement. Chaque souscription déclare sa stratégie.
//
// Pattern : Enum avec associated values pour la configuration.
//           Utilisé dans subscribe() et dans TopicRegistration.

import Foundation

// MARK: - RealtimeBufferingPolicy

/// Stratégie de backpressure pour une souscription temps réel.
///
/// Chaque souscription déclare comment gérer les messages entrants
/// quand le consommateur est plus lent que le producteur.
///
/// ```swift
/// // Chat : chaque message est important → unbounded
/// realtime.subscribe(to: topic, as: ChatMessage.self, buffering: .unbounded)
///
/// // GPS tracking : seule la dernière position compte → throttle
/// realtime.subscribe(to: topic, as: Position.self, buffering: .throttle(interval: 0.5))
///
/// // Typing indicator : attendre la stabilisation → debounce
/// realtime.subscribe(to: topic, as: TypingEvent.self, buffering: .debounce(interval: 1.0))
/// ```
public enum RealtimeBufferingPolicy: Sendable, Equatable {

    /// Aucune limite — tous les messages sont conservés dans le buffer.
    ///
    /// Usage : volumes faibles où chaque message est critique (chat messages, notifications).
    /// ⚠️ Risque mémoire si le consommateur ne suit pas. À utiliser uniquement
    /// quand le volume est garanti faible ou quand la perte de message est inacceptable.
    case unbounded

    /// Conserve les N messages les plus récents, drop les anciens.
    ///
    /// Usage : haute fréquence où seul l'état le plus récent compte
    /// (dernière position GPS, dernier statut).
    ///
    /// - Parameter count: nombre maximum de messages dans le buffer.
    case bufferNewest(Int)

    /// Conserve les N premiers messages, drop les nouveaux qui arrivent quand le buffer est plein.
    ///
    /// Usage : historique où les premiers messages ont plus de valeur
    /// (premiers résultats d'une recherche temps réel).
    ///
    /// - Parameter count: nombre maximum de messages dans le buffer.
    case bufferOldest(Int)

    /// Limite à maximum 1 message par intervalle. Les messages intermédiaires sont droppés.
    ///
    /// Usage : flux haute fréquence avec besoin d'échantillonnage régulier
    /// (GPS à 60Hz réduit à 2Hz pour l'affichage carte).
    ///
    /// - Parameter interval: intervalle minimum entre deux messages délivrés (en secondes).
    case throttle(interval: TimeInterval)

    /// Attend que le flux se stabilise avant de délivrer le dernier message.
    /// Reset le timer à chaque nouveau message.
    ///
    /// Usage : événements "en train de" qui se terminent par un silence
    /// (typing indicators, recherche en temps réel).
    ///
    /// - Parameter interval: durée de silence requise avant de délivrer (en secondes).
    case debounce(interval: TimeInterval)
}

// MARK: - AsyncStream Mapping

extension RealtimeBufferingPolicy {

    /// Convertit vers la `AsyncStream.Continuation.BufferingPolicy` native de Swift.
    ///
    /// Note : throttle et debounce ne sont pas directement supportés par AsyncStream.
    /// Ils sont implémentés dans RealtimeKit au-dessus de l'AsyncStream.
    /// Cette conversion ne couvre que les cas buffer-based.
    public var asyncStreamPolicy: AsyncStream<Any>.Continuation.BufferingPolicy {
        switch self {
        case .unbounded:
            return .unbounded
        case .bufferNewest(let count):
            return .bufferingNewest(count)
        case .bufferOldest(let count):
            return .bufferingOldest(count)
        case .throttle, .debounce:
            // Throttle et debounce utilisent un buffer interne géré par RealtimeKit.
            // On utilise bufferNewest(1) comme base pour ne garder que le dernier.
            return .bufferingNewest(1)
        }
    }

    /// `true` si cette policy nécessite un traitement temporel dans RealtimeKit
    /// (throttle ou debounce) au-delà du simple buffering natif d'AsyncStream.
    public var requiresTemporalProcessing: Bool {
        switch self {
        case .throttle, .debounce:
            return true
        case .unbounded, .bufferNewest, .bufferOldest:
            return false
        }
    }
}

// MARK: - Defaults

extension RealtimeBufferingPolicy {

    /// Policy par défaut pour les messages critiques (chat, notifications).
    public static let `default`: RealtimeBufferingPolicy = .unbounded

    /// Policy recommandée pour le tracking haute fréquence (GPS, sensors).
    public static let highFrequencyTracking: RealtimeBufferingPolicy = .throttle(interval: 0.5)

    /// Policy recommandée pour les indicateurs d'activité (typing, presence).
    public static let activityIndicator: RealtimeBufferingPolicy = .debounce(interval: 1.0)
}
