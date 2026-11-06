//
//  SupportGovernance.swift
//  CoreKit
//
//  SLA, accès opérateur et notes internes — Bloc 7, §60 et §31.6.
//
//  **BACKEND CONTRACT REQUIRED** — les habilitations opérateur sont décidées et
//  signées côté backend. Ce fichier décrit ce que le client vérifie et ce qu'il
//  refuse d'afficher, jamais ce qu'il accorde.
//

import Foundation

// MARK: - SLA (§60)

public enum SupportPriority: String, Sendable, Hashable, Codable, CaseIterable {

    /// Fonds bloqués, compte inaccessible, opération en `timeoutUnknown`.
    case critical = "CRITICAL"

    case high     = "HIGH"
    case normal   = "NORMAL"
    case low      = "LOW"
    case unknown  = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportPriority(rawValue: raw) ?? .unknown
    }

    /// Une priorité inconnue est traitée comme `normal`, jamais comme `low` :
    /// une priorité que ce client ne sait pas lire ne doit pas se retrouver en
    /// bas de pile.
    public var effective: SupportPriority { self == .unknown ? .normal : self }
}

/// L'engagement de délai, et sa mesure.
///
/// Le §60 demande un SLA ; le champ existant `expectedResponseSeconds` est un
/// délai **annoncé**, pas un engagement mesurable. La différence porte tout :
/// un délai annoncé ne peut pas être dépassé, il peut seulement être faux.
public struct SupportSLA: Sendable, Hashable, Codable {

    public let priority: SupportPriority

    /// Délai de première réponse.
    public let firstResponseSeconds: TimeInterval

    /// Délai de résolution.
    public let resolutionSeconds: TimeInterval

    /// Le temps passé en attente du client ou d'un tiers, déjà décompté par le
    /// backend. Le client ne le recalcule pas — il ne connaît pas l'historique
    /// complet des transitions.
    public let pausedSeconds: TimeInterval

    public init(priority: SupportPriority, firstResponseSeconds: TimeInterval,
                resolutionSeconds: TimeInterval, pausedSeconds: TimeInterval = 0) {
        self.priority = priority
        self.firstResponseSeconds = firstResponseSeconds
        self.resolutionSeconds = resolutionSeconds
        self.pausedSeconds = pausedSeconds
    }

    /// Temps réellement consommé depuis l'ouverture, hors périodes suspendues.
    public func elapsedSeconds(since openedAt: Date, now: Date = Date()) -> TimeInterval {
        max(0, now.timeIntervalSince(openedAt) - pausedSeconds)
    }

    /// Le délai de première réponse est-il dépassé ?
    public func hasBreachedFirstResponse(openedAt: Date, firstRespondedAt: Date?,
                                         now: Date = Date()) -> Bool {
        let reference = firstRespondedAt ?? now
        return max(0, reference.timeIntervalSince(openedAt) - pausedSeconds) > firstResponseSeconds
    }

    public func hasBreachedResolution(openedAt: Date, resolvedAt: Date?,
                                      now: Date = Date()) -> Bool {
        let reference = resolvedAt ?? now
        return max(0, reference.timeIntervalSince(openedAt) - pausedSeconds) > resolutionSeconds
    }

    /// Ce qu'on affiche au client : une échéance, pas un compte à rebours.
    ///
    /// Un compte à rebours qui atteint zéro sans réponse transforme un retard
    /// en promesse rompue affichée en direct.
    public func firstResponseDeadline(openedAt: Date) -> Date {
        openedAt.addingTimeInterval(firstResponseSeconds + pausedSeconds)
    }
}

// MARK: - Accès opérateur (ABAC, §31.6)

/// Ce qu'un opérateur a le droit de faire.
///
/// Le §31.6 pose : « un opérateur peut écrire directement dans le ledger ». Le
/// critère n'était pas vérifiable faute de modèle opérateur — pas parce que
/// l'écriture était permise, mais parce que rien ne permettait d'affirmer
/// qu'elle ne l'était pas. C'est ce que ces types rendent énonçable.
public enum SupportOperatorRole: String, Sendable, Hashable, Codable, CaseIterable {

