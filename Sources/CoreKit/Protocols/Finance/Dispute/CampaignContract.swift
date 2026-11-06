//
//  CampaignContract.swift
//  CoreKit
//
//  Tontines, cagnottes et collectes — Bloc 6, chapitre 51.
//
//  **BACKEND CONTRACT REQUIRED** — création, contributions, séquestre,
//  décaissement, vote, remboursement, suspension pour fraude.
//

import Foundation

/// Collectes de fonds entre plusieurs personnes.
///
/// Le chapitre couvre quatre objets que la doctrine sépare : la collecte
/// informelle entre proches, la tontine à tour de rôle, la cagnotte pour un
/// événement, et l'appel de fonds ouvert. Ils partagent un cycle de vie, pas
/// leur régime : une tontine engage un tour de cotisations, une cagnotte non.
///
/// **La vérité des collectes appartient au service collectif.** Divin n'est
/// pas un séquestre : il consulte l'état d'un séquestre tenu ailleurs, et
/// ``EscrowStateReference`` ne porte qu'une référence, jamais des fonds.
public protocol CampaignManaging: Sendable {

    func campaigns(cursor: String?) async -> Result<[Campaign], FinanceError>
    func campaign(id: String) async -> Result<Campaign, FinanceError>

    func create(
        _ draft: CampaignDraft,
        idempotency: IdempotencyContext
    ) async -> Result<Campaign, FinanceError>

    /// Contribue à une collecte.
    ///
    /// L'anonymat demandé ici est **public uniquement** : il masque le nom aux
    /// autres participants. Le backend connaît toujours le contributeur, et
    /// c'est non négociable — une contribution intraçable est une contribution
    /// que la conformité ne peut pas examiner.
    func contribute(
        _ intent: ContributionIntent,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<Campaign, FinanceError>

    /// Demande un décaissement vers le bénéficiaire.
    ///
    /// **Ne décaisse pas.** Ouvre un flux qui peut exiger un vote, une
    /// vérification de bénéficiaire, ou un délai. C'est le backend qui
    /// déclenche le mouvement, jamais cet appel.
    func requestDisbursement(
        campaignID: String,
        amount: Money?,
        reasonKey: String,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<DisbursementWorkflow, FinanceError>

    func disbursement(id: String) async -> Result<DisbursementWorkflow, FinanceError>

    /// Vote sur un décaissement soumis au groupe.
    func vote(
        disbursementID: String,
        approve: Bool,
        idempotency: IdempotencyContext
    ) async -> Result<DisbursementWorkflow, FinanceError>

    /// Demande le remboursement de sa contribution.
    func requestRefund(
        campaignID: String,
        reasonKey: String,
        idempotency: IdempotencyContext
    ) async -> Result<CampaignRefund, FinanceError>

    /// Signale une collecte suspecte.
    ///
    /// Le signalement est **immédiat et sans friction** : une collecte
    /// frauduleuse collecte pendant qu'on hésite.
    func report(
        campaignID: String,
        reasonKey: String,
        idempotency: IdempotencyContext
    ) async -> Result<Void, FinanceError>
}

// MARK: - La collecte

public struct Campaign: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let kind: CampaignKind
    public let titleKey: String
    public let descriptionKey: String?

    public let organizer: CampaignOrganizer
    public let beneficiary: CampaignBeneficiary

    /// Objectif. `nil` ⇒ collecte ouverte, sans cible.
    public let target: Money?

    /// Collecté, **rendu par le backend**.
    public let collected: Money

    /// Déjà décaissé.
    public let disbursed: Money

    public let state: CampaignState
    public let policy: CollectionPolicy

    /// Référence du séquestre. **Une référence, pas des fonds.**
    public let escrow: EscrowStateReference?

    public let contributionCount: Int
    public let conversationID: String?

    public let createdAt: Date
    public let deadline: Date?

    /// Référence d'audit immuable, exigée au chapitre 51.
    ///
    /// Permet de rejouer l'historique financier d'une collecte auprès du
    /// service collectif, indépendamment de ce que cette application affiche.
    public let auditReference: String?

    public init(
        id: String, kind: CampaignKind, titleKey: String, descriptionKey: String? = nil,
        organizer: CampaignOrganizer, beneficiary: CampaignBeneficiary,
        target: Money? = nil, collected: Money, disbursed: Money,
        state: CampaignState, policy: CollectionPolicy,
        escrow: EscrowStateReference? = nil, contributionCount: Int = 0,
        conversationID: String? = nil, createdAt: Date, deadline: Date? = nil,
        auditReference: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.organizer = organizer
        self.beneficiary = beneficiary
        self.target = target
        self.collected = collected
        self.disbursed = disbursed
        self.state = state
        self.policy = policy
        self.escrow = escrow
        self.contributionCount = contributionCount
        self.conversationID = conversationID
        self.createdAt = createdAt
        self.deadline = deadline
        self.auditReference = auditReference
    }

    /// Progression vers l'objectif. **Ratio d'affichage** : ne produit aucun
    /// montant et n'engage rien.
    public var progressPercent: Decimal? {
        guard let target, target.minorUnits > 0,
              target.isComparable(to: collected) else { return nil }
        return min(100, Decimal(collected.minorUnits) / Decimal(target.minorUnits) * 100)
    }

    /// Accepte des contributions **maintenant**.
    ///
    /// Quatre conditions. Un bénéficiaire non vérifié bloque : le §51 exige la
    /// vérification du bénéficiaire, et collecter d'abord pour vérifier ensuite
    /// est le schéma exact de la collecte frauduleuse.
    public func acceptsContributions(at now: Date = Date()) -> Bool {
        guard state.acceptsContributions else { return false }
        guard beneficiary.verification.permitsCollection else { return false }
        if let deadline, now >= deadline { return false }
        return true
    }
}

public enum CampaignKind: String, Codable, Sendable, CaseIterable {
    case informalCollection = "INFORMAL_COLLECTION"
    case tontine            = "TONTINE"
    case eventPot           = "EVENT_POT"
    case socialContribution = "SOCIAL_CONTRIBUTION"
    case fundraising        = "FUNDRAISING"
    case unknown            = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CampaignKind(rawValue: raw) ?? .unknown
    }

