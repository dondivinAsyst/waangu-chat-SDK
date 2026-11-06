//
//  CommerceOrdering.swift
//  CoreKit
//
//  Catalogue, panier, commande, suivi et après-vente — Bloc 1, chapitre 7.
//
//  **BACKEND CONTRACT REQUIRED** — catalogue signé, prix, stock, commandes,
//  livraison, retours.
//

import Foundation

/// Acheter à un marchand depuis une conversation.
///
/// **Le panier vit côté serveur.** Un panier local se recalcule à chaque
/// ouverture d'écran, diverge entre deux appareils, et surtout : le total qu'il
/// affiche est un total que le client a calculé lui-même. Ici le client envoie
/// des intentions — ajouter, retirer — et affiche ce que le serveur renvoie.
///
/// Aucun prix, aucun sous-total, aucune taxe n'est calculé dans l'application.
public protocol CommerceOrdering: Sendable {

    /// Catalogue d'un marchand. La pagination est portée par le curseur : un
    /// catalogue entier chargé d'un coup ne tient pas sur un réseau lent.
    func catalog(
        merchantID: String,
        cursor: String?
    ) async -> Result<CommerceCatalogPage, FinanceError>

    /// Panier courant pour ce marchand. `nil` ⇒ aucun panier ouvert.
    func cart(merchantID: String) async -> Result<CommerceCart?, FinanceError>

    /// Ajoute, modifie ou retire une ligne. `quantity: 0` retire la ligne.
    ///
    /// Le serveur revalide le prix : un article dont le prix a changé depuis
    /// l'affichage revient avec le nouveau prix, et l'écran doit le montrer
    /// avant que l'utilisateur paie.
    func updateCart(
        merchantID: String,
        itemID: String,
        quantity: Int,
        idempotency: IdempotencyContext
    ) async -> Result<CommerceCart, FinanceError>

    /// Transforme le panier en commande **non payée**.
    ///
    /// Séparé du paiement : entre les deux, le stock est réservé, l'adresse est
    /// figée et le total devient opposable. Payer directement depuis un panier
    /// ferait payer un total qui pouvait encore bouger.
    func placeOrder(
        merchantID: String,
        deliveryOptionID: String?,
        noteKey: String?,
        idempotency: IdempotencyContext
    ) async -> Result<CommerceOrder, FinanceError>

    /// Paie une commande passée.
    func payOrder(
        orderID: String,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<CommerceOrder, FinanceError>

    /// Commandes de l'utilisateur, les plus récentes d'abord.
    func orders(cursor: String?) async -> Result<[CommerceOrder], FinanceError>

    func order(id: String) async -> Result<CommerceOrder, FinanceError>

    /// Annule une commande, tant que le marchand l'autorise encore.
    func cancelOrder(
        id: String,
        reasonKey: String,
        idempotency: IdempotencyContext
    ) async -> Result<CommerceOrder, FinanceError>

    /// Ouvre un retour ou un échange après livraison (§7, après-vente).
    ///
    /// Distinct du litige : un retour est une opération commerciale convenue
    /// avec le marchand ; un litige conteste la transaction elle-même. Les
    /// confondre ferait passer un échange de taille pour une fraude.
    func requestReturn(
        _ request: CommerceReturnRequest,
        idempotency: IdempotencyContext
    ) async -> Result<CommerceReturn, FinanceError>
}

// MARK: - Catalogue

public struct CommerceCatalogPage: Codable, Sendable, Hashable {

    public let items: [CommerceItem]

    /// Curseur de la page suivante. `nil` ⇒ fin du catalogue.
    public let nextCursor: String?

    /// Version du catalogue, telle que signée par le marchand. Elle accompagne
    /// chaque commande : sans elle, on ne peut plus dire quel prix était
    /// affiché au moment de l'achat.
    public let catalogVersion: String

