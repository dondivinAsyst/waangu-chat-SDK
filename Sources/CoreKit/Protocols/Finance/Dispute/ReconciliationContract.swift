//
//  ReconciliationContract.swift
//  CoreKit
//
//  Incidents et réconciliation — Bloc 6, chapitre 53.
//
//  **BACKEND CONTRACT REQUIRED** — ouverture de dossier, instantanés de
//  vérité, escalade partenaire, résolution.
//

import Foundation

/// Rapproche ce que chaque système affirme quand ils se contredisent.
///
/// Le chapitre 53 énumère les désaccords qui comptent : débit confirmé et
/// commande impayée, commande payée sans débit, double débit, mauvais marchand,
/// règlement carte divergent, contribution invisible.
///
/// Chacun a la même forme : **plusieurs systèmes, plusieurs vérités, aucune
/// autorité locale pour trancher.** Divin ne réconcilie donc pas — il constate,
/// documente, et escalade. La résolution appartient aux systèmes financiers.
public protocol ReconciliationProviding: Sendable {

    /// Ouvre un dossier de rapprochement.
    ///
    /// Ne corrige rien et ne rejoue rien. Un désaccord entre deux systèmes se
    /// résout par une décision humaine ou par un rapprochement backend, jamais
    /// par une nouvelle tentative de paiement — c'est ainsi qu'on double un
    /// débit en croyant réparer.
    func open(
        _ request: ReconciliationRequest,
        idempotency: IdempotencyContext
    ) async -> Result<ReconciliationCase, FinanceError>

    func caseDetail(id: String) async -> Result<ReconciliationCase, FinanceError>
    func cases(cursor: String?) async -> Result<[ReconciliationCase], FinanceError>

    /// Récupère ce que chaque système affirme, à un instant donné.
    ///
    /// Les instantanés sont demandés **ensemble** : pris à des moments
    /// différents, ils décriraient un désaccord qui n'a jamais existé
    /// simultanément.
    func truthSnapshots(caseID: String) async -> Result<TruthSnapshotBundle, FinanceError>

    /// Ajoute une pièce au dossier.
    func attachEvidence(
        caseID: String,
        evidence: EvidenceBundleReference,
        idempotency: IdempotencyContext
    ) async -> Result<ReconciliationCase, FinanceError>

    /// Escalade vers le partenaire concerné — PGW, émetteur, réseau, marchand.
    func escalate(
        caseID: String,
        to partner: PartnerEscalationTarget,
        idempotency: IdempotencyContext
    ) async -> Result<ReconciliationCase, FinanceError>
}

// MARK: - Le dossier

public struct ReconciliationCase: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let kind: ReconciliationKind
    public let state: ReconciliationState

    /// Ce qui relie toutes les traces de cet incident, tous canaux confondus.
    ///
    /// Le §53 l'exige sous le nom d'*omnichannel correlation ID* : sans lui,
    /// un incident vécu sur iOS et vu sur le web reste deux dossiers.
    public let omnichannelCorrelationID: String

    /// Références des objets en désaccord.
    public let subjects: [ReconciliationSubject]

    /// Écart constaté, quand il est chiffrable. `nil` pour un désaccord d'état
    /// sans écart de montant — une commande impayée face à un débit confirmé.
    public let discrepancyAmount: Money?

    public let evidence: [EvidenceBundleReference]
    public let escalations: [PartnerEscalation]

    public let openedAt: Date
    public let updatedAt: Date
    public let resolvedAt: Date?

    /// Comment le dossier s'est terminé. `nil` tant qu'il est ouvert.
    public let resolution: ReconciliationResolution?

    public init(
        id: String, kind: ReconciliationKind, state: ReconciliationState,
        omnichannelCorrelationID: String, subjects: [ReconciliationSubject],
        discrepancyAmount: Money? = nil, evidence: [EvidenceBundleReference] = [],
        escalations: [PartnerEscalation] = [], openedAt: Date, updatedAt: Date,
        resolvedAt: Date? = nil, resolution: ReconciliationResolution? = nil
    ) {
        self.id = id
        self.kind = kind
        self.state = state
        self.omnichannelCorrelationID = omnichannelCorrelationID
        self.subjects = subjects
        self.discrepancyAmount = discrepancyAmount
        self.evidence = evidence
        self.escalations = escalations
        self.openedAt = openedAt
        self.updatedAt = updatedAt
        self.resolvedAt = resolvedAt
        self.resolution = resolution
    }

    /// Le dossier attend quelque chose de l'utilisateur.
    public var awaitsUserAction: Bool { state == .awaitingEvidence }
}

