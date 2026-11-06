// MARK: - CoreKit/Realtime/RealtimePresence.swift
//
// Module  : CoreKit
// Rôle    : Système de presence (en ligne/hors ligne/typing) abstrait.
//           Aucun équivalent HTTP — spécifique au temps réel.
//
// Design  : PresenceState est l'état publié par l'utilisateur local.
//           PresenceInfo est l'état reçu d'un autre utilisateur (avec métadonnées).
//           Le multi-device est géré via deviceId dans PresenceInfo.

import Foundation

// MARK: - PresenceState

/// État de presence publiable par l'utilisateur local.
///
/// ```swift
/// // Publier que l'utilisateur est en train de taper
/// try await realtime.publishPresence(
///     .typing(in: conversationId),
///     to: .scoped(feature: "chat", path: "\(conversationId)/presence")
/// )
///
/// // Publier que l'utilisateur est en ligne
/// try await realtime.publishPresence(.online, to: presenceTopic)
/// ```
public enum PresenceState: Sendable, Equatable {

    /// L'utilisateur est en ligne et actif.
    case online

    /// L'utilisateur est hors ligne (déconnecté ou app fermée).
    case offline

    /// L'utilisateur est inactif depuis un moment (app en background, pas d'interaction).
    case away(since: Date)

    /// L'utilisateur est en train de taper dans un contexte donné.
    /// - Parameter context: identifiant du contexte (ex: conversationId).
    case typing(in: String)

    /// État custom extensible pour les features qui ont besoin de presence spécifique.
    /// Ex: "in_call", "recording_voice", "viewing_map".
    case custom(key: String, value: String?)
}

// MARK: - PresenceState + Codable

extension PresenceState: Codable {

    private enum CodingKeys: String, CodingKey {
        case type, since, context, key, value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "online":
            self = .online
        case "offline":
            self = .offline
        case "away":
            let since = try container.decode(Date.self, forKey: .since)
            self = .away(since: since)
        case "typing":
            let context = try container.decode(String.self, forKey: .context)
            self = .typing(in: context)
        case "custom":
            let key = try container.decode(String.self, forKey: .key)
            let value = try container.decodeIfPresent(String.self, forKey: .value)
            self = .custom(key: key, value: value)
        default:
            self = .custom(key: type, value: nil)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .online:
            try container.encode("online", forKey: .type)
        case .offline:
            try container.encode("offline", forKey: .type)
        case .away(let since):
            try container.encode("away", forKey: .type)
            try container.encode(since, forKey: .since)
        case .typing(let context):
            try container.encode("typing", forKey: .type)
            try container.encode(context, forKey: .context)
        case .custom(let key, let value):
            try container.encode("custom", forKey: .type)
            try container.encode(key, forKey: .key)
            try container.encodeIfPresent(value, forKey: .value)
        }
    }
}

// MARK: - PresenceInfo

/// Informations de presence reçues d'un autre utilisateur.
///
/// Contient l'état, les métadonnées temporelles, et le deviceId
/// pour le multi-device (iPhone + iPad connectés simultanément).
///
/// ```swift
/// for await presence in realtime.observePresence(on: presenceTopic) {
///     switch presence.state {
///     case .typing(let context) where context == conversationId:
///         showTypingIndicator(for: presence.userId)
///     case .online:
///         markUserOnline(presence.userId)
///     default:
///         break
///     }
/// }
/// ```
public struct PresenceInfo: Sendable, Equatable, Codable {

    /// Identifiant de l'utilisateur.
    public let userId: String

    /// État de presence actuel.
    public let state: PresenceState

    /// Dernière activité connue de cet utilisateur.
    public let lastSeen: Date

    /// Identifiant du device d'où provient cet état.
    /// Permet de distinguer les connexions multi-device.
    public let deviceId: String?

    // MARK: - Init

    public init(
        userId: String,
        state: PresenceState,
        lastSeen: Date,
        deviceId: String? = nil
    ) {
        self.userId = userId
        self.state = state
        self.lastSeen = lastSeen
        self.deviceId = deviceId
    }
}

// MARK: - Identifiable

extension PresenceInfo: Identifiable {
    /// Identité composite : userId + deviceId pour le multi-device.
    public var id: String {
        if let deviceId {
            return "\(userId):\(deviceId)"
        }
        return userId
    }
}

// MARK: - Convenience

extension PresenceInfo {

    /// `true` si l'utilisateur est considéré comme actif (online ou typing).
    public var isActive: Bool {
        switch state {
        case .online, .typing:
            return true
        default:
            return false
        }
    }

    /// `true` si l'utilisateur est en train de taper.
    public var isTyping: Bool {
        if case .typing = state { return true }
        return false
    }

    /// Durée depuis la dernière activité.
    public func timeSinceLastSeen(from now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(lastSeen)
    }
}