    public init(items: [CommerceItem], nextCursor: String?, catalogVersion: String) {
        self.items = items
        self.nextCursor = nextCursor
        self.catalogVersion = catalogVersion
    }
}

public struct CommerceItem: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let nameKey: String
    public let descriptionKey: String?
    public let imageURL: URL?

    /// Prix unitaire **rendu par le backend**, taxes incluses ou non selon la
    /// juridiction — ce que `priceNoteKey` explique.
    public let unitPrice: Money
    public let priceNoteKey: String?

    /// Stock restant. `nil` ⇒ le marchand ne publie pas son stock, ce qui n'est
    /// pas la même chose que « en rupture ».
    public let remainingStock: Int?

    /// `false` ⇒ affiché grisé avec son motif. Masquer un article épuisé fait
    /// croire qu'il n'a jamais existé, et le client rappelle le marchand.
    public let isOrderable: Bool
    public let unavailableReasonKey: String?

    public init(
        id: String, nameKey: String, descriptionKey: String? = nil, imageURL: URL? = nil,
        unitPrice: Money, priceNoteKey: String? = nil, remainingStock: Int? = nil,
        isOrderable: Bool, unavailableReasonKey: String? = nil
    ) {
        self.id = id
        self.nameKey = nameKey
        self.descriptionKey = descriptionKey
        self.imageURL = imageURL
        self.unitPrice = unitPrice
        self.priceNoteKey = priceNoteKey
        self.remainingStock = remainingStock
        self.isOrderable = isOrderable
        self.unavailableReasonKey = unavailableReasonKey
    }
}

// MARK: - Panier

public struct CommerceCart: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let merchantID: String
    public let lines: [CommerceCartLine]

    /// Totaux **calculés par le serveur**. Les recomposer côté client à partir
    /// des lignes produirait un second total, et deux totaux qui divergent d'un
    /// centime suffisent à faire perdre confiance dans les deux.
    public let subtotal: Money
    public let deliveryFee: Money?
    public let taxTotal: Money?
    public let total: Money

    /// Options de livraison proposées pour ce panier.
    public let deliveryOptions: [CommerceDeliveryOption]

    /// Ce qui empêche de commander en l'état — article épuisé, minimum non
    /// atteint, adresse manquante. Vide ⇒ commandable.
    public let blockingReasonKeys: [String]

    public init(
        id: String, merchantID: String, lines: [CommerceCartLine],
        subtotal: Money, deliveryFee: Money? = nil, taxTotal: Money? = nil, total: Money,
        deliveryOptions: [CommerceDeliveryOption] = [], blockingReasonKeys: [String] = []
    ) {
        self.id = id
        self.merchantID = merchantID
        self.lines = lines
        self.subtotal = subtotal
        self.deliveryFee = deliveryFee
        self.taxTotal = taxTotal
        self.total = total
        self.deliveryOptions = deliveryOptions
        self.blockingReasonKeys = blockingReasonKeys
    }

    public var isOrderable: Bool { !lines.isEmpty && blockingReasonKeys.isEmpty }
}

public struct CommerceCartLine: Codable, Sendable, Hashable, Identifiable {

    public var id: String { itemID }
    public let itemID: String
    public let nameKey: String
    public let imageURL: URL?
    public let quantity: Int
    public let unitPrice: Money
    /// Total de ligne, rendu par le serveur — jamais `quantity × unitPrice`
    /// recalculé ici, où les remises et arrondis par ligne seraient perdus.
    public let lineTotal: Money

    /// Le prix a changé depuis l'ajout au panier. L'écran doit le signaler :
    /// laisser passer une hausse silencieuse est ce qui transforme un achat en
    /// réclamation.
    public let priceChangedSinceAdded: Bool

    public init(
        itemID: String, nameKey: String, imageURL: URL? = nil, quantity: Int,
        unitPrice: Money, lineTotal: Money, priceChangedSinceAdded: Bool = false
    ) {
        self.itemID = itemID
        self.nameKey = nameKey
        self.imageURL = imageURL
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
        self.priceChangedSinceAdded = priceChangedSinceAdded
    }
}