    /// Lecture seule du dossier et du contexte masqué.
    case agent          = "AGENT"

    /// Peut escalader et éditer les notes internes.
    case seniorAgent    = "SENIOR_AGENT"

    /// Peut demander une action financière — jamais l'exécuter seul.
    case supervisor     = "SUPERVISOR"

    /// Peut approuver la demande d'un autre. Jamais la sienne.
    case complianceOfficer = "COMPLIANCE_OFFICER"

    case unknown        = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportOperatorRole(rawValue: raw) ?? .unknown
    }
}

/// Ce qu'un opérateur peut voir.
public enum SupportDataScope: String, Sendable, Hashable, Codable, CaseIterable {
    case caseMetadata     = "CASE_METADATA"
    case maskedContext    = "MASKED_CONTEXT"
    case statusHistory    = "STATUS_HISTORY"
    case internalNotes    = "INTERNAL_NOTES"
    case complianceCase   = "COMPLIANCE_CASE"
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportDataScope(rawValue: raw) ?? .unknown
    }
}

/// L'habilitation d'un opérateur, sur un dossier, pour une durée.
///
/// Attributs plutôt que rôles seuls : le rôle dit ce que quelqu'un est, pas ce
/// qu'il consulte à cet instant. Un agent habilité en général qui ouvre le
/// dossier d'un proche n'est pas couvert par son rôle — il l'est ou non par
/// `caseID`, `purpose` et `expiresAt`.
public struct SupportAccessContext: Sendable, Hashable, Codable {

    public let operatorID: String
    public let role: SupportOperatorRole
    public let tenantID: String

    /// Le dossier auquel cette habilitation se limite. Une habilitation sans
    /// dossier n'ouvre rien : voir ``permits(_:on:now:)``.
    public let caseID: String?

    public let scopes: Set<SupportDataScope>

    /// Motif déclaré de la consultation, journalisé. Ce n'est pas un contrôle
    /// technique — c'est ce qui rend un accès abusif imputable après coup.
    public let purposeKey: String

    public let grantedAt: Date
    public let expiresAt: Date

    public init(operatorID: String, role: SupportOperatorRole, tenantID: String,
                caseID: String?, scopes: Set<SupportDataScope>, purposeKey: String,
                grantedAt: Date, expiresAt: Date) {
        self.operatorID = operatorID
        self.role = role
        self.tenantID = tenantID
        self.caseID = caseID
        self.scopes = scopes
        self.purposeKey = purposeKey
        self.grantedAt = grantedAt
        self.expiresAt = expiresAt
    }

    public func isValid(now: Date = Date()) -> Bool {
        now >= grantedAt && now < expiresAt && role != .unknown
    }

    /// L'accès est-il permis, pour cette portée, sur ce dossier ?
    ///
    /// Les trois conditions se vérifient ensemble : une habilitation valide
    /// pour un autre dossier n'est pas une habilitation partielle.
    public func permits(_ scope: SupportDataScope, on caseID: String,
                        now: Date = Date()) -> Bool {
        guard isValid(now: now) else { return false }
        guard let scopedCase = self.caseID, scopedCase == caseID else { return false }
        return scopes.contains(scope)
    }
}

// MARK: - Notes internes

/// Une note attachée à un dossier.
///
/// La visibilité est un type, pas un booléen sur une chaîne. Une note interne
/// rendue au client est la fuite la plus banale d'un outil de support : elle
/// ne franchit aucune frontière technique, juste un mauvais champ dans un
/// gabarit.
public struct SupportNote: Sendable, Hashable, Codable, Identifiable {

    public enum Visibility: String, Sendable, Hashable, Codable, CaseIterable {

        /// Visible par le client.
        case customerVisible = "CUSTOMER_VISIBLE"

        /// Interne. **Ne sort jamais vers le client**, quel que soit le canal.
        case internalOnly    = "INTERNAL"

        /// Réservé à la conformité — invisible même aux agents.
        case complianceOnly  = "COMPLIANCE_ONLY"

