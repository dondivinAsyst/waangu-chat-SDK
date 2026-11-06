//
//  SplitBillContract.swift
//  CoreKit
//
//  Partage d'addition — Bloc 6, chapitre 50.
//
//  **BACKEND CONTRACT REQUIRED** — création, consentement, contributions,
//  relances, clôture.
//

import Foundation

/// Partage d'une dépense entre plusieurs personnes.
///
/// **Le partage vit côté serveur.** Un partage tenu localement recalcule ses
/// parts à chaque ouverture, diverge entre deux appareils, et surtout : le
/// montant qu'il affiche à chacun est un montant que le client a calculé
/// lui-même. Le §50 l'interdit — « recalcul financier définitif côté client ».
///
/// **Rien n'est débité sans consentement.** Un participant reçoit une demande ;
/// il l'accepte ou la refuse. Aucun chemin de ce contrat ne permet de prélever
/// quelqu'un qui n'a rien accepté, et c'est structurel : `contribute` part de
/// l'appareil du contributeur, jamais de celui de l'organisateur.
public protocol SplitBillManaging: Sendable {

    /// Partages où l'utilisateur est organisateur ou participant.
    func splits(cursor: String?) async -> Result<[SplitBill], FinanceError>

    func split(id: String) async -> Result<SplitBill, FinanceError>

    /// Crée un partage. Les parts sont **calculées par le backend** à partir de
    /// la stratégie demandée : arrondis et restes compris.
    func create(
        _ draft: SplitBillDraft,
        idempotency: IdempotencyContext
    ) async -> Result<SplitBill, FinanceError>

    /// Répond à une demande de participation.
    ///
    /// Accepter n'est **pas** payer : c'est reconnaître devoir une part. Le
    /// paiement passe par `contribute`, avec son propre step-up.
    func respond(
        splitID: String,
        response: SplitParticipantResponse,
        idempotency: IdempotencyContext
    ) async -> Result<SplitBill, FinanceError>

    /// Paie sa part. **Part de l'appareil du contributeur.**
    func contribute(
        splitID: String,
        amount: Money,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<SplitBill, FinanceError>

    /// Relance un participant. Le backend applique la politique de relance et
    /// refuse au-delà — voir ``SplitReminderPolicy``.
    func remind(
        splitID: String,
        participantID: String,
        idempotency: IdempotencyContext
    ) async -> Result<SplitBill, FinanceError>

    /// Clôture le partage. Réservé à l'organisateur.
    func close(
        splitID: String,
        idempotency: IdempotencyContext
    ) async -> Result<SplitBill, FinanceError>

    /// `POST /split-bill/pay` (§4) — **un devis pour une seule part**.
    ///
    /// Distinct de ``contribute`` : le serveur ne règle rien ici, il rend un
    /// `PrepareSendMoneyResponse` que la personne confirme ensuite, par le même
    /// chemin que Send Money. `contribute` promettait un partage mis à jour,
    /// c'est-à-dire un débit abouti dans un seul appel — ce que le contrat ne
    /// fait pas et n'autorise pas : « ne jamais payer le partage entier d'un
    /// tap », une part vaut un consentement.
    ///
    /// `amount` à `nil` : le serveur connaît la part due.
    func payShare(
        splitID: String,
        conversationID: String?,
        amount: Money?,
        idempotency: IdempotencyContext
    ) async -> Result<TransferQuote, FinanceError>
}

public extension SplitBillManaging {
    /// Sans devis serveur (implémentations locales) : rien à confirmer.
    func payShare(splitID: String, conversationID: String?, amount: Money?,
                  idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// `false` si **ce client** n'a aucune route pour lister les partages.
    ///
    /// À ne pas confondre avec un refus : `capabilityUnavailable` dit « votre
    /// compte n'y a pas droit », et c'est une affirmation que **seul le serveur**
    /// peut faire. Le Hub venait au contraire d'accorder `SPLIT_BILL`
    /// (`enabled: true`, `reason: null`) ; répondre « indisponible pour votre
    /// compte » parce que le client n'a pas d'endpoint revenait à parler à la
    /// place de la source de vérité, et à lui faire dire le contraire de ce
    /// qu'elle disait.
    ///
    /// L'écran lit ce drapeau pour dire ce qui est vrai — la liste n'est pas
    /// encore servie — sans rien affirmer sur les droits de la personne.
    var listsSplits: Bool { true }
}

// MARK: - Le partage

public struct SplitBill: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let labelKey: String
    public let organizerID: String
    public let conversationID: String?

