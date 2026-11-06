//
//  ComplianceStanding.swift
//  CoreKit
//
//  KYC, AML et leur combinaison — Bloc 7, §31.7 et §57.
//
//  **BACKEND CONTRACT REQUIRED** — les statuts sont décidés et servis par le
//  backend. Le client ne les calcule jamais ; il les applique.
//

import Foundation

// MARK: - KYC

/// Où en est la vérification d'identité.
///
/// Distinct du **niveau** : un utilisateur `verified` au niveau 1 et un
/// utilisateur `expired` qui était au niveau 3 ne sont pas comparables, et les
/// confondre dans un seul entier — ce que fait `FinanceCapabilityContext.kycLevel`
/// aujourd'hui, un `String?` — rend l'expiration invisible.
public enum KYCState: String, Sendable, Hashable, Codable, CaseIterable {

    case notStarted    = "NOT_STARTED"
    case inProgress    = "IN_PROGRESS"

    /// Dossier déposé, en attente d'un examen humain.
    case pendingReview = "PENDING_REVIEW"

    case verified      = "VERIFIED"

    /// Vérifié un jour, périmé depuis — pièce d'identité expirée, revue
    /// périodique échue. **N'est pas un retour à `notStarted`** : les fonds
    /// déjà détenus restent consultables et les entrées restent possibles.
    case expired       = "EXPIRED"

    case rejected      = "REJECTED"

    /// Suspendu par la conformité, indépendamment de la qualité du dossier.
    case suspended     = "SUSPENDED"

    case unknown       = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = KYCState(rawValue: raw) ?? .unknown
    }

    /// L'identité est-elle établie à cet instant ?
    public var isEstablished: Bool { self == .verified }
}

/// Le niveau atteint, qui borne ce qui est permis.
public enum KYCTier: Int, Sendable, Hashable, Codable, CaseIterable, Comparable {

    /// Aucune vérification. Consultation et réception seulement.
    case tier0 = 0

    /// Identité déclarée et vérifiée automatiquement.
    case tier1 = 1

    /// Pièce d'identité contrôlée. Sorties courantes.
    case tier2 = 2

    /// Contrôle renforcé — justificatif de domicile, origine des fonds.
    case tier3 = 3

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// Un niveau inconnu vaut `tier0`, jamais le niveau demandé.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = KYCTier(rawValue: raw) ?? .tier0
    }
}

public struct KYCStatus: Sendable, Hashable, Codable {

    public let state: KYCState
    public let tier: KYCTier
    public let verifiedAt: Date?

    /// Échéance de la revue périodique. Passée, le statut doit être `expired`
    /// — mais on ne fait pas confiance au backend pour l'avoir recalculé : voir
    /// ``effectiveState(now:)``.
    public let expiresAt: Date?

    /// Ce qu'il manque pour monter, en clés de message.
    public let pendingRequirementKeys: [String]

    public init(state: KYCState, tier: KYCTier, verifiedAt: Date? = nil,
                expiresAt: Date? = nil, pendingRequirementKeys: [String] = []) {
        self.state = state
        self.tier = tier
        self.verifiedAt = verifiedAt
        self.expiresAt = expiresAt
        self.pendingRequirementKeys = pendingRequirementKeys
    }

    /// L'état réel, échéance comprise.
    ///
    /// Un statut `verified` dont la date d'expiration est passée est traité
    /// comme `expired` sans attendre que le backend le rafraîchisse. Un client
    /// laissé hors ligne plusieurs jours conserverait sinon un statut valide
    /// après son échéance.
    public func effectiveState(now: Date = Date()) -> KYCState {
        guard state == .verified, let expiresAt, expiresAt <= now else { return state }
        return .expired
    }

    /// Statut inconnu — le défaut avant toute résolution.
    public static let unresolved = KYCStatus(state: .unknown, tier: .tier0)
}

// MARK: - AML

/// Ce que le filtrage anti-blanchiment conclut.
///
/// Les causes sont distinctes en interne et **indiscernables à l'affichage** :
/// voir ``AMLStatus/abstractMessageKey``.
public enum AMLState: String, Sendable, Hashable, Codable, CaseIterable {

    case clear      = "CLEAR"

    /// Surveillance renforcée, sans restriction immédiate.
    case monitoring = "MONITORING"

    /// Dossier ouvert, en attente de décision humaine.
    case underReview = "UNDER_REVIEW"

    /// Bloqué. Aucune sortie de fonds.
    case blocked    = "BLOCKED"

    case unknown    = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = AMLState(rawValue: raw) ?? .unknown
    }
}

public struct AMLStatus: Sendable, Hashable, Codable {