    /// Une tontine engage un tour de cotisations : on n'en sort pas comme d'une
    /// cagnotte. L'interface doit le dire **avant** l'adhésion.
    public var createsRecurringObligation: Bool { self == .tontine }
}

// MARK: - Organisateur et bénéficiaire

public struct CampaignOrganizer: Codable, Sendable, Hashable {
    public let actor: FinancialActor
    /// Niveau de confiance, **établi par le backend** — ancienneté, collectes
    /// passées, signalements. Jamais calculé ici.
    public let trustLevel: OrganizerTrustLevel

    public init(actor: FinancialActor, trustLevel: OrganizerTrustLevel) {
        self.actor = actor
        self.trustLevel = trustLevel
    }
}

public enum OrganizerTrustLevel: String, Codable, Sendable, CaseIterable {
    case newOrganizer = "NEW"
    case established  = "ESTABLISHED"
    case trusted      = "TRUSTED"
    case flagged      = "FLAGGED"

    /// Un niveau inconnu retombe sur `newOrganizer`, pas sur `trusted`.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = OrganizerTrustLevel(rawValue: raw) ?? .newOrganizer
    }

    /// Un avertissement doit s'afficher avant de contribuer.
    public var warrantsWarning: Bool { self == .flagged || self == .newOrganizer }
}

/// Le destinataire final des fonds.
///
/// Distinct de l'organisateur : la personne qui ouvre une cagnotte n'est pas
/// toujours celle qui reçoit. Les confondre rendrait invisible le changement de
/// bénéficiaire, qui est le vecteur classique de détournement.
public struct CampaignBeneficiary: Codable, Sendable, Hashable {

    public let actor: FinancialActor
    public let verification: BeneficiaryVerification

    /// Version de l'identité du bénéficiaire.
    ///
    /// Un changement de bénéficiaire **exige une revalidation** : le §30 en
    /// fait un P0. Sans version, le changement est indétectable.
    public let identityVersion: String

    public init(actor: FinancialActor, verification: BeneficiaryVerification,
                identityVersion: String) {
        self.actor = actor
        self.verification = verification
        self.identityVersion = identityVersion
    }
}

public enum BeneficiaryVerification: String, Codable, Sendable, CaseIterable {
    case unverified  = "UNVERIFIED"
    case pending     = "PENDING"
    case verified    = "VERIFIED"
    case rejected    = "REJECTED"

    /// Vérification inconnue ⇒ non vérifiée. Collecter vers un bénéficiaire
    /// dont on ne comprend pas le statut est exclu.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = BeneficiaryVerification(rawValue: raw) ?? .unverified
    }

    /// Seul un bénéficiaire vérifié peut recevoir des contributions.
    public var permitsCollection: Bool { self == .verified }
}