    /// Montant total, **rendu par le backend**.
    public let total: Money

    /// Somme déjà collectée. Jamais recalculée depuis les contributions : une
    /// contribution en vol ou remboursée fausserait le total local.
    public let collected: Money

    public let participants: [SplitParticipant]
    public let strategy: SplitStrategy
    public let state: SplitSettlementState

    /// Qui voit quoi. Le partage social ne doit pas exposer les finances de
    /// chacun à tout le groupe.
    public let privacyScope: SplitPrivacyScope

    public let reminderPolicy: SplitReminderPolicy

    /// Source de la dépense, quand elle en a une — une facture, un paiement
    /// marchand déjà réglé par l'organisateur.
    public let sourceReference: FinancialReference?

    public let createdAt: Date
    public let updatedAt: Date
    public let expiresAt: Date?

    public init(
        id: String, labelKey: String, organizerID: String, conversationID: String? = nil,
        total: Money, collected: Money, participants: [SplitParticipant],
        strategy: SplitStrategy, state: SplitSettlementState,
        privacyScope: SplitPrivacyScope, reminderPolicy: SplitReminderPolicy,
        sourceReference: FinancialReference? = nil,
        createdAt: Date, updatedAt: Date, expiresAt: Date? = nil
    ) {
        self.id = id
        self.labelKey = labelKey
        self.organizerID = organizerID
        self.conversationID = conversationID
        self.total = total
        self.collected = collected
        self.participants = participants
        self.strategy = strategy
        self.state = state
        self.privacyScope = privacyScope
        self.reminderPolicy = reminderPolicy
        self.sourceReference = sourceReference
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.expiresAt = expiresAt
    }

    /// La part de l'utilisateur courant, s'il en a une.
    public func participant(_ userID: String) -> SplitParticipant? {
        participants.first { $0.userID == userID }
    }

    public func isOrganizer(_ userID: String) -> Bool { organizerID == userID }

    /// Reste à collecter, **rendu par différence des montants serveur**.
    ///
    /// Les deux termes viennent du backend, donc la soustraction n'invente rien.
    /// Recomposer `collected` depuis la liste des participants, en revanche,
    /// produirait un second chiffre.
    public var remaining: Money? {
        guard total.isComparable(to: collected) else { return nil }
        return Money(minorUnits: max(0, total.minorUnits - collected.minorUnits),
                     currency: total.currency)
    }
}

// MARK: - Participant et consentement

public struct SplitParticipant: Codable, Sendable, Hashable, Identifiable {

    public var id: String { userID }
    public let userID: String
    public let displayName: String

    /// Part demandée, **calculée par le backend**.
    public let share: Money

    /// Ce que le participant a effectivement versé.
    public let contributed: Money

    /// Où en est son consentement.
    public let consent: SplitParticipantConsent

    /// Exclu du partage par l'organisateur — il ne doit rien.
    public let isExcluded: Bool

    /// Nombre de relances déjà envoyées, **compté par le backend**.
    public let reminderCount: Int
    public let lastRemindedAt: Date?

    public init(userID: String, displayName: String, share: Money, contributed: Money,
                consent: SplitParticipantConsent, isExcluded: Bool = false,
                reminderCount: Int = 0, lastRemindedAt: Date? = nil) {
        self.userID = userID
        self.displayName = displayName
        self.share = share
        self.contributed = contributed
        self.consent = consent
        self.isExcluded = isExcluded
        self.reminderCount = reminderCount
        self.lastRemindedAt = lastRemindedAt
    }

    /// Il reste quelque chose à verser.
    public var hasOutstandingAmount: Bool {
        !isExcluded && contributed.minorUnits < share.minorUnits
    }

    /// Ce qu'il reste à ce participant à verser.
    public var outstanding: Money? {
        guard share.isComparable(to: contributed) else { return nil }
        return Money(minorUnits: max(0, share.minorUnits - contributed.minorUnits),
                     currency: share.currency)
    }
}

/// L'état du consentement d'un participant.
///
/// **Aucun débit sans `accepted`.** C'est l'invariant du §50, et il est porté
/// par le type : `canBeDebited` n'est vrai que dans un seul cas.
public enum SplitParticipantConsent: String, Codable, Sendable, CaseIterable {

    /// Invité, n'a pas encore répondu.
    case pending  = "PENDING"