    public let state: AMLState

    /// Correspondance sur une liste de sanctions.
    ///
    /// **Ne s'affiche jamais.** Présent pour que la décision soit correcte, pas
    /// pour être montré.
    public let hasSanctionsMatch: Bool

    /// Personne politiquement exposée. Impose un contrôle renforcé, pas un
    /// blocage : être PPE est légal.
    public let isPoliticallyExposed: Bool

    /// Référence du dossier, pour le support. Jamais affichée à l'utilisateur
    /// visé par le dossier.
    public let caseReference: String?

    public let screenedAt: Date?

    public init(state: AMLState, hasSanctionsMatch: Bool = false,
                isPoliticallyExposed: Bool = false,
                caseReference: String? = nil, screenedAt: Date? = nil) {
        self.state = state
        self.hasSanctionsMatch = hasSanctionsMatch
        self.isPoliticallyExposed = isPoliticallyExposed
        self.caseReference = caseReference
        self.screenedAt = screenedAt
    }

    /// La seule clé de message qu'un blocage AML peut produire.
    ///
    /// Une correspondance de sanctions, un dossier en cours et une décision
    /// manuelle rendent **exactement la même chaîne**. Ce n'est pas de la
    /// paresse d'interface : informer quelqu'un qu'il a déclenché un filtrage
    /// anti-blanchiment est, dans la plupart des juridictions, une infraction
    /// distincte — le *tipping off*. Et un message qui distingue les causes est
    /// un oracle : il suffit de faire varier les paramètres pour apprendre
    /// laquelle s'applique.
    ///
    /// La cause réelle vit dans le dossier, côté conformité, et n'atteint
    /// jamais l'appareil de la personne concernée.
    public static let abstractMessageKey = "finance.compliance.unavailable"

    /// Idem pour l'affichage : aucune granularité.
    public var displayMessageKey: String { Self.abstractMessageKey }

    /// Statut inconnu — le défaut avant tout filtrage.
    public static let unresolved = AMLStatus(state: .unknown)

    /// Bloque-t-il les sorties de fonds ?
    ///
    /// `unknown` bloque : un filtrage qui n'a pas répondu n'est pas un
    /// filtrage qui a répondu « rien à signaler ».
    public var restrictsOutbound: Bool {
        switch state {
        case .clear, .monitoring:            return false
        case .blocked, .unknown:             return true
        case .underReview:                   return true
        }
    }
}

// MARK: - Classes d'action

/// Ce que l'utilisateur cherche à faire.
///
/// Le grain est délibérément grossier : la matrice doit rester lisible et
/// testable. Les montants précis sont bornés ailleurs, par les plafonds.
public enum FinancialActionClass: String, Sendable, Hashable, Codable, CaseIterable {

    /// Consulter son solde, son historique, un reçu.
    case read           = "READ"

    /// Recevoir des fonds.
    case inbound        = "INBOUND"

    /// Envoyer, sous le plafond courant.
    case outboundLow    = "OUTBOUND_LOW"

    /// Envoyer, au-dessus du plafond courant.
    case outboundHigh   = "OUTBOUND_HIGH"

    /// Envoyer hors du pays.
    case crossBorder    = "CROSS_BORDER"

    /// Retirer en espèces.
    case cashOut        = "CASH_OUT"

    /// Modifier un bénéficiaire, un moyen de paiement, un mandat.
    case accountChange  = "ACCOUNT_CHANGE"

    case unknown        = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = FinancialActionClass(rawValue: raw) ?? .unknown
    }

    /// Une action inconnue est traitée comme mutante.
    public var isMutating: Bool { self != .read && self != .inbound }

    /// Le niveau KYC minimal, hors AML.
    public var minimumTier: KYCTier {
        switch self {
        case .read, .inbound:                   return .tier0
        case .outboundLow, .accountChange:      return .tier1
        case .outboundHigh, .cashOut:           return .tier2
        case .crossBorder, .unknown:            return .tier3
        }
    }
}

// MARK: - La matrice (§31.7)

/// Ce que la conformité décide pour une action.
public enum ComplianceDecision: Sendable, Equatable {

    case allowed

    /// Autorisé, mais l'assurance d'identité doit être relevée d'abord.
    case allowedWithStepUp(StepUpLevel)

    /// Il faut monter de niveau KYC. Actionnable : l'utilisateur peut y
    /// remédier lui-même, et le message peut donc être précis.
    case requiresUpgrade(to: KYCTier, requirementKeys: [String])

    /// Un examen est en cours. Ni refus ni acceptation.
    case pendingReview