        case unknown         = "UNKNOWN"

        /// Une visibilité inconnue est traitée comme la plus restrictive.
        ///
        /// C'est le seul défaut acceptable : dégrader vers `customerVisible`
        /// publierait une note dont on ne sait rien.
        public init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Visibility(rawValue: raw) ?? .unknown
        }

        public var isCustomerFacing: Bool { self == .customerVisible }

        /// La portée nécessaire pour la lire.
        public var requiredScope: SupportDataScope {
            switch self {
            case .customerVisible:              return .caseMetadata
            case .internalOnly:                 return .internalNotes
            case .complianceOnly, .unknown:     return .complianceCase
            }
        }
    }

    public let id: String
    public let caseID: String
    public let authorID: String
    public let visibility: Visibility
    public let body: String
    public let createdAt: Date

    public init(id: String, caseID: String, authorID: String,
                visibility: Visibility, body: String, createdAt: Date) {
        self.id = id
        self.caseID = caseID
        self.authorID = authorID
        self.visibility = visibility
        self.body = body
        self.createdAt = createdAt
    }

    /// Cet opérateur peut-il la lire ?
    public func isReadable(by access: SupportAccessContext, now: Date = Date()) -> Bool {
        access.permits(visibility.requiredScope, on: caseID, now: now)
    }
}

public extension Array where Element == SupportNote {

    /// Les notes affichables au client. À utiliser partout où un gabarit
    /// compose un message sortant.
    var customerVisible: [SupportNote] {
        filter { $0.visibility.isCustomerFacing }
    }
}

// MARK: - Action financière opérateur (§31.6)

/// Ce qu'un opérateur peut demander sur les fonds d'un client.
///
/// Aucune de ces valeurs n'est une écriture. Ce sont des **demandes** — le nom
/// est le contrat : un opérateur n'écrit pas dans le ledger, il demande une
/// opération qui suit ensuite le même chemin que celle d'un client, permis
/// compris.
public enum SupportFinancialAction: String, Sendable, Hashable, Codable, CaseIterable {
    case refundRequest      = "REFUND_REQUEST"
    case reversalRequest    = "REVERSAL_REQUEST"
    case feeWaiverRequest   = "FEE_WAIVER_REQUEST"
    case holdRelease        = "HOLD_RELEASE"
    case unknown            = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportFinancialAction(rawValue: raw) ?? .unknown
    }

    /// Le rôle minimal pour la demander.
    public var minimumRole: SupportOperatorRole {
        switch self {
        case .feeWaiverRequest:                     return .seniorAgent
        case .refundRequest, .holdRelease:          return .supervisor
        case .reversalRequest, .unknown:            return .complianceOfficer
        }
    }
}

/// Une demande d'action financière par un opérateur, et son approbation.
///
/// Le double contrôle est structurel : ``approve(by:now:)`` refuse le
/// demandeur. Un opérateur ne peut pas approuver sa propre demande, et ce n'est
/// pas une règle d'interface qu'un écran pourrait oublier — c'est un refus du
/// type lui-même.
public struct SupportFinancialActionRequest: Sendable, Hashable, Codable, Identifiable {

    public let id: String
    public let caseID: String
    public let action: SupportFinancialAction
    public let amount: Money?
    public let requestedBy: String
    public let requestedByRole: SupportOperatorRole
    public let justificationKey: String
    public let requestedAt: Date

    /// Qui a approuvé. `nil` tant que personne ne l'a fait.
    public let approvedBy: String?
    public let approvedAt: Date?

    public init(id: String, caseID: String, action: SupportFinancialAction,
                amount: Money?, requestedBy: String, requestedByRole: SupportOperatorRole,
                justificationKey: String, requestedAt: Date,
                approvedBy: String? = nil, approvedAt: Date? = nil) {
        self.id = id
        self.caseID = caseID
        self.action = action
        self.amount = amount
        self.requestedBy = requestedBy
        self.requestedByRole = requestedByRole
        self.justificationKey = justificationKey
        self.requestedAt = requestedAt
        self.approvedBy = approvedBy
        self.approvedAt = approvedAt
    }

