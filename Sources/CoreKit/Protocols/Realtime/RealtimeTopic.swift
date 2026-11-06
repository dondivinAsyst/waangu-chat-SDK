// MARK: - CoreKit/Realtime/RealtimeTopic.swift
//
// Module  : CoreKit
// Rôle    : Modèle de topic/channel pour le système temps réel.
//           Supporte le namespacing par feature, les wildcards, et la validation.
//           Aucune technologie — les wildcards sont traduites par chaque transport.
//
// Pattern : Value type immuable, Hashable pour usage dans des dictionnaires/sets.
// Design  : Le path est un string opaque. Le scoping ajoute un préfixe feature
//           pour éviter les collisions entre modules.

import Foundation

// MARK: - RealtimeTopic

/// Représente un canal de communication temps réel.
///
/// Les topics sont namespaced par feature pour garantir l'isolation.
/// Chaque transport (MQTT, WebSocket) traduit le path dans son format natif.
///
/// ```swift
/// // Namespaced — usage recommandé
/// let topic = RealtimeTopic.scoped(feature: "chat", path: "\(convId)/messages")
/// // → "chat/{convId}/messages"
///
/// // Wildcard — souscription à tous les sous-topics d'une feature
/// let all = RealtimeTopic.wildcard(feature: "chat")
/// // → "chat/#"
///
/// // Littéral — cas avancés uniquement
/// let raw: RealtimeTopic = "system/broadcasts"
/// ```


public enum RealtimeFeature : String {
    case chat
    case ride
    case wallet
}

public struct RealtimeTopic: Sendable, Hashable {

    /// Le chemin du topic (ex: "chat/abc123/messages").
    public let path: String

    /// Le nom de la feature propriétaire, s'il y a eu scoping.
    /// `nil` pour les topics littéraux non scopés.
    public let feature: RealtimeFeature?

    // MARK: - Init

    /// Crée un topic avec un path brut.
    /// Préférer `scoped(feature:path:)` pour le namespacing automatique.
    public init(_ path: String) {
        self.path = path
        self.feature = nil
    }

    /// Crée un topic scopé sous une feature.
    ///
    /// Le préfixe feature est ajouté automatiquement :
    /// `scoped(feature: "chat", path: "abc/messages")` → `"chat/abc/messages"`.
    ///
    /// - Parameters:
    ///   - feature: Identifiant de la feature (ex: "chat", "ride", "wallet").
    ///   - path: Sous-chemin relatif à la feature.
    /// - Returns: Un topic avec le path complet préfixé.
    public static func scoped(feature: RealtimeFeature, path: String) -> RealtimeTopic {
        RealtimeTopic(
            path: "\(feature.rawValue)/\(path)",
            feature: feature
        )
    }

    /// Crée un topic wildcard pour une feature entière.
    ///
    /// Utile pour souscrire à tous les événements d'une feature :
    /// `wildcard(feature: "chat")` → `"chat/#"`.
    ///
    /// Le caractère `#` est le wildcard multi-niveaux.
    /// Chaque transport le traduit dans son format natif.
    ///
    /// - Parameter feature: Identifiant de la feature.
    /// - Returns: Un topic wildcard.
    public static func wildcard(feature: RealtimeFeature) -> RealtimeTopic {
        RealtimeTopic(
            path: "\(feature.rawValue)/#",
            feature: feature
        )
    }

    /// Crée un topic single-level wildcard.
    ///
    /// `singleWildcard(feature: "chat", path: "+/messages")` → `"chat/+/messages"`.
    ///
    /// Le caractère `+` matche exactement un niveau.
    /// Ex: matche `chat/abc123/messages` mais pas `chat/abc/def/messages`.
    ///
    /// - Parameters:
    ///   - feature: Identifiant de la feature.
    ///   - path: Sous-chemin contenant `+` pour le wildcard.
    /// - Returns: Un topic avec single-level wildcard.
    public static func singleWildcard(feature: RealtimeFeature, path: String) -> RealtimeTopic {
        RealtimeTopic(
            path: "waangu-\(feature.rawValue)/\(path)",
            feature: feature
        )
    }

    // MARK: - Private init (with feature)

    private init(path: String, feature: RealtimeFeature?) {
        self.path = path
        self.feature = feature
    }
}

// MARK: - ExpressibleByStringLiteral

extension RealtimeTopic: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.path = value
        self.feature = nil
    }
}

// MARK: - CustomStringConvertible

extension RealtimeTopic: CustomStringConvertible {
    public var description: String { path }
}

// MARK: - Query Helpers

extension RealtimeTopic {

    /// `true` si le topic contient un wildcard (`#` ou `+`).
    public var isWildcard: Bool {
        path.contains("#") || path.contains("+")
    }

    /// `true` si le topic est un multi-level wildcard (`#`).
    public var isMultiLevelWildcard: Bool {
        path.contains("#")
    }

    /// Les segments du path séparés par `/`.
    public var segments: [String] {
        path.split(separator: "/").map(String.init)
    }

    /// Le nombre de niveaux dans le topic.
    public var depth: Int {
        segments.count
    }

    /// `true` si ce topic pourrait matcher un topic wildcard donné.
    ///
    /// Vérification locale simplifiée (le broker fait l'autorité).
    /// Utile pour le routing côté client (EventBus bridge, metrics filtering).
    ///
    /// - Parameter pattern: Le topic wildcard à tester.
    /// - Returns: `true` si le pattern matche ce topic.
    public func matches(pattern: RealtimeTopic) -> Bool {
        let topicParts = segments
        let patternParts = pattern.segments

        var ti = 0
        var pi = 0

        while pi < patternParts.count {
            let part = patternParts[pi]

            if part == "#" {
                // Multi-level wildcard → matche tout le reste
                return true
            }

            guard ti < topicParts.count else {
                return false
            }

            if part == "+" {
                // Single-level wildcard → matche exactement un segment
                ti += 1
                pi += 1
                continue
            }

            if part != topicParts[ti] {
                return false
            }

            ti += 1
            pi += 1
        }

        return ti == topicParts.count
    }
}

// MARK: - Codable

extension RealtimeTopic: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.path = try container.decode(String.self)
        self.feature = nil
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(path)
    }
}