    /// A reconnu devoir sa part. **Accepter n'est pas payer.**
    case accepted = "ACCEPTED"

    /// A refusé. L'organisateur peut l'exclure ou réajuster les parts.
    case declined = "DECLINED"

    /// L'invitation a expiré sans réponse.
    case expired  = "EXPIRED"

    /// État inconnu de ce client. **Traité comme non consenti.**
    case unknown  = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SplitParticipantConsent(rawValue: raw) ?? .unknown
    }

    /// Le seul état qui autorise un mouvement d'argent.
    public var canBeDebited: Bool { self == .accepted }

    /// Une relance a encore du sens.
    public var isAwaitingResponse: Bool { self == .pending }
}

public enum SplitParticipantResponse: String, Codable, Sendable {
    case accept
    case decline
}

// MARK: - Stratégie de répartition

/// Comment le total se répartit.
///
/// La stratégie est **déclarée**, les montants sont **calculés par le backend**.
/// Le client ne divise jamais : un reste de division sur trois parts d'un
/// montant impair doit tomber quelque part, et c'est une décision comptable.
public enum SplitStrategy: Sendable, Hashable, Codable {

    /// Parts égales. Le reste de division est attribué par le backend selon
    /// ``SplitRoundingPolicy``.
    case equal

    /// Montants fixés participant par participant.
    case custom([String: Decimal])

    /// Parts proportionnelles à un poids — nombre de plats, de nuits, de parts.
    case proportional([String: Decimal])

    /// Somme des poids ou des montants, pour vérification d'affichage.
    ///
    /// **Ne produit aucun montant à débiter** : sert seulement à signaler à
    /// l'organisateur que sa saisie ne couvre pas le total, avant l'envoi.
    public var declaredSum: Decimal? {
        switch self {
        case .equal: return nil
        case .custom(let values), .proportional(let values):
            return values.values.reduce(0, +)
        }
    }
}

/// À qui revient le reste d'une division inexacte.
///
/// Trois parts sur 10 unités mineures font 3,33 — et une unité doit tomber
/// quelque part. Laisser le client trancher produirait des répartitions
/// différentes selon l'appareil qui affiche.
public enum SplitRoundingPolicy: String, Codable, Sendable, CaseIterable {
    /// L'organisateur absorbe le reste.
    case organizerAbsorbs = "ORGANIZER_ABSORBS"
    /// Réparti sur les premiers participants, un centime chacun.
    case distributed      = "DISTRIBUTED"
    /// Le premier participant absorbe.
    case firstAbsorbs     = "FIRST_ABSORBS"
}

// MARK: - Confidentialité

/// Qui voit quoi dans un partage.
///
/// Un partage d'addition est social ; les finances de chacun ne le sont pas.
/// Sans cette portée, participer à un dîner révèle à tout le groupe qui a payé,
/// qui traîne, et qui a refusé.
public enum SplitPrivacyScope: String, Codable, Sendable, CaseIterable {

    /// Chacun voit toutes les parts et tous les versements.
    case openToAll     = "OPEN_TO_ALL"

    /// Chacun voit sa propre part ; l'organisateur voit tout.
    case ownShareOnly  = "OWN_SHARE_ONLY"

    /// Chacun voit sa part et l'avancement global, sans le détail par personne.
    case aggregateOnly = "AGGREGATE_ONLY"

    /// Portée inconnue ⇒ la plus restrictive.
    ///
    /// L'inverse exposerait des montants qu'une version plus récente avait
    /// justement décidé de masquer.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SplitPrivacyScope(rawValue: raw) ?? .ownShareOnly
    }

    /// Ce participant peut-il voir la part d'un autre ?
    public func canSeeOtherShares(isOrganizer: Bool) -> Bool {
        if isOrganizer { return true }
        return self == .openToAll
    }

    /// Peut-il voir l'avancement global ?
    public func canSeeAggregate(isOrganizer: Bool) -> Bool {
        if isOrganizer { return true }
        return self != .ownShareOnly
    }
}

// MARK: - Relances

/// Ce que l'organisateur peut envoyer, et à quelle fréquence.
///
/// Le §50 interdit les « relances illimitées ». Sans borne, un partage devient
/// un canal de harcèlement que le destinataire ne peut pas couper.
public struct SplitReminderPolicy: Codable, Sendable, Hashable {

    /// Nombre maximal de relances par participant.
    public let maxPerParticipant: Int