/// Ce que le dossier constate.
///
/// Nommer le désaccord dès l'ouverture n'est pas cosmétique : « débit sans
/// commande » et « commande sans débit » s'escaladent vers des partenaires
/// différents, et les confondre fait perdre les délais de recours.
public enum ReconciliationKind: String, Codable, Sendable, CaseIterable {

    /// Débit confirmé, commande impayée côté marchand.
    case debitWithoutOrder      = "DEBIT_WITHOUT_ORDER"

    /// Commande payée côté marchand, aucun débit constaté.
    case orderWithoutDebit      = "ORDER_WITHOUT_DEBIT"

    /// Deux débits pour une seule opération.
    case duplicateDebit         = "DUPLICATE_DEBIT"

    /// Le bénéficiaire du débit n'est pas celui affiché.
    case wrongMerchant          = "WRONG_MERCHANT"

    /// Le règlement carte diverge de la capture.
    case cardSettlementMismatch = "CARD_SETTLEMENT_MISMATCH"

    /// Remboursement promis, jamais reçu.
    case missingRefund          = "MISSING_REFUND"

    /// Contribution versée, invisible dans la collecte.
    case missingContribution    = "MISSING_CONTRIBUTION"

    /// Retrait débité, espèces non délivrées.
    case atmDispenseFailure     = "ATM_DISPENSE_FAILURE"

    case unknown                = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReconciliationKind(rawValue: raw) ?? .unknown
    }

    /// De l'argent a quitté le compte selon au moins un système.
    ///
    /// Décide de l'urgence : un désaccord sans débit constaté peut attendre,
    /// un double débit non.
    public var involvesDebitedFunds: Bool {
        switch self {
        case .debitWithoutOrder, .duplicateDebit, .wrongMerchant,
             .cardSettlementMismatch, .missingRefund, .atmDispenseFailure:
            return true
        case .orderWithoutDebit, .missingContribution, .unknown:
            return false
        }
    }
}

/// Un objet impliqué dans le désaccord.
public struct ReconciliationSubject: Codable, Sendable, Hashable {
    /// Système qui détient cette vérité.
    public let system: TruthSystem
    /// Référence de l'objet dans ce système. Opaque à cette couche.
    public let objectID: String
    public let objectType: String

    public init(system: TruthSystem, objectID: String, objectType: String) {
        self.system = system
        self.objectID = objectID
        self.objectType = objectType
    }
}

/// Qui détient une vérité.
///
/// La doctrine l'énonce : la vérité financière appartient aux systèmes
/// financiers, la vérité commerciale au backend marchand, la vérité carte au
/// Card System. Cette énumération rend la frontière explicite plutôt que
/// commentée.
public enum TruthSystem: String, Codable, Sendable, CaseIterable {
    case ledger         = "LEDGER"
    case paymentGateway = "PAYMENT_GATEWAY"
    case merchantBackend = "MERCHANT_BACKEND"
    case cardSystem     = "CARD_SYSTEM"
    case collectionService = "COLLECTION_SERVICE"
    case nativeApp      = "NATIVE_APP"
    case unknown        = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = TruthSystem(rawValue: raw) ?? .unknown
    }
}

// MARK: - Instantanés de vérité

/// Ce que chaque système affirme, **au même instant**.
///
/// Le groupe est un objet à part entière plutôt que trois appels : des
/// instantanés pris à des moments différents décriraient un désaccord qui n'a
/// jamais existé simultanément, et enverraient chercher une panne inexistante.
public struct TruthSnapshotBundle: Codable, Sendable, Hashable {

    public let caseID: String

    /// Instant commun de capture, **fixé par le backend**.
    public let capturedAt: Date

    public let financial: FinancialTruthSnapshot?
    public let merchant: MerchantTruthSnapshot?
    public let card: CardTruthSnapshot?

    public init(caseID: String, capturedAt: Date,
                financial: FinancialTruthSnapshot? = nil,
                merchant: MerchantTruthSnapshot? = nil,
                card: CardTruthSnapshot? = nil) {
        self.caseID = caseID
        self.capturedAt = capturedAt
        self.financial = financial
        self.merchant = merchant
        self.card = card
    }

    /// Les systèmes qui ont répondu.
    ///
    /// Un système absent n'est **pas** un système en accord : c'est un système
    /// qui n'a pas répondu, et conclure d'un silence serait la faute que ce
    /// dossier existe pour éviter.
    public var respondingSystems: [TruthSystem] {
        var systems: [TruthSystem] = []
        if financial != nil { systems.append(.ledger) }
        if merchant != nil { systems.append(.merchantBackend) }
        if card != nil { systems.append(.cardSystem) }
        return systems
    }

