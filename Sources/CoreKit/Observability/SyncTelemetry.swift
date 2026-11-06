//
//  SyncTelemetry.swift
//  CoreKit
//
//  Événements techniques de synchronisation — Bloc 8, §26 et §27.
//
//  Complète `RealtimeMetricsDelegate`, qui couvre déjà le transport (connexion,
//  latence, perte, déduplication). Ce qui manquait : le cycle de vie de la
//  synchronisation, les curseurs, l'outbox et la révocation.
//

import Foundation
import CryptoKit

/// Un événement technique de synchronisation.
///
/// **Aucun cas ne porte de texte libre.** C'est délibéré et c'est toute la
/// garantie du §26 : on ne peut pas journaliser un message privé, un PAN, un
/// OTP, un jeton ou un document KYC, parce qu'aucun cas n'accepte de chaîne
/// arbitraire. Les seules chaînes admises sont des identifiants de flux, des
/// empreintes et des clés stables.
///
/// Une politique de rédaction qui repose sur la discipline finit par céder au
/// premier `"error: \(error)"` ajouté un vendredi soir. Un type qui n'a pas de
/// champ libre ne cède pas.
public enum SyncTelemetryEvent: Sendable, Equatable {

    // MARK: Cycle de synchronisation

    case syncStarted(stream: String)
    case syncCompleted(stream: String, applied: Int, duration: TimeInterval)
    case syncFailed(stream: String, code: String)

    // MARK: Curseurs (§15, §16)

    /// Un trou de séquence a été détecté.
    ///
    /// Le plus important de la liste : c'est le seul signal qui distingue « le
    /// serveur n'a rien envoyé » de « nous avons perdu des événements ».
    case cursorGap(stream: String, expected: Int64, received: Int64)

    case cursorInvalid(stream: String)

    /// Le curseur a été committé après ses données, comme il se doit.
    case cursorCommitted(stream: String, sequence: Int64)

    // MARK: Outbox (§8, §9)

    case outboxQueued(type: String, queueDepth: Int)
    case outboxRetry(type: String, attempt: Int, delay: TimeInterval)
    case outboxDeadLetter(reasonKey: String, attempts: Int)

    // MARK: Temps réel (§13)

    case mqttConnected(transport: String)
    case mqttDisconnected(codeKey: String)
    case mqttGapDetected(topicHash: String, expected: Int64, received: Int64)

    // MARK: Sécurité et sessions (§18, §43)

    case deviceRevoked(deviceIDHash: String)
    case sessionExpired
    case cachePurged(scope: String, itemCount: Int)

    // MARK: Réconciliation

    case reconciliationStarted(objectIDHash: String)
    case reconciliationCompleted(objectIDHash: String, outcomeKey: String)

    /// Le nom stable de l'événement, tel que le §26 l'énumère.
    ///
    /// Stable au sens fort : c'est la clé sur laquelle les tableaux de bord et
    /// les alertes sont construits. La renommer casse l'exploitation sans
    /// casser la compilation, ce qui en fait un changement à traiter comme une
    /// rupture de contrat.
    public var name: String {
        switch self {
        case .syncStarted:              return "sync_started"
        case .syncCompleted:            return "sync_completed"
        case .syncFailed:               return "sync_failed"
        case .cursorGap:                return "cursor_gap"
        case .cursorInvalid:            return "cursor_invalid"
        case .cursorCommitted:          return "cursor_committed"
        case .outboxQueued:             return "outbox_queued"
        case .outboxRetry:              return "outbox_retry"
        case .outboxDeadLetter:         return "outbox_dead_letter"
        case .mqttConnected:            return "mqtt_connected"
        case .mqttDisconnected:         return "mqtt_disconnected"
        case .mqttGapDetected:          return "mqtt_gap_detected"
        case .deviceRevoked:            return "device_revoked"
        case .sessionExpired:           return "session_expired"
        case .cachePurged:              return "cache_purged"
        case .reconciliationStarted:    return "reconciliation_started"
        case .reconciliationCompleted:  return "reconciliation_completed"
        }
    }

    /// Ce qui doit réveiller quelqu'un.
    ///
    /// Un trou de curseur et une révocation d'appareil sont des alertes ; une
    /// synchronisation qui démarre ne l'est pas. Sans cette distinction, tout
    /// part au même niveau et l'astreinte cesse de lire.
    public var severity: SyncTelemetrySeverity {
        switch self {
        case .cursorGap, .cursorInvalid, .mqttGapDetected, .outboxDeadLetter:
            return .alert
        case .syncFailed, .deviceRevoked, .sessionExpired:
            return .warning
        case .syncStarted, .syncCompleted, .cursorCommitted, .outboxQueued,
             .outboxRetry, .mqttConnected, .mqttDisconnected, .cachePurged,
             .reconciliationStarted, .reconciliationCompleted:
            return .info
        }
    }

