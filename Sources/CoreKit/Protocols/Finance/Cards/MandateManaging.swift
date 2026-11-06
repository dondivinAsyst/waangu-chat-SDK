//
//  MandateManaging.swift
//  CoreKit
//
//  Mandats de prélèvement — Bloc 4, chapitre 30 (GAP-02).
//
//  **BACKEND CONTRACT REQUIRED** — `GET/POST /v1/biller/mandates`,
//  `/suspend`, `/resume`, `/revoke`.
//

import Foundation

/// Gère les autorisations permanentes de débit.
///
/// **Un mandat est le seul objet du système qui autorise un débit futur sans
/// geste de l'utilisateur.** Tout le reste en découle : la preuve de
/// consentement est versionnée et conservée, la révocation est toujours
/// atteignable, et une exécution ne peut jamais réactiver un mandat suspendu.
public protocol MandateManaging: Sendable {

    func mandates() async -> Result<[Mandate], FinanceError>

    /// Crée un mandat. Le consentement est **obligatoire et daté**.
    func create(_ draft: MandateDraft,
                idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError>

    func suspend(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError>
    func resume(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError>

    /// Révoque définitivement.
    ///
    /// Distinct de `suspend` : une suspension se reprend, une révocation non.
    /// Les confondre laisserait croire qu'un mandat révoqué peut revivre.
    func revoke(_ id: String, idempotency: IdempotencyContext) async -> Result<Mandate, FinanceError>
}

// MARK: - Mandat

public struct Mandate: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let creditorID: String
    public let creditorDisplayName: String

    /// Plafond par exécution. `nil` ⇒ pas de plafond côté mandat — le backend
    /// applique alors ses propres limites, que le client n'a pas à connaître.
    public let maxAmount: Money?

    public let frequency: MandateFrequency
    public let startDate: Date
    public let expiryDate: Date?

    /// Version du texte de consentement accepté.
    ///
    /// Sans elle, on sait que l'utilisateur a consenti mais pas **à quoi** : un
    /// texte modifié depuis rendrait la preuve inexploitable en contestation.
    public let consentVersion: String

    /// Référence de la preuve conservée par le backend.
    ///
    /// **La seule défense en cas de contestation.** Le client ne la produit pas
    /// et ne la stocke pas : il l'affiche pour que l'utilisateur sache qu'elle
    /// existe.
    public let consentEvidenceID: String

    public let status: MandateStatus
    public let lastExecutionAt: Date?
    public let nextExecutionAt: Date?

    public init(
        id: String, creditorID: String, creditorDisplayName: String,
        maxAmount: Money? = nil, frequency: MandateFrequency,
        startDate: Date, expiryDate: Date? = nil,
        consentVersion: String, consentEvidenceID: String,
        status: MandateStatus,
        lastExecutionAt: Date? = nil, nextExecutionAt: Date? = nil
    ) {
        self.id = id
        self.creditorID = creditorID
        self.creditorDisplayName = creditorDisplayName
        self.maxAmount = maxAmount
        self.frequency = frequency
        self.startDate = startDate
        self.expiryDate = expiryDate
        self.consentVersion = consentVersion
        self.consentEvidenceID = consentEvidenceID
        self.status = status
        self.lastExecutionAt = lastExecutionAt
        self.nextExecutionAt = nextExecutionAt
    }
}

// MARK: - Brouillon

public struct MandateDraft: Sendable, Hashable, Codable {
    public let creditorID: String
    public let maxAmount: Money?
    public let frequency: MandateFrequency
    public let startDate: Date
    public let expiryDate: Date?

    /// Version du texte que l'utilisateur a réellement lu.
    public let consentVersion: String

    /// Consentement explicite. Sans valeur par défaut : un mandat présumé
    /// consenti est une autorisation de débit que personne n'a donnée.
    public let hasConsented: Bool

    public init(creditorID: String, maxAmount: Money?, frequency: MandateFrequency,
                startDate: Date, expiryDate: Date?, consentVersion: String,
                hasConsented: Bool) {
        self.creditorID = creditorID
        self.maxAmount = maxAmount
        self.frequency = frequency
        self.startDate = startDate
        self.expiryDate = expiryDate
        self.consentVersion = consentVersion
        self.hasConsented = hasConsented
    }

    public var isSubmittable: Bool { hasConsented && !consentVersion.isEmpty }
}

// MARK: - Fréquence

public enum MandateFrequency: String, Codable, Sendable, CaseIterable {
    case weekly, biweekly, monthly, quarterly, yearly, onDemand

    /// Une fréquence inconnue est refusée au décodage.
    ///
    /// Pas de repli : traiter un mandat trimestriel comme mensuel triplerait le
    /// nombre de débits. Il n'existe pas de valeur sûre par défaut ici.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = MandateFrequency(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Fréquence de mandat inconnue : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - États

public enum MandateStatus: String, Codable, Sendable, CaseIterable {
    case pendingConsent  = "PENDING_CONSENT"
    case pendingApproval = "PENDING_APPROVAL"
    case active          = "ACTIVE"
    case suspended       = "SUSPENDED"
    case expired         = "EXPIRED"
    case revoked         = "REVOKED"
    case failed          = "FAILED"

    /// Un état inconnu devient `suspended` : aucune exécution, et réversible.
    ///
    /// Le repli le plus sûr n'est ni `active` — qui autoriserait des débits sur
    /// un état qu'on ne comprend pas — ni `revoked`, qui détruirait un mandat
    /// peut-être valide.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = MandateStatus(rawValue: raw) ?? .suspended
    }

    /// Un mandat révoqué ou expiré ne revit jamais.
    public var isTerminal: Bool { self == .revoked || self == .expired }

    /// `true` si une exécution peut être planifiée.
    public var allowsExecution: Bool { self == .active }
}

// MARK: - Machine à états

public enum MandateStateMachine {

    /// Transitions autorisées. Toute autre est refusée.
    private static let allowed: [MandateStatus: Set<MandateStatus>] = [
        .pendingConsent:  [.pendingApproval, .failed, .revoked],
        .pendingApproval: [.active, .failed, .revoked],
        .active:          [.suspended, .expired, .revoked, .failed],
        .suspended:       [.active, .expired, .revoked],
        .failed:          [.pendingApproval, .revoked],
        .expired:         [],
        .revoked:         []
    ]

    public static func isAllowed(from current: MandateStatus, to next: MandateStatus) -> Bool {
        if current == next { return true }
        return allowed[current]?.contains(next) ?? false
    }
}

// MARK: - Confort

public extension Mandate {

    func isExpired(asOf now: Date = Date()) -> Bool {
        guard let expiryDate else { return false }
        return now >= expiryDate
    }

    /// `true` si un débit peut être prélevé maintenant.
    ///
    /// Trois conditions ensemble : actif, non expiré, et démarré. Un mandat
    /// dont la date de début est future ne prélève pas, même actif.
    func allowsDebit(asOf now: Date = Date()) -> Bool {
        status.allowsExecution && !isExpired(asOf: now) && now >= startDate
    }

    /// `true` si ce montant respecte le plafond du mandat.
    ///
    /// Un plafond absent ne vaut pas plafond infini côté client : il signifie
    /// que la borne est ailleurs, et le client ne la valide pas.
    func permits(amount: Money) -> Bool {
        guard let maxAmount else { return true }
        guard maxAmount.currency == amount.currency else { return false }
        return amount.minorUnits <= maxAmount.minorUnits
    }

    /// La révocation reste atteignable tant que le mandat n'est pas terminal.
    var isRevocable: Bool { !status.isTerminal }
}