    /// Un rapprochement est-il concluable ?
    ///
    /// Il faut **au moins deux** systèmes : avec un seul, il n'y a pas de
    /// désaccord à constater, seulement une affirmation isolée.
    public var isConclusive: Bool { respondingSystems.count >= 2 }
}

/// Ce que le système financier affirme.
public struct FinancialTruthSnapshot: Codable, Sendable, Hashable {
    public let reference: FinancialReference
    public let status: PaymentStatus
    public let amount: Money
    public let objectRevision: Int
    public let observedAt: Date

    public init(reference: FinancialReference, status: PaymentStatus,
                amount: Money, objectRevision: Int, observedAt: Date) {
        self.reference = reference
        self.status = status
        self.amount = amount
        self.objectRevision = objectRevision
        self.observedAt = observedAt
    }
}

/// Ce que le backend marchand affirme.
public struct MerchantTruthSnapshot: Codable, Sendable, Hashable {
    public let merchantID: String
    public let orderID: String?
    public let invoiceID: String?
    /// État tel que le marchand le voit, en clé — jamais promu en statut
    /// financier : un marchand qui dit « payé » ne débite pas.
    public let merchantStateKey: String
    public let amount: Money?
    public let observedAt: Date

    public init(merchantID: String, orderID: String? = nil, invoiceID: String? = nil,
                merchantStateKey: String, amount: Money? = nil, observedAt: Date) {
        self.merchantID = merchantID
        self.orderID = orderID
        self.invoiceID = invoiceID
        self.merchantStateKey = merchantStateKey
        self.amount = amount
        self.observedAt = observedAt
    }
}

/// Ce que le système de cartes affirme.
public struct CardTruthSnapshot: Codable, Sendable, Hashable {
    public let cardID: String
    public let transactionID: String
    public let state: CardTransactionState
    public let authorizedAmount: Money
    public let capturedAmount: Money?
    public let settledAmount: Money?
    public let observedAt: Date

    public init(cardID: String, transactionID: String, state: CardTransactionState,
                authorizedAmount: Money, capturedAmount: Money? = nil,
                settledAmount: Money? = nil, observedAt: Date) {
        self.cardID = cardID
        self.transactionID = transactionID
        self.state = state
        self.authorizedAmount = authorizedAmount
        self.capturedAmount = capturedAmount
        self.settledAmount = settledAmount
        self.observedAt = observedAt
    }
}

// MARK: - Machine d'état

public enum ReconciliationState: String, Codable, Sendable, CaseIterable {
    case opened           = "OPENED"
    case gatheringTruth   = "GATHERING_TRUTH"
    case awaitingEvidence = "AWAITING_EVIDENCE"
    case underReview      = "UNDER_REVIEW"
    case escalated        = "ESCALATED"
    case resolved         = "RESOLVED"
    case closedNoAction   = "CLOSED_NO_ACTION"
    case unknown          = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReconciliationState(rawValue: raw) ?? .unknown
    }

    public var isTerminal: Bool {
        self == .resolved || self == .closedNoAction
    }
}

/// Transitions autorisées d'un dossier de rapprochement.
public enum ReconciliationStateMachine {

    public static func allowedTransitions(from state: ReconciliationState) -> Set<ReconciliationState> {
        switch state {
        case .opened:
            return [.gatheringTruth, .closedNoAction, .unknown]
        case .gatheringTruth:
            return [.awaitingEvidence, .underReview, .closedNoAction, .unknown]
        case .awaitingEvidence:
            return [.underReview, .closedNoAction, .unknown]
        case .underReview:
            return [.escalated, .resolved, .closedNoAction, .awaitingEvidence, .unknown]
        case .escalated:
            // Une escalade ne redevient pas « en revue » : elle attend le
            // partenaire, et revenir en arrière effacerait cette attente.
            return [.resolved, .closedNoAction, .unknown]
        case .resolved, .closedNoAction:
            return []
        case .unknown:
            return Set(ReconciliationState.allCases).subtracting([.unknown])
        }
    }

    public static func isAllowed(from current: ReconciliationState,
                                 to next: ReconciliationState) -> Bool {
        if current == next { return true }
        return allowedTransitions(from: current).contains(next)
    }
}

// MARK: - Pièces et escalade

/// Référence à un faisceau de pièces, **jamais les pièces elles-mêmes**.
///
/// Un dossier de rapprochement voyage dans les journaux et les tickets ; y
/// embarquer une capture d'écran de relevé bancaire exposerait des données
/// qu'aucun de ces canaux n'est autorisé à porter.
public struct EvidenceBundleReference: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kindKey: String
    public let itemCount: Int
    public let collectedAt: Date

    public init(id: String, kindKey: String, itemCount: Int, collectedAt: Date) {
        self.id = id
        self.kindKey = kindKey
        self.itemCount = itemCount
        self.collectedAt = collectedAt
    }
}