// MARK: - Politique

public struct CollectionPolicy: Codable, Sendable, Hashable {

    /// Montant de contribution imposé. `nil` ⇒ libre.
    public let fixedContribution: Money?
    public let minimumContribution: Money?
    public let maximumContribution: Money?

    /// Les contributeurs peuvent-ils demander l'anonymat **public** ?
    public let allowsPublicAnonymity: Bool

    /// Le décaissement passe-t-il par un vote du groupe ?
    public let requiresVoteForDisbursement: Bool

    /// Quorum de votes favorables, en pourcentage.
    public let voteThresholdPercent: Int?

    /// Les contributeurs peuvent-ils se faire rembourser ?
    public let allowsRefund: Bool

    /// Qui voit la liste des contributions.
    public let visibility: CampaignVisibility

    public init(fixedContribution: Money? = nil, minimumContribution: Money? = nil,
                maximumContribution: Money? = nil, allowsPublicAnonymity: Bool,
                requiresVoteForDisbursement: Bool, voteThresholdPercent: Int? = nil,
                allowsRefund: Bool, visibility: CampaignVisibility) {
        self.fixedContribution = fixedContribution
        self.minimumContribution = minimumContribution
        self.maximumContribution = maximumContribution
        self.allowsPublicAnonymity = allowsPublicAnonymity
        self.requiresVoteForDisbursement = requiresVoteForDisbursement
        self.voteThresholdPercent = voteThresholdPercent
        self.allowsRefund = allowsRefund
        self.visibility = visibility
    }

    /// Ce montant est-il recevable ? Contrôle **local**, pour ne pas proposer
    /// un versement que le backend refusera.
    public func accepts(_ amount: Money) -> Bool {
        guard amount.minorUnits > 0 else { return false }
        if let fixed { return amount == fixed }
        if let minimum = minimumContribution,
           amount.isComparable(to: minimum), amount.minorUnits < minimum.minorUnits {
            return false
        }
        if let maximum = maximumContribution,
           amount.isComparable(to: maximum), amount.minorUnits > maximum.minorUnits {
            return false
        }
        return true
    }

    private var fixed: Money? { fixedContribution }
}

public enum CampaignVisibility: String, Codable, Sendable, CaseIterable {
    case contributorsOnly = "CONTRIBUTORS_ONLY"
    case participants     = "PARTICIPANTS"
    case publicList       = "PUBLIC"

    /// Visibilité inconnue ⇒ la plus restrictive.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CampaignVisibility(rawValue: raw) ?? .contributorsOnly
    }
}

// MARK: - Contribution

public struct ContributionIntent: Sendable, Hashable, Codable {

    public let campaignID: String
    public let amount: Money

    /// Masquer son nom **aux autres participants**.
    ///
    /// Ne masque rien au backend, ni à la conformité. Le §51 l'écrit sans
    /// ambiguïté : l'anonymat est public, jamais réglementaire, et jamais un
    /// moyen de contourner la conformité.
    public let isPubliclyAnonymous: Bool

    /// Message accompagnant la contribution.
    public let messageText: String?

    public init(campaignID: String, amount: Money,
                isPubliclyAnonymous: Bool = false, messageText: String? = nil) {
        self.campaignID = campaignID
        self.amount = amount
        self.isPubliclyAnonymous = isPubliclyAnonymous
        self.messageText = messageText
    }

    /// Recevable au regard de la politique de la collecte.
    public func isWellFormed(under policy: CollectionPolicy) -> Bool {
        guard policy.accepts(amount) else { return false }
        // Demander l'anonymat là où la collecte ne l'autorise pas produirait
        // une contribution nominative alors que le contributeur croyait le
        // contraire — pire que le refus.
        if isPubliclyAnonymous && !policy.allowsPublicAnonymity { return false }
        return true
    }
}

public struct CampaignContribution: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let amount: Money
    /// `nil` quand la contribution est publiquement anonyme.
    public let contributorDisplayName: String?
    public let messageText: String?
    public let contributedAt: Date
    public let reference: FinancialReference?

    public init(id: String, amount: Money, contributorDisplayName: String? = nil,
                messageText: String? = nil, contributedAt: Date,
                reference: FinancialReference? = nil) {
        self.id = id
        self.amount = amount
        self.contributorDisplayName = contributorDisplayName
        self.messageText = messageText
        self.contributedAt = contributedAt
        self.reference = reference
    }

    public var isAnonymous: Bool { contributorDisplayName == nil }
}