    /// Refusé. La clé est volontairement générique — voir
    /// ``AMLStatus/abstractMessageKey``.
    case blocked(reasonKey: String)

    public var permitsExecution: Bool {
        switch self {
        case .allowed, .allowedWithStepUp:                    return true
        case .requiresUpgrade, .pendingReview, .blocked:      return false
        }
    }

    /// La clé de message à afficher. Jamais une phrase composée ici.
    public var messageKey: String {
        switch self {
        case .allowed, .allowedWithStepUp:  return ""
        case .requiresUpgrade(let tier, _): return "finance.compliance.upgrade.tier\(tier.rawValue)"
        case .pendingReview:                return "finance.compliance.pending_review"
        case .blocked(let key):             return key
        }
    }
}

/// La position de conformité d'un utilisateur, à un instant donné.
///
/// Le §31.7 pose le critère : « un blocage AML peut être contourné depuis le
/// Chat ». Il ne peut l'être que si la décision est prise à un seul endroit et
/// que le Chat ne dispose d'aucun chemin qui la court-circuite. ``decision(for:now:)``
/// est ce seul endroit : une fonction pure, sans état ni réseau, donc testable
/// exhaustivement.
public struct ComplianceStanding: Sendable, Hashable, Codable {

    public let kyc: KYCStatus
    public let aml: AMLStatus

    public init(kyc: KYCStatus, aml: AMLStatus) {
        self.kyc = kyc
        self.aml = aml
    }

    /// Position non résolue. Tout ce qui mute est refusé.
    public static let unresolved = ComplianceStanding(kyc: .unresolved, aml: .unresolved)

    /// La décision, pour une classe d'action.
    ///
    /// **L'AML l'emporte sur le KYC**, et l'ordre n'est pas arbitraire : une
    /// correspondance de sanctions ne se corrige pas en téléversant une pièce
    /// d'identité. Inverser l'ordre afficherait « complétez votre vérification »
    /// à quelqu'un dont le dossier est bloqué — un conseil faux, et un aveu.
    public func decision(for action: FinancialActionClass, now: Date = Date()) -> ComplianceDecision {

        // La consultation de ses propres données reste ouverte, y compris sous
        // blocage. Couper l'accès au solde ne sert aucun objectif de conformité
        // et prive quelqu'un de la vue sur ses propres fonds.
        if action == .read { return .allowed }

        // 1. AML.
        if aml.restrictsOutbound && action.isMutating {
            switch aml.state {
            case .underReview:
                return .pendingReview
            case .blocked, .unknown:
                return .blocked(reasonKey: AMLStatus.abstractMessageKey)
            case .clear, .monitoring:
                break
            }
        }

        // Recevoir reste possible sous examen : bloquer les entrées
        // immobiliserait des fonds sans les protéger.
        if action == .inbound {
            return aml.state == .blocked
                ? .blocked(reasonKey: AMLStatus.abstractMessageKey)
                : .allowed
        }

        // 2. KYC.
        switch kyc.effectiveState(now: now) {
        case .verified:
            break
        case .pendingReview, .inProgress:
            return .pendingReview
        case .expired:
            return .requiresUpgrade(to: kyc.tier, requirementKeys: kyc.pendingRequirementKeys)
        case .notStarted:
            return .requiresUpgrade(to: action.minimumTier, requirementKeys: kyc.pendingRequirementKeys)
        case .rejected, .suspended, .unknown:
            return .blocked(reasonKey: AMLStatus.abstractMessageKey)
        }

        // 3. Niveau atteint.
        guard kyc.tier >= action.minimumTier else {
            return .requiresUpgrade(to: action.minimumTier, requirementKeys: kyc.pendingRequirementKeys)
        }

        // 4. Contrôle renforcé pour les personnes politiquement exposées : une
        // assurance plus forte, pas un refus.
        if aml.isPoliticallyExposed || aml.state == .monitoring {
            return .allowedWithStepUp(.biometricAndOTP)
        }

        return .allowed
    }
}

// MARK: - Fourniture

/// Sert la position de conformité.
public protocol ComplianceStandingProviding: Sendable {

    /// La position courante. Rafraîchie par le backend, jamais calculée ici.
    func standing() async -> Result<ComplianceStanding, FinanceError>
}

// MARK: - Défaut fermé

/// Ne connaît aucune position, et refuse donc tout ce qui mute.
///
/// La lecture reste ouverte — c'est ce que rend ``ComplianceStanding/unresolved``
/// à travers ``ComplianceStanding/decision(for:now:)``.
public struct ClosedComplianceStandingProvider: ComplianceStandingProviding {

    public init() {}

    public func standing() async -> Result<ComplianceStanding, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