    /// Délai minimal entre deux relances.
    public let minimumInterval: TimeInterval

    public init(maxPerParticipant: Int, minimumInterval: TimeInterval) {
        self.maxPerParticipant = maxPerParticipant
        self.minimumInterval = minimumInterval
    }

    /// Une relance est-elle recevable ?
    ///
    /// Contrôle **local**, pour ne pas proposer un geste que le backend
    /// refusera. Le backend reste l'autorité — lui seul voit les relances
    /// envoyées depuis un autre appareil.
    public func allowsReminder(for participant: SplitParticipant,
                               at now: Date = Date()) -> Bool {
        guard participant.consent.isAwaitingResponse || participant.hasOutstandingAmount else {
            return false
        }
        guard participant.reminderCount < maxPerParticipant else { return false }
        if let last = participant.lastRemindedAt,
           now.timeIntervalSince(last) < minimumInterval {
            return false
        }
        return true
    }
}

// MARK: - État du règlement

public enum SplitSettlementState: String, Codable, Sendable, CaseIterable {
    case draft            = "DRAFT"
    case open             = "OPEN"
    case partiallySettled = "PARTIALLY_SETTLED"
    case settled          = "SETTLED"
    case closed           = "CLOSED"
    case cancelled        = "CANCELLED"
    case expired          = "EXPIRED"
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SplitSettlementState(rawValue: raw) ?? .unknown
    }

    /// De nouvelles contributions sont acceptées.
    public var acceptsContributions: Bool {
        self == .open || self == .partiallySettled
    }

    public var isTerminal: Bool {
        switch self {
        case .settled, .closed, .cancelled, .expired: return true
        default: return false
        }
    }
}

// MARK: - Brouillon

public struct SplitBillDraft: Sendable, Hashable, Codable {
    public let labelKey: String
    public let total: Money
    public let participantIDs: [String]
    public let strategy: SplitStrategy
    public let privacyScope: SplitPrivacyScope
    public let conversationID: String?
    public let sourceReference: FinancialReference?
    public let expiresAfter: TimeInterval?

    public init(labelKey: String, total: Money, participantIDs: [String],
                strategy: SplitStrategy, privacyScope: SplitPrivacyScope,
                conversationID: String? = nil, sourceReference: FinancialReference? = nil,
                expiresAfter: TimeInterval? = nil) {
        self.labelKey = labelKey
        self.total = total
        self.participantIDs = participantIDs
        self.strategy = strategy
        self.privacyScope = privacyScope
        self.conversationID = conversationID
        self.sourceReference = sourceReference
        self.expiresAfter = expiresAfter
    }

    /// Recevable en l'état, avant l'avis du backend.
    ///
    /// Ne vérifie **pas** que les montants tombent juste : c'est le backend qui
    /// répartit, et un contrôle local trop strict refuserait une saisie que
    /// l'arrondi serveur aurait acceptée.
    public var isSubmittable: Bool {
        guard !labelKey.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard total.minorUnits > 0, !participantIDs.isEmpty else { return false }

        switch strategy {
        case .equal:
            return true
        case .custom(let values), .proportional(let values):
            // Chaque participant doit avoir une valeur, et aucune ne peut être
            // négative — un poids négatif rendrait une part négative.
            guard values.count == participantIDs.count else { return false }
            guard participantIDs.allSatisfy({ values[$0] != nil }) else { return false }
            return values.values.allSatisfy { $0 > 0 }
        }
    }
}

// MARK: - Défaut fermé

/// Ne crée, ne collecte et ne relance rien.
///
/// **Ne tient volontairement aucun état local.** Un partage mémorisé côté
/// client est un registre financier que le client n'a pas le droit d'être.
public struct ClosedSplitBillManager: SplitBillManaging {

    public init() {}

    public func splits(cursor: String?) async -> Result<[SplitBill], FinanceError> { .failure(.capabilityUnavailable) }
    public func split(id: String) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
    public func create(_ draft: SplitBillDraft, idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
    public func respond(splitID: String, response: SplitParticipantResponse,
                        idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
    public func contribute(splitID: String, amount: Money, idempotency: IdempotencyContext,
                           stepUp: StepUpAttestation?) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
    public func remind(splitID: String, participantID: String,
                       idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
    public func close(splitID: String, idempotency: IdempotencyContext) async -> Result<SplitBill, FinanceError> { .failure(.capabilityUnavailable) }
}
