//
//  ChatMetrics.swift
//  FeatureChat
//
//  Plan SDK, étape 1.13 — mesures du Chat remises à l'hôte (spec §16.2).
//

import Foundation

/// Une mesure du Chat, **sans contenu** : un nom, une durée, quelques attributs de
/// nature ou de résultat. Jamais un identifiant (conversation, message, compte), un
/// jeton, un texte ni un nom.
public struct ChatMetric: Sendable, Equatable {

    /// `conversation_open`, `send_to_ack`, `reconnect`, `sync_failure`.
    public let name: String

    /// Durée en millisecondes, quand la mesure en a une.
    public let durationMs: Int?

    /// Nature ou résultat uniquement (`trigger=reconnect`, `result=finished`).
    public let attributes: [String: String]

    public init(name: String, durationMs: Int? = nil, attributes: [String: String] = [:]) {
        self.name = name
        self.durationMs = durationMs
        self.attributes = attributes
    }
}

/// Où l'hôte veut recevoir les mesures (analytique, Sentry…). Appelé sur un fil
/// quelconque ; l'implémentation ne doit ni bloquer ni lancer.
public protocol ChatMetricsSink: Sendable {
    func record(_ metric: ChatMetric)
}

/// Défaut : les mesures sont jetées. Un hôte qui n'en veut pas ne change rien.
public struct NoChatMetrics: ChatMetricsSink {
    public init() {}
    public func record(_ metric: ChatMetric) {}
}

/// Noms émis par le Chat. Internes : l'hôte lit `ChatMetric.name` comme une chaîne.
enum ChatMetricName {
    static let conversationOpen = "conversation_open"
    static let sendToAck        = "send_to_ack"
    static let reconnect        = "reconnect"
    static let syncFailure      = "sync_failure"
}

extension ChatMetric {

    /// Millisecondes écoulées depuis `start`.
    static func elapsedMs(since start: ContinuousClock.Instant) -> Int {
        let parts = start.duration(to: .now).components
        return Int(parts.seconds * 1_000 + parts.attoseconds / 1_000_000_000_000_000)
    }
}