// MARK: - Séquestre

/// Référence à un séquestre tenu **ailleurs**.
///
/// Divin n'est pas un séquestre autonome — la doctrine l'interdit explicitement.
/// Cette structure ne porte aucun fonds : elle dit où ils sont et dans quel
/// état, pour que l'interface puisse le montrer sans le prétendre.
public struct EscrowStateReference: Codable, Sendable, Hashable {
    public let escrowID: String
    /// Établissement qui détient les fonds.
    public let custodianID: String
    public let state: EscrowState
    public let heldAmount: Money
    public let asOf: Date

    public init(escrowID: String, custodianID: String, state: EscrowState,
                heldAmount: Money, asOf: Date) {
        self.escrowID = escrowID
        self.custodianID = custodianID
        self.state = state
        self.heldAmount = heldAmount
        self.asOf = asOf
    }
}

public enum EscrowState: String, Codable, Sendable, CaseIterable {
    case holding   = "HOLDING"
    case releasing = "RELEASING"
    case released  = "RELEASED"
    case refunding = "REFUNDING"
    case frozen    = "FROZEN"
    case unknown   = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = EscrowState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Décaissement

public struct DisbursementWorkflow: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let campaignID: String
    public let amount: Money
    public let state: DisbursementState

    /// Vérification du bénéficiaire **au moment de la demande**.
    ///
    /// Refaite ici et pas seulement à la création : c'est entre les deux qu'un
    /// changement de bénéficiaire passerait inaperçu.
    public let beneficiaryVerification: BeneficiaryVerification

    /// Version d'identité du bénéficiaire visé, pour détecter un changement.
    public let beneficiaryIdentityVersion: String

    public let vote: DisbursementVote?
    public let requestedAt: Date
    public let reference: FinancialReference?

    public init(id: String, campaignID: String, amount: Money,
                state: DisbursementState, beneficiaryVerification: BeneficiaryVerification,
                beneficiaryIdentityVersion: String, vote: DisbursementVote? = nil,
                requestedAt: Date, reference: FinancialReference? = nil) {
        self.id = id
        self.campaignID = campaignID
        self.amount = amount
        self.state = state
        self.beneficiaryVerification = beneficiaryVerification
        self.beneficiaryIdentityVersion = beneficiaryIdentityVersion
        self.vote = vote
        self.requestedAt = requestedAt
        self.reference = reference
    }

    /// Le bénéficiaire a changé depuis l'ouverture de la collecte.
    ///
    /// Marqué P0 par le §30 : « si une collecte peut changer de bénéficiaire
    /// sans revalidation ». L'interface doit le montrer et bloquer.
    public func beneficiaryChanged(since campaign: Campaign) -> Bool {
        beneficiaryIdentityVersion != campaign.beneficiary.identityVersion
    }
}

public enum DisbursementState: String, Codable, Sendable, CaseIterable {
    case requested        = "REQUESTED"
    case awaitingVote     = "AWAITING_VOTE"
    case voteFailed       = "VOTE_FAILED"
    case complianceReview = "COMPLIANCE_REVIEW"
    case approved         = "APPROVED"
    case processing       = "PROCESSING"
    case completed        = "COMPLETED"
    case rejected         = "REJECTED"
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = DisbursementState(rawValue: raw) ?? .unknown
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .rejected, .voteFailed: return true
        default: return false
        }
    }
}

public struct DisbursementVote: Codable, Sendable, Hashable {
    public let approvals: Int
    public let rejections: Int
    public let eligibleVoters: Int
    public let thresholdPercent: Int
    public let closesAt: Date?
    /// L'utilisateur courant a-t-il déjà voté ?
    public let hasCurrentUserVoted: Bool

    public init(approvals: Int, rejections: Int, eligibleVoters: Int,
                thresholdPercent: Int, closesAt: Date? = nil,
                hasCurrentUserVoted: Bool = false) {
        self.approvals = approvals
        self.rejections = rejections
        self.eligibleVoters = eligibleVoters
        self.thresholdPercent = thresholdPercent
        self.closesAt = closesAt
        self.hasCurrentUserVoted = hasCurrentUserVoted
    }