public enum PartnerEscalationTarget: String, Codable, Sendable, CaseIterable {
    case paymentGateway = "PAYMENT_GATEWAY"
    case cardIssuer     = "CARD_ISSUER"
    case cardNetwork    = "CARD_NETWORK"
    case merchant       = "MERCHANT"
    case collectionService = "COLLECTION_SERVICE"
    case internalSupport = "INTERNAL_SUPPORT"
}

public struct PartnerEscalation: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let target: PartnerEscalationTarget
    public let openedAt: Date
    /// Échéance de réponse du partenaire. Sert à savoir quand relancer, et à
    /// ne pas laisser un dossier dormir chez quelqu'un d'autre.
    public let respondBy: Date?
    public let statusKey: String

    public init(id: String, target: PartnerEscalationTarget, openedAt: Date,
                respondBy: Date? = nil, statusKey: String) {
        self.id = id
        self.target = target
        self.openedAt = openedAt
        self.respondBy = respondBy
        self.statusKey = statusKey
    }

    /// Le partenaire a dépassé son délai.
    public func isOverdue(at now: Date = Date()) -> Bool {
        guard let respondBy else { return false }
        return now > respondBy
    }
}

// MARK: - Résolution

public struct ReconciliationResolution: Codable, Sendable, Hashable {
    public let outcome: ReconciliationOutcome
    public let explanationKey: String
    /// Mouvement correctif, quand il y en a eu un. **Décidé par le backend.**
    public let correctiveReference: FinancialReference?

    public init(outcome: ReconciliationOutcome, explanationKey: String,
                correctiveReference: FinancialReference? = nil) {
        self.outcome = outcome
        self.explanationKey = explanationKey
        self.correctiveReference = correctiveReference
    }
}

public enum ReconciliationOutcome: String, Codable, Sendable, CaseIterable {
    /// Les systèmes étaient d'accord ; le désaccord venait d'un décalage.
    case noDiscrepancy   = "NO_DISCREPANCY"
    /// Corrigé par un mouvement — remboursement, régularisation.
    case corrected       = "CORRECTED"
    /// Le débit était justifié.
    case debitUpheld     = "DEBIT_UPHELD"
    /// Tranché en faveur de l'utilisateur.
    case refunded        = "REFUNDED"
    /// Le partenaire n'a pas répondu dans les délais.
    case partnerTimeout  = "PARTNER_TIMEOUT"
    case unknown         = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ReconciliationOutcome(rawValue: raw) ?? .unknown
    }
}

// MARK: - Demande

public struct ReconciliationRequest: Sendable, Hashable, Codable {
    public let kind: ReconciliationKind
    public let subjects: [ReconciliationSubject]
    public let descriptionText: String?
    public let omnichannelCorrelationID: String?

    public init(kind: ReconciliationKind, subjects: [ReconciliationSubject],
                descriptionText: String? = nil, omnichannelCorrelationID: String? = nil) {
        self.kind = kind
        self.subjects = subjects
        self.descriptionText = descriptionText
        self.omnichannelCorrelationID = omnichannelCorrelationID
    }

    /// Un dossier a besoin d'**au moins deux** systèmes en désaccord.
    ///
    /// Avec un seul sujet, il n'y a rien à rapprocher : c'est une réclamation,
    /// et elle passe par le support.
    public var isSubmittable: Bool {
        guard kind != .unknown else { return false }
        let systems = Set(subjects.map(\.system))
        return systems.count >= 2
    }
}

// MARK: - Défaut fermé

/// N'ouvre aucun dossier et ne rapproche rien.
public struct ClosedReconciliationProvider: ReconciliationProviding {

    public init() {}

    public func open(_ request: ReconciliationRequest,
                     idempotency: IdempotencyContext) async -> Result<ReconciliationCase, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func caseDetail(id: String) async -> Result<ReconciliationCase, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cases(cursor: String?) async -> Result<[ReconciliationCase], FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func truthSnapshots(caseID: String) async -> Result<TruthSnapshotBundle, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func attachEvidence(caseID: String, evidence: EvidenceBundleReference,
                               idempotency: IdempotencyContext) async -> Result<ReconciliationCase, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func escalate(caseID: String, to partner: PartnerEscalationTarget,
                         idempotency: IdempotencyContext) async -> Result<ReconciliationCase, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