    /// La demande est-elle recevable ?
    public var isWellFormed: Bool {
        action != .unknown
            && requestedByRole != .unknown
            && !justificationKey.isEmpty
            && requestedByRole.rank >= action.minimumRole.rank
    }

    public var isApproved: Bool { approvedBy != nil && approvedAt != nil }

    /// Approuve, si l'approbateur en a le droit et n'est pas le demandeur.
    public func approve(by access: SupportAccessContext,
                        now: Date = Date()) -> Result<SupportFinancialActionRequest, SupportApprovalRejection> {

        guard isWellFormed                         else { return .failure(.malformedRequest) }
        guard !isApproved                          else { return .failure(.alreadyApproved) }
        guard access.isValid(now: now)             else { return .failure(.expiredAuthorization) }
        guard access.operatorID != requestedBy     else { return .failure(.selfApproval) }
        guard access.role == .complianceOfficer    else { return .failure(.insufficientRole) }
        guard access.caseID == caseID              else { return .failure(.wrongCase) }

        return .success(SupportFinancialActionRequest(
            id: id, caseID: caseID, action: action, amount: amount,
            requestedBy: requestedBy, requestedByRole: requestedByRole,
            justificationKey: justificationKey, requestedAt: requestedAt,
            approvedBy: access.operatorID, approvedAt: now
        ))
    }
}

/// Pourquoi une approbation est refusée.
public enum SupportApprovalRejection: String, Error, Sendable, Hashable, CaseIterable {

    case malformedRequest     = "MALFORMED_REQUEST"
    case alreadyApproved      = "ALREADY_APPROVED"
    case expiredAuthorization = "EXPIRED_AUTHORIZATION"

    /// Le demandeur essaie d'approuver sa propre demande.
    case selfApproval         = "SELF_APPROVAL"

    case insufficientRole     = "INSUFFICIENT_ROLE"
    case wrongCase            = "WRONG_CASE"

    public var messageKey: String { "support.approval.rejected.\(rawValue.lowercased())" }

    /// À remonter comme incident : ces deux-là ne s'expliquent pas par une
    /// manipulation d'interface.
    public var isSecurityIncident: Bool {
        self == .selfApproval || self == .wrongCase
    }
}

extension SupportOperatorRole {

    /// Ordre d'habilitation. Séparé du `rawValue` pour que l'ajout d'un rôle
    /// n'oblige pas à réordonner une chaîne.
    var rank: Int {
        switch self {
        case .unknown:           return -1
        case .agent:             return 0
        case .seniorAgent:       return 1
        case .supervisor:        return 2
        case .complianceOfficer: return 3
        }
    }
}

// MARK: - Contrat

/// Sert le SLA, les notes et les demandes d'action d'un dossier.
public protocol SupportGoverning: Sendable {

    func sla(for caseID: String) async -> Result<SupportSLA, FinanceError>

    /// Les notes lisibles sous cette habilitation. Le filtrage est fait côté
    /// backend ; le client refiltre — une note interne qui arrive quand même ne
    /// doit pas s'afficher parce que la requête était bien formée.
    func notes(for caseID: String,
               access: SupportAccessContext) async -> Result<[SupportNote], FinanceError>

    func requestFinancialAction(
        _ request: SupportFinancialActionRequest,
        idempotency: IdempotencyContext
    ) async -> Result<SupportFinancialActionRequest, FinanceError>
}

// MARK: - Défaut fermé

/// N'accorde ni SLA, ni note, ni action.
public struct ClosedSupportGovernor: SupportGoverning {

    public init() {}

    public func sla(for caseID: String) async -> Result<SupportSLA, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func notes(for caseID: String,
                      access: SupportAccessContext) async -> Result<[SupportNote], FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func requestFinancialAction(
        _ request: SupportFinancialActionRequest,
        idempotency: IdempotencyContext
    ) async -> Result<SupportFinancialActionRequest, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