public struct CommerceDeliveryOption: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let labelKey: String
    public let fee: Money
    /// Délai annoncé **par le transporteur**. Une estimation calculée ici
    /// deviendrait une promesse que personne ne tient.
    public let estimatedDays: Int?

    public init(id: String, labelKey: String, fee: Money, estimatedDays: Int? = nil) {
        self.id = id
        self.labelKey = labelKey
        self.fee = fee
        self.estimatedDays = estimatedDays
    }
}

// MARK: - Commande

public struct CommerceOrder: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let merchantID: String
    public let merchantNameKey: String
    public let state: CommerceOrderState

    public let lines: [CommerceCartLine]
    public let total: Money

    /// Référence de la transaction financière, quand la commande est payée.
    /// C'est le lien entre la commande et le reçu, et il ne se devine pas.
    public let paymentReference: FinancialReference?

    /// Version du catalogue au moment de la commande, pour rejouer l'affichage
    /// tel qu'il était.
    public let catalogVersion: String?

    public let placedAt: Date
    public let updatedAt: Date

    /// Suivi de livraison, quand le marchand en publie un.
    public let trackingEvents: [CommerceTrackingEvent]

    /// Jusqu'à quand l'annulation reste possible. `nil` ⇒ plus annulable.
    public let cancellableUntil: Date?
    /// Jusqu'à quand un retour reste ouvert. `nil` ⇒ pas de retour possible.
    public let returnableUntil: Date?

    public init(
        id: String, merchantID: String, merchantNameKey: String, state: CommerceOrderState,
        lines: [CommerceCartLine], total: Money, paymentReference: FinancialReference? = nil,
        catalogVersion: String? = nil, placedAt: Date, updatedAt: Date,
        trackingEvents: [CommerceTrackingEvent] = [],
        cancellableUntil: Date? = nil, returnableUntil: Date? = nil
    ) {
        self.id = id
        self.merchantID = merchantID
        self.merchantNameKey = merchantNameKey
        self.state = state
        self.lines = lines
        self.total = total
        self.paymentReference = paymentReference
        self.catalogVersion = catalogVersion
        self.placedAt = placedAt
        self.updatedAt = updatedAt
        self.trackingEvents = trackingEvents
        self.cancellableUntil = cancellableUntil
        self.returnableUntil = returnableUntil
    }

    public func isCancellable(at now: Date = Date()) -> Bool {
        guard let cancellableUntil else { return false }
        return now < cancellableUntil && state.allowsCancellation
    }

    public func isReturnable(at now: Date = Date()) -> Bool {
        guard let returnableUntil else { return false }
        return now < returnableUntil && state == .delivered
    }
}

public enum CommerceOrderState: String, Codable, Sendable, CaseIterable {
    case awaitingPayment = "AWAITING_PAYMENT"
    case paid            = "PAID"
    case accepted        = "ACCEPTED"
    case preparing       = "PREPARING"
    case shipped         = "SHIPPED"
    case delivered       = "DELIVERED"
    case cancelled       = "CANCELLED"
    case refunded        = "REFUNDED"
    case returnOpen      = "RETURN_OPEN"
    /// État connu du backend mais pas de ce client. Affiché tel quel, jamais
    /// traduit en « livré » par défaut.
    case unknown         = "UNKNOWN"

    /// Un état inconnu ne casse pas la liste des commandes — il dégrade une
    /// ligne, là où l'échec du décodage effacerait tout l'historique.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CommerceOrderState(rawValue: raw) ?? .unknown
    }

    public var allowsCancellation: Bool {
        switch self {
        case .awaitingPayment, .paid, .accepted, .preparing: return true
        default: return false
        }
    }

    /// `true` quand l'argent est parti. Sert à décider si un litige a du sens.
    public var isSettled: Bool {
        switch self {
        case .paid, .accepted, .preparing, .shipped, .delivered, .returnOpen: return true
        default: return false
        }
    }
}

