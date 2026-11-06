//
//  InvoiceContract.swift
//  CoreKit
//
//  Factures marchandes — Bloc 6, chapitre 46.
//
//  **BACKEND CONTRACT REQUIRED** — émission, consultation, revalidation,
//  paiement partiel, échéancier.
//

import Foundation

/// Factures émises par un marchand.
///
/// Distinct de ``BillPaying`` du Bloc 4 : celui-ci paie un **facturier**
/// (électricité, eau, télécoms) sur un référentiel public. Ici, un marchand
/// adresse une facture nominative à un client, avec ses lignes, ses taxes et
/// parfois son échéancier.
///
/// **Rien n'est recalculé côté client.** Ni le sous-total, ni les taxes, ni le
/// reste à payer. Le §46 l'interdit explicitement, et pour une raison précise :
/// une facture est un document opposable. Deux totaux qui divergent d'un
/// centime, c'est un litige.
public protocol InvoiceProviding: Sendable {

    /// Lit une facture. La consultation est un événement métier — `viewed` fait
    /// partie du cycle de vie, et le marchand a le droit de le savoir.
    func invoice(id: String) async -> Result<Invoice, FinanceError>

    /// Factures adressées à l'utilisateur.
    func invoices(cursor: String?) async -> Result<[Invoice], FinanceError>

    /// Revalide juste avant de payer.
    ///
    /// Une facture affichée vieillit. Entre l'affichage et le paiement, elle a
    /// pu être annulée, expirer, ou être modifiée par le marchand. Payer sur la
    /// foi de l'écran, c'est payer un document qui n'existe plus.
    func revalidate(_ snapshot: InvoiceSnapshot) async -> Result<InvoiceVerdict, FinanceError>

    /// Paie tout ou partie d'une facture.
    ///
    /// `allocation` dit **ce que ce paiement règle** : le tout, un acompte, une
    /// échéance nommée. Sans cette précision, deux paiements partiels sur la
    /// même facture deviennent impossibles à rapprocher.
    func pay(
        invoiceID: String,
        snapshot: InvoiceSnapshot,
        allocation: PaymentAllocation,
        idempotency: IdempotencyContext,
        stepUp: StepUpAttestation?
    ) async -> Result<Invoice, FinanceError>

    /// `POST /invoice/prepare` (§5.2) — **un devis**, pas un débit. Le montant
    /// est celui du serveur (`outstandingMinor`) ; l'execute suit par le chemin
    /// de Send Money, après confirmation explicite.
    func quote(_ invoice: Invoice, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `true` si cette implémentation demande un devis au serveur — distingue
    /// « je ne fais pas de devis » d'un refus serveur (voir `BillPaying`).
    var providesQuotes: Bool { get }
}

public extension InvoiceProviding {
    /// Sans devis serveur : l'écran garde le paiement direct de `pay`.
    func quote(_ invoice: Invoice, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    var providesQuotes: Bool { false }
}

// MARK: - La facture

public struct Invoice: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let merchantID: String
    public let merchantNameKey: String

    /// Numéro tel que le marchand l'a émis. Affiché, jamais composé ici.
    public let number: String

    public let state: InvoiceState
    public let lines: [InvoiceLine]

    // ── Totaux, **rendus par le backend** ────────────────────
    /// `nil` ⇒ le backend ne l'a pas fourni. **Jamais recomposé ici** : Chat
    /// Core ne rend que le reste dû et le déjà payé (`invoice/inquire`).
    public let subtotal: Money?
    public let taxTotal: Money?
    public let discountTotal: Money?
    public let total: Money?

    /// Déjà réglé. Un acompte versé change ce montant, pas `total`.
    public let paidAmount: Money

    /// Reste à payer, **calculé par le backend**.
    ///
    /// Ce n'est pas `total − paidAmount` : des frais de retard, un avoir ou un
    /// arrondi de devise peuvent s'y ajouter. Le soustraire ici produirait un
    /// second montant, et c'est celui-là que l'utilisateur paierait.
    public let amountDue: Money

    /// Échéancier, quand le marchand en propose un.
    public let installments: [InvoiceInstallment]

    /// Paiement partiel autorisé. `false` ⇒ tout ou rien.
    public let allowsPartialPayment: Bool

    /// Plusieurs payeurs admis sur la même facture (§46.4).
    public let allowsMultiplePayers: Bool

    public let issuedAt: Date
    public let dueAt: Date?
    public let expiresAt: Date?

    // ── Détection de mutation ────────────────────────────────

