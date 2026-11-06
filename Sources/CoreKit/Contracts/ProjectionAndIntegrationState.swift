//
//  ProjectionAndIntegrationState.swift
//  CoreKit
//
//  Fraîcheur des projections Toussaint et états techniques EIG — Waangu 360 §5, §10.
//

import Foundation

/// Fraîcheur déclarée par Toussaint pour une projection de lecture.
///
/// Le client l'affiche telle quelle. Il ne corrige jamais une projection
/// incohérente et ne déduit pas `current` d'un horodatage local.
public enum ProjectionFreshness: String, Codable, Sendable, CaseIterable {
    case current   = "CURRENT"
    case lagging   = "LAGGING"
    case stale     = "STALE"
    case rebuilding = "REBUILDING"
    case failed    = "FAILED"
    /// Valeur non reconnue : dit la vérité plutôt que de supposer `current`.
    case unknown   = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProjectionFreshness(rawValue: raw) ?? .unknown
    }

    /// Seul `current` autorise à présenter la donnée comme à jour.
    public var mayBePresentedAsCurrent: Bool { self == .current }
}

/// État technique d'une opération EIG.
///
/// Il décrit le transport, jamais le résultat métier ou financier :
/// `acknowledged` ne veut pas dire payé, émis ou confirmé.
public enum EIGTechnicalState: String, Codable, Sendable, CaseIterable {
    case requested        = "EIG_REQUESTED"
    case dispatched       = "EIG_DISPATCHED"
    case acknowledged     = "EIG_ACKNOWLEDGED"
    case pending          = "EIG_PENDING"
    case timeout          = "EIG_TIMEOUT"
    case technicalFailed  = "EIG_TECHNICAL_FAILED"
    case callbackReceived = "EIG_CALLBACK_RECEIVED"
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EIGTechnicalState(rawValue: raw) ?? .unknown
    }

    /// Un état EIG ne porte jamais d'issue financière : toujours `nil`.
    /// L'issue vient de l'autorité du domaine, via un événement Samuel.
    public var impliedPaymentStatus: PaymentStatus? { nil }

    /// Effet externe inconnu : à traiter comme `inDoubt`/`unknown`, jamais
    /// comme un échec définitif ni un succès.
    public var externalEffectIsUnknown: Bool {
        switch self {
        case .timeout, .unknown: return true
        default: return false
        }
    }
}