    /// Champs structurés. Valeurs numériques ou clés — jamais de contenu.
    public var fields: [String: String] {
        switch self {
        case .syncStarted(let stream):
            return ["stream": stream]
        case .syncCompleted(let stream, let applied, let duration):
            return ["stream": stream, "applied": "\(applied)",
                    "duration_ms": "\(Int(duration * 1000))"]
        case .syncFailed(let stream, let code):
            return ["stream": stream, "code": code]
        case .cursorGap(let stream, let expected, let received):
            return ["stream": stream, "expected": "\(expected)",
                    "received": "\(received)", "missing": "\(received - expected)"]
        case .cursorInvalid(let stream):
            return ["stream": stream]
        case .cursorCommitted(let stream, let sequence):
            return ["stream": stream, "sequence": "\(sequence)"]
        case .outboxQueued(let type, let depth):
            return ["type": type, "queue_depth": "\(depth)"]
        case .outboxRetry(let type, let attempt, let delay):
            return ["type": type, "attempt": "\(attempt)",
                    "delay_ms": "\(Int(delay * 1000))"]
        case .outboxDeadLetter(let reasonKey, let attempts):
            return ["reason": reasonKey, "attempts": "\(attempts)"]
        case .mqttConnected(let transport):
            return ["transport": transport]
        case .mqttDisconnected(let codeKey):
            return ["code": codeKey]
        case .mqttGapDetected(let topicHash, let expected, let received):
            return ["topic_hash": topicHash, "expected": "\(expected)",
                    "received": "\(received)"]
        case .deviceRevoked(let hash):
            return ["device_hash": hash]
        case .sessionExpired:
            return [:]
        case .cachePurged(let scope, let count):
            return ["scope": scope, "items": "\(count)"]
        case .reconciliationStarted(let hash):
            return ["object_hash": hash]
        case .reconciliationCompleted(let hash, let outcomeKey):
            return ["object_hash": hash, "outcome": outcomeKey]
        }
    }
}

public enum SyncTelemetrySeverity: String, Sendable, Hashable, CaseIterable {
    case info    = "INFO"
    case warning = "WARNING"
    case alert   = "ALERT"
}

// MARK: - Corrélation (§27)

/// Ce qui permet de suivre une opération de l'UI jusqu'au bus d'événements.
///
/// Les six identifiants du §27, aucun secret. `idempotencyKey` et `deviceID`
/// sont **hachés** : ils identifient sans être rejouables si un log fuit.
public struct SyncTraceContext: Sendable, Hashable {

    public let correlationID: CorrelationId
    public let requestID: String?
    public let clientRequestID: String?
    public let idempotencyKeyHash: String?
    public let deviceIDHash: String?
    public let sessionID: String?

    public init(correlationID: CorrelationId, requestID: String? = nil,
                clientRequestID: String? = nil, idempotencyKey: String? = nil,
                deviceID: String? = nil, sessionID: String? = nil) {
        self.correlationID = correlationID
        self.requestID = requestID
        self.clientRequestID = clientRequestID
        self.idempotencyKeyHash = idempotencyKey.map(SyncTraceContext.hash)
        self.deviceIDHash = deviceID.map(SyncTraceContext.hash)
        self.sessionID = sessionID
    }

    /// Empreinte tronquée, non salée.
    ///
    /// Même raisonnement que ``FinanceLogContext`` : le hachage doit être
    /// stable d'un appareil à l'autre pour que deux logs se recoupent. À ne pas
    /// employer sur une valeur à faible entropie — un identifiant opaque
    /// backend convient, un numéro de téléphone non.
    static func hash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }
            .joined().prefix(16).description
    }

    public var fields: [String: String] {
        var out = ["correlation_id": correlationID.value]
        if let requestID { out["request_id"] = requestID }
        if let clientRequestID { out["client_request_id"] = clientRequestID }
        if let idempotencyKeyHash { out["idempotency_hash"] = idempotencyKeyHash }
        if let deviceIDHash { out["device_hash"] = deviceIDHash }
        if let sessionID { out["session_id"] = sessionID }
        return out
    }
}

// MARK: - Émission

/// Reçoit les événements de synchronisation.
public protocol SyncTelemetryEmitting: Sendable {
    func emit(_ event: SyncTelemetryEvent, trace: SyncTraceContext?) async
}

public extension SyncTelemetryEmitting {
    func emit(_ event: SyncTelemetryEvent) async {
        await emit(event, trace: nil)
    }
}

/// N'émet rien.
///
/// Défaut explicite plutôt qu'un `nil` optionnel partout : un appelant qui doit
/// écrire `await telemetry?.emit(...)` finit par en oublier un.
public struct NoOpSyncTelemetry: SyncTelemetryEmitting {
    public init() {}
    public func emit(_ event: SyncTelemetryEvent, trace: SyncTraceContext?) async {}
}

// MARK: - Correspondance depuis les erreurs

public extension SyncError {

    /// Code stable pour la télémétrie.
    ///
    /// **N'emprunte jamais le texte associé.** `malformedPayload(reason:)` et
    /// `permanentFailure(code:)` portent des chaînes rédigées par le
    /// développeur ; les émettre telles quelles rouvrirait le champ libre que
    /// ``SyncTelemetryEvent`` ferme.
    var telemetryCode: String {
        switch self {
        case .offline:             return "offline"
        case .timeout:             return "timeout"
        case .unauthorized:        return "unauthorized"
        case .forbidden:           return "forbidden"
        case .conflict:            return "conflict"
        case .stale:               return "stale"
        case .expired:             return "expired"
        case .revoked:             return "revoked"
        case .invalidCursor:       return "invalid_cursor"
        case .malformedPayload:    return "malformed_payload"
        case .serverUnavailable:   return "server_unavailable"
        case .unknownOutcome:      return "unknown_outcome"
        case .permanentFailure:    return "permanent_failure"
        case .foreignScope:        return "foreign_scope"
        }
    }
}