public struct CommerceTrackingEvent: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let labelKey: String
    public let occurredAt: Date
    public let locationKey: String?

    public init(id: String, labelKey: String, occurredAt: Date, locationKey: String? = nil) {
        self.id = id
        self.labelKey = labelKey
        self.occurredAt = occurredAt
        self.locationKey = locationKey
    }
}

// MARK: - Après-vente

public struct CommerceReturnRequest: Sendable, Hashable, Codable {
    public let orderID: String
    /// Lignes concernées et quantités. Un retour partiel est le cas courant.
    public let lines: [String: Int]
    public let kind: CommerceReturnKind
    public let reasonKey: String
    public let commentText: String?
    /// Pièces jointes déjà téléversées — identifiants, pas des données.
    public let evidenceIDs: [String]

    public init(orderID: String, lines: [String: Int], kind: CommerceReturnKind,
                reasonKey: String, commentText: String? = nil, evidenceIDs: [String] = []) {
        self.orderID = orderID
        self.lines = lines
        self.kind = kind
        self.reasonKey = reasonKey
        self.commentText = commentText
        self.evidenceIDs = evidenceIDs
    }

    /// Un retour sans ligne ni quantité positive n'a rien à traiter.
    public var isSubmittable: Bool {
        !lines.isEmpty && lines.values.allSatisfy { $0 > 0 } && !reasonKey.isEmpty
    }
}

public enum CommerceReturnKind: String, Codable, Sendable, CaseIterable {
    case refund   = "REFUND"
    case exchange = "EXCHANGE"
    case repair   = "REPAIR"
}

public struct CommerceReturn: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let orderID: String
    public let kind: CommerceReturnKind
    public let state: CommerceReturnState
    public let openedAt: Date
    /// Montant remboursé quand il est arrêté. `nil` tant que le marchand
    /// n'a pas tranché — et surtout pas un montant estimé ici.
    public let refundedAmount: Money?

    public init(id: String, orderID: String, kind: CommerceReturnKind,
                state: CommerceReturnState, openedAt: Date, refundedAmount: Money? = nil) {
        self.id = id
        self.orderID = orderID
        self.kind = kind
        self.state = state
        self.openedAt = openedAt
        self.refundedAmount = refundedAmount
    }
}

public enum CommerceReturnState: String, Codable, Sendable, CaseIterable {
    case open      = "OPEN"
    case approved  = "APPROVED"
    case rejected  = "REJECTED"
    case shipped   = "SHIPPED_BACK"
    case completed = "COMPLETED"
    case unknown   = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = CommerceReturnState(rawValue: raw) ?? .unknown
    }
}

// MARK: - Défaut fermé

/// Refuse tout le commerce.
///
/// Le défaut ne rend ni catalogue de démonstration ni panier vide « valide ».
/// Un catalogue factice conduit à commander des articles qui n'existent pas, et
/// l'erreur n'apparaît qu'après le paiement.
public struct ClosedCommerceOrdering: CommerceOrdering {

    public init() {}

    public func catalog(merchantID: String, cursor: String?) async -> Result<CommerceCatalogPage, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cart(merchantID: String) async -> Result<CommerceCart?, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func updateCart(merchantID: String, itemID: String, quantity: Int,
                           idempotency: IdempotencyContext) async -> Result<CommerceCart, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func placeOrder(merchantID: String, deliveryOptionID: String?, noteKey: String?,
                           idempotency: IdempotencyContext) async -> Result<CommerceOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func payOrder(orderID: String, idempotency: IdempotencyContext,
                         stepUp: StepUpAttestation?) async -> Result<CommerceOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func orders(cursor: String?) async -> Result<[CommerceOrder], FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func order(id: String) async -> Result<CommerceOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func cancelOrder(id: String, reasonKey: String,
                            idempotency: IdempotencyContext) async -> Result<CommerceOrder, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func requestReturn(_ request: CommerceReturnRequest,
                              idempotency: IdempotencyContext) async -> Result<CommerceReturn, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