    /// Progression du vote. **Ratio d'affichage** : le quorum est constaté par
    /// le backend, qui seul connaît les votes arrivés ailleurs.
    public var approvalPercent: Int {
        guard eligibleVoters > 0 else { return 0 }
        return Int((Double(approvals) / Double(eligibleVoters)) * 100)
    }
}

// MARK: - Remboursement

public struct CampaignRefund: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let campaignID: String
    public let amount: Money
    public let state: DisbursementState
    public let requestedAt: Date

    public init(id: String, campaignID: String, amount: Money,
                state: DisbursementState, requestedAt: Date) {
        self.id = id
        self.campaignID = campaignID
        self.amount = amount
        self.state = state
        self.requestedAt = requestedAt
    }
}

// MARK: - État de la collecte

public enum CampaignState: String, Codable, Sendable, CaseIterable {
    case draft      = "DRAFT"
    case open       = "OPEN"
    case targetMet  = "TARGET_MET"
    case closed     = "CLOSED"
    case disbursing = "DISBURSING"
    case completed  = "COMPLETED"
    /// Suspendue pour suspicion de fraude. Ni contribution, ni décaissement.
    case suspended  = "SUSPENDED"
    case refunding  = "REFUNDING"
    case cancelled  = "CANCELLED"
    case unknown    = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CampaignState(rawValue: raw) ?? .unknown
    }

    /// `targetMet` accepte encore : dépasser un objectif n'est pas une erreur.
    public var acceptsContributions: Bool {
        self == .open || self == .targetMet
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled: return true
        default: return false
        }
    }
}

// MARK: - Brouillon

public struct CampaignDraft: Sendable, Hashable, Codable {
    public let kind: CampaignKind
    public let titleKey: String
    public let descriptionKey: String?
    public let beneficiaryID: String
    public let target: Money?
    public let policy: CollectionPolicy
    public let conversationID: String?
    public let deadline: Date?

    public init(kind: CampaignKind, titleKey: String, descriptionKey: String? = nil,
                beneficiaryID: String, target: Money? = nil, policy: CollectionPolicy,
                conversationID: String? = nil, deadline: Date? = nil) {
        self.kind = kind
        self.titleKey = titleKey
        self.descriptionKey = descriptionKey
        self.beneficiaryID = beneficiaryID
        self.target = target
        self.policy = policy
        self.conversationID = conversationID
        self.deadline = deadline
    }

    public var isSubmittable: Bool {
        guard !titleKey.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard !beneficiaryID.isEmpty else { return false }
        // Une nature inconnue ne se crée pas : elle vient d'un décodage raté.
        guard kind != .unknown else { return false }
        if let target, target.minorUnits <= 0 { return false }
        return true
    }
}

// MARK: - Défaut fermé

/// Ne crée, ne collecte et ne décaisse rien.
public struct ClosedCampaignManager: CampaignManaging {

    public init() {}

    public func campaigns(cursor: String?) async -> Result<[Campaign], FinanceError> { .failure(.capabilityUnavailable) }
    public func campaign(id: String) async -> Result<Campaign, FinanceError> { .failure(.capabilityUnavailable) }
    public func create(_ draft: CampaignDraft, idempotency: IdempotencyContext) async -> Result<Campaign, FinanceError> { .failure(.capabilityUnavailable) }
    public func contribute(_ intent: ContributionIntent, idempotency: IdempotencyContext,
                           stepUp: StepUpAttestation?) async -> Result<Campaign, FinanceError> { .failure(.capabilityUnavailable) }
    public func requestDisbursement(campaignID: String, amount: Money?, reasonKey: String,
                                    idempotency: IdempotencyContext,
                                    stepUp: StepUpAttestation?) async -> Result<DisbursementWorkflow, FinanceError> { .failure(.capabilityUnavailable) }
    public func disbursement(id: String) async -> Result<DisbursementWorkflow, FinanceError> { .failure(.capabilityUnavailable) }
    public func vote(disbursementID: String, approve: Bool,
                     idempotency: IdempotencyContext) async -> Result<DisbursementWorkflow, FinanceError> { .failure(.capabilityUnavailable) }
    public func requestRefund(campaignID: String, reasonKey: String,
                              idempotency: IdempotencyContext) async -> Result<CampaignRefund, FinanceError> { .failure(.capabilityUnavailable) }
    public func report(campaignID: String, reasonKey: String,
                       idempotency: IdempotencyContext) async -> Result<Void, FinanceError> { .failure(.capabilityUnavailable) }
}