    /// Version du document, incrémentée par le marchand à chaque modification.
    public let version: Int

    /// Empreinte du contenu facturé, **calculée par le backend**.
    ///
    /// C'est elle qui rend une modification silencieuse détectable : deux
    /// factures de même `version` mais d'empreinte différente signalent une
    /// altération que le compteur n'a pas suivie.
    public let contentHash: String

    public init(
        id: String, merchantID: String, merchantNameKey: String, number: String,
        state: InvoiceState, lines: [InvoiceLine],
        subtotal: Money?, taxTotal: Money? = nil, discountTotal: Money? = nil,
        total: Money?, paidAmount: Money, amountDue: Money,
        installments: [InvoiceInstallment] = [],
        allowsPartialPayment: Bool, allowsMultiplePayers: Bool = false,
        issuedAt: Date, dueAt: Date? = nil, expiresAt: Date? = nil,
        version: Int, contentHash: String
    ) {
        self.id = id
        self.merchantID = merchantID
        self.merchantNameKey = merchantNameKey
        self.number = number
        self.state = state
        self.lines = lines
        self.subtotal = subtotal
        self.taxTotal = taxTotal
        self.discountTotal = discountTotal
        self.total = total
        self.paidAmount = paidAmount
        self.amountDue = amountDue
        self.installments = installments
        self.allowsPartialPayment = allowsPartialPayment
        self.allowsMultiplePayers = allowsMultiplePayers
        self.issuedAt = issuedAt
        self.dueAt = dueAt
        self.expiresAt = expiresAt
        self.version = version
        self.contentHash = contentHash
    }

    /// Épingle la facture telle qu'elle est affichée.
    public func snapshot(at now: Date = Date()) -> InvoiceSnapshot {
        InvoiceSnapshot(invoiceID: id, version: version,
                        contentHash: contentHash, amountDue: amountDue,
                        capturedAt: now)
    }

    /// Payable **maintenant**.
    ///
    /// Quatre conditions, toutes nécessaires. Une facture expirée reste
    /// consultable — c'est une pièce comptable — mais elle ne se paie plus.
    public func isPayable(at now: Date = Date()) -> Bool {
        guard state.acceptsPayment else { return false }
        if let expiresAt, now >= expiresAt { return false }
        return amountDue.minorUnits > 0
    }
}

public struct InvoiceLine: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let labelKey: String
    public let quantity: Decimal
    public let unitPrice: Money
    /// Total de ligne rendu par le backend — jamais `quantity × unitPrice`
    /// recalculé ici, où remises et arrondis par ligne seraient perdus.
    public let lineTotal: Money
    public let taxRatePercent: Decimal?

    public init(id: String, labelKey: String, quantity: Decimal,
                unitPrice: Money, lineTotal: Money, taxRatePercent: Decimal? = nil) {
        self.id = id
        self.labelKey = labelKey
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.lineTotal = lineTotal
        self.taxRatePercent = taxRatePercent
    }
}

public struct InvoiceInstallment: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let number: Int
    public let amount: Money
    public let dueAt: Date
    public let isSettled: Bool

    public init(id: String, number: Int, amount: Money, dueAt: Date, isSettled: Bool) {
        self.id = id
        self.number = number
        self.amount = amount
        self.dueAt = dueAt
        self.isSettled = isSettled
    }
}

// MARK: - États (§46.1)

public enum InvoiceState: String, Codable, Sendable, CaseIterable {
    case draft         = "DRAFT"
    case issued        = "ISSUED"
    case viewed        = "VIEWED"
    case partiallyPaid = "PARTIALLY_PAID"
    case paid          = "PAID"
    case cancelled     = "CANCELLED"
    case expired       = "EXPIRED"
    case disputed      = "DISPUTED"

    /// Un état inconnu **n'accepte aucun paiement**.
    ///
    /// Faire échouer le décodage effacerait la facture de la liste ; la traiter
    /// comme payable enverrait de l'argent sur un état qu'on ne comprend pas.
    case unknown       = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = InvoiceState(rawValue: raw) ?? .unknown
    }

    /// Seuls trois états admettent un paiement. Un brouillon n'a pas été émis,
    /// une facture annulée n'a plus d'objet, et `unknown` n'engage rien.
    public var acceptsPayment: Bool {
        switch self {
        case .issued, .viewed, .partiallyPaid: return true
        default: return false
        }
    }

    public var isTerminal: Bool {
        switch self {
        case .paid, .cancelled, .expired: return true
        default: return false
        }
    }
}

// MARK: - Instantané et verdict

