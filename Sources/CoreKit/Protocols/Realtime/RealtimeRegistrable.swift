// MARK: - CoreKit/Realtime/RealtimeRegistrable.swift
//
// Module  : CoreKit
// Rôle    : Chaque feature déclare ses topics, leurs QoS, background policy,
//           buffering policy, et priorité. Même pattern que DatabaseRegistrable
//           pour la database.
//
// Design  : Le DependencyContainer collecte tous les RealtimeRegistrable
//           au bootstrap et les enregistre dans le RealtimeClient.
//           Le BackgroundPolicyManager et l'AdaptiveRealtimePolicy
//           utilisent ces déclarations pour adapter le comportement.
//
// Pattern :
//   public protocol DatabaseRegistrable {
//       static var storableTypes: [any Storable.Type] { get }
//       static var migrationSteps: [any MigrationStep] { get }
//   }
//   →
//   public protocol RealtimeRegistrable {
//       static var topicRegistrations: [TopicRegistration] { get }
//   }

import Foundation

// MARK: - RealtimeRegistrable

/// Chaque feature conforme à ce protocol déclare ses topics temps réel.
///
/// Utilisé au bootstrap pour :
/// - Enregistrer les topics attendus dans le RealtimeClient
/// - Configurer le BackgroundPolicyManager (quels topics garder en background)
/// - Configurer l'AdaptiveRealtimePolicy (buffer sizes par feature)
/// - Valider les souscriptions (topic ACL côté client)
///
/// ```swift
/// // FeatureChat
/// extension ChatModule: RealtimeRegistrable {
///     public static var topicRegistrations: [TopicRegistration] {
///         [
///             TopicRegistration(
///                 topicPattern: .singleWildcard(feature: "chat", path: "+/messages"),
///                 qos: .atLeastOnce,
///                 backgroundPolicy: .disconnect,
///                 bufferingPolicy: .unbounded,
///                 priority: .normal
///             ),
///             TopicRegistration(
///                 topicPattern: .singleWildcard(feature: "chat", path: "+/presence"),
///                 qos: .fireAndForget,
///                 backgroundPolicy: .disconnect,
///                 bufferingPolicy: .activityIndicator,
///                 priority: .low
///             )
///         ]
///     }
/// }
/// ```
public protocol RealtimeRegistrable {
    
    static var topicRegistrations: [TopicRegistration] { get }
}

// MARK: - TopicRegistration

/// Déclaration d'un topic par une feature.
///
/// Porte toutes les policies qui s'appliquent à ce topic.
/// Le RealtimeClient et ses sous-systèmes lisent ces déclarations
/// pour adapter leur comportement.
public struct TopicRegistration: Sendable {

    /// Pattern du topic (peut contenir des wildcards `+` et `#`).
    public let topicPattern: RealtimeTopic

    /// QoS par défaut pour les souscriptions à ce topic.
    /// Les features peuvent override au moment du subscribe().
    public let qos: RealtimeQoS

    /// Comportement en background iOS.
    public let backgroundPolicy: TopicBackgroundPolicy

    /// Stratégie de backpressure par défaut.
    /// Les features peuvent override au moment du subscribe().
    public let bufferingPolicy: RealtimeBufferingPolicy

    /// Priorité par défaut des messages sur ce topic.
    public let priority: MessagePriority

    /// Description humaine pour le logging et le debugging.
    public let description: String?

    // MARK: - Init

    public init(
        topicPattern: RealtimeTopic,
        qos: RealtimeQoS = .atLeastOnce,
        backgroundPolicy: TopicBackgroundPolicy = .disconnect,
        bufferingPolicy: RealtimeBufferingPolicy = .default,
        priority: MessagePriority = .normal,
        description: String? = nil
    ) {
        self.topicPattern = topicPattern
        self.qos = qos
        self.backgroundPolicy = backgroundPolicy
        self.bufferingPolicy = bufferingPolicy
        self.priority = priority
        self.description = description
    }
}

// MARK: - TopicBackgroundPolicy

/// Politique de comportement d'un topic quand l'app passe en background iOS.
///
/// Sur iOS, l'app est suspendue ~30 secondes après le passage en background.
/// Chaque topic doit déclarer ce qu'il attend :
///
/// - `.disconnect` : couper la souscription en background (chat quand l'écran est fermé)
/// - `.maintainBriefly` : garder la connexion via `beginBackgroundTask` (~30s)
/// - `.keepAlive` : maintenir via `BGAppRefreshTask` (notifications critiques)
/// - `.reducedFrequency` : réduire le débit (GPS tracking : 1/s → 1/30s)
public enum TopicBackgroundPolicy: Sendable, Equatable {

    /// Couper la souscription en background. Reprendre au retour en foreground.
    /// Usage : chat messages, typing indicators, UI updates.
    case disconnect

    /// Maintenir la souscription brièvement via `UIApplication.beginBackgroundTask`.
    /// Durée : ~30 secondes avant suspension iOS.
    /// Usage : ride tracking pendant une course active, livraison en cours.
    case maintainBriefly

    /// Maintenir la souscription via `BGAppRefreshTask`.
    /// Rafraîchissement périodique contrôlé par iOS (intervalle non garanti).
    /// Usage : notifications de transaction critique, alertes sécurité.
    case keepAlive

    /// Réduire la fréquence de réception en background.
    /// - Parameter factor: Facteur de réduction (ex: 30 = 30x moins fréquent).
    /// Usage : GPS tracking (passer de 1 update/s à 1 update/30s).
    case reducedFrequency(factor: Int)
}

// MARK: - TopicRegistration Helpers

extension TopicRegistration {

    /// `true` si ce topic doit rester actif en background.
    public var staysActiveInBackground: Bool {
        switch backgroundPolicy {
        case .disconnect:
            return false
        case .maintainBriefly, .keepAlive, .reducedFrequency:
            return true
        }
    }

    /// Le nom de la feature déduit du topicPattern.
    public var featureName: String? {
        topicPattern.feature?.rawValue
    }
}

// MARK: - Collection Helpers

extension Array where Element == TopicRegistration {

    /// Filtre les registrations qui doivent rester actives en background.
    public var backgroundActive: [TopicRegistration] {
        filter(\.staysActiveInBackground)
    }

    /// Filtre les registrations pour une feature donnée.
    public func forFeature(_ feature: RealtimeFeature) -> [TopicRegistration] {
        filter { $0.topicPattern.feature?.rawValue == feature.rawValue }
    }

    /// Les topics uniques dans cette collection de registrations.
    public var topics: [RealtimeTopic] {
        map(\.topicPattern)
    }
}