/// La facture telle que l'utilisateur l'a lue.
public struct InvoiceSnapshot: Codable, Sendable, Hashable {
    public let invoiceID: String
    public let version: Int
    public let contentHash: String
    /// Le montant que l'utilisateur avait sous les yeux.
    public let amountDue: Money
    public let capturedAt: Date

    public init(invoiceID: String, version: Int, contentHash: String,
                amountDue: Money, capturedAt: Date) {
        self.invoiceID = invoiceID
        self.version = version
        self.contentHash = contentHash
        self.amountDue = amountDue
        self.capturedAt = capturedAt
    }

    /// Détecte une divergence avec la facture fraîchement lue.
    ///
    /// L'empreinte est vérifiée **avant** la version : un marchand qui modifie
    /// le contenu sans incrémenter le compteur est exactement le cas que la
    /// version seule ne verrait pas.
    public func mutation(comparedTo fresh: Invoice) -> InvoiceMutation? {
        if contentHash != fresh.contentHash {
            return version == fresh.version ? .silentContentChange : .contentChanged
        }
        if version != fresh.version { return .versionChanged }
        if amountDue != fresh.amountDue { return .amountChanged }
        return nil
    }
}

/// Ce qui a bougé sur une facture entre l'affichage et le paiement.
public enum InvoiceMutation: String, Sendable, Equatable {

    /// Contenu et version ont changé : modification déclarée.
    case contentChanged

    /// **Contenu modifié à version constante.** Le cas grave : le marchand a
    /// changé la facture sans le dire. Aucun paiement ne doit suivre.
    case silentContentChange

    case versionChanged
    case amountChanged
}

public enum InvoiceVerdict: Sendable, Equatable {

    /// Rien n'a bougé.
    case unchanged

    /// La facture a changé. `mutation` dit quoi, `fresh` porte la nouvelle.
    case mutated(InvoiceMutation, fresh: Invoice)

    case cancelled(reasonKey: String)
    case expired

    public var permitsImmediatePayment: Bool { self == .unchanged }
}

// MARK: - Affectation du paiement

/// Ce qu'un paiement règle sur une facture.
///
/// Sans cette précision, deux versements partiels deviennent indiscernables au
/// rapprochement — et c'est le client qui doit prouver ce qu'il a payé.
public enum PaymentAllocation: Sendable, Hashable, Codable {

    /// Solde la facture entière.
    case full

    /// Acompte ou versement libre. Le backend refuse si la facture n'admet
    /// pas les paiements partiels.
    case partial(Money)

    /// Règle une échéance nommée de l'échéancier.
    case installment(id: String)

    /// Le montant affiché à l'utilisateur pour cette affectation.
    ///
    /// `nil` pour une échéance : c'est le backend qui en connaît le montant, et
    /// le déduire ici reviendrait à recomposer la facture.
    public func displayedAmount(on invoice: Invoice) -> Money? {
        switch self {
        case .full:
            return invoice.amountDue
        case .partial(let amount):
            return amount
        case .installment(let id):
            return invoice.installments.first { $0.id == id }?.amount
        }
    }

    /// Recevable en l'état, avant même l'avis du backend.
    public func isWellFormed(on invoice: Invoice) -> Bool {
        switch self {
        case .full:
            return invoice.amountDue.minorUnits > 0
        case .partial(let amount):
            guard invoice.allowsPartialPayment else { return false }
            guard amount.isComparable(to: invoice.amountDue) else { return false }
            // Un versement supérieur au dû n'est pas un acompte : c'est une
            // erreur de saisie, et le backend la refuserait de toute façon.
            return amount.minorUnits > 0 && amount.minorUnits <= invoice.amountDue.minorUnits
        case .installment(let id):
            guard let target = invoice.installments.first(where: { $0.id == id }) else { return false }
            return !target.isSettled
        }
    }
}

// MARK: - Défaut fermé

/// Refuse toute facture.
///
/// Ne fabrique aucune facture de démonstration : un document opposable inventé
/// côté client est une réclamation en préparation.
public struct ClosedInvoiceProvider: InvoiceProviding {

    public init() {}

    public func invoice(id: String) async -> Result<Invoice, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func invoices(cursor: String?) async -> Result<[Invoice], FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func revalidate(_ snapshot: InvoiceSnapshot) async -> Result<InvoiceVerdict, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func pay(invoiceID: String, snapshot: InvoiceSnapshot, allocation: PaymentAllocation,
                    idempotency: IdempotencyContext,
                    stepUp: StepUpAttestation?) async -> Result<Invoice, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
