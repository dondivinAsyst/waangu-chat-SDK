//
//  BillPaying.swift
//  CoreKit
//
//  Paiement de facture — Bloc 3, chapitre 21.
//
//  **BACKEND CONTRACT REQUIRED** — `GET /v1/billers`, `POST /v1/bills/lookup`,
//  `POST /v1/bill-payments`.
//

import Foundation

/// Catalogue de facturiers et paiement de factures.
public protocol BillPaying: Sendable {

    /// Catégories et facturiers disponibles, filtrés par le backend selon pays,
    /// province et territoire. Le client ne filtre pas : il ne connaît pas les
    /// licences détenues sur chaque marché.
    func categories() async -> Result<[BillerCategory], FinanceError>

    /// Formulaire du facturier, **rendu par le backend**.
    ///
    /// Rend `DynamicBiller`, le modèle **déjà existant** de
    /// `CoreKit/Protocols/DomainKit/DynamicBiller/`. Il porte ce qu'un
    /// formulaire de facturier exige réellement et qu'un modèle réécrit à côté
    /// n'aurait pas : expression de validation, masque de saisie, dépendances
    /// parent/enfants avec réinitialisation en cascade, priorité d'affichage,
    /// mapping vers les clés backend et bornes dynamiques.
    ///
    /// Un second modèle de formulaire aurait divergé du premier au premier
    /// facturier qui ajoute un champ — la version « formulaire » des quatre
    /// `PaymentStatus` incompatibles que le Bloc 1 a supprimés.
    func form(for billerID: String) async -> Result<DynamicBiller, FinanceError>

    /// Résout une facture à partir des champs saisis.
    func lookup(billerID: String,
                fields: [String: String]) async -> Result<Bill, FinanceError>

    func pay(_ bill: Bill,
             amount: Decimal?,
             idempotency: IdempotencyContext) async -> Result<FinancialReference, FinanceError>

    /// `POST /pay-bill/prepare` (§5.1) — **un devis**, pas un débit : frais,
    /// total, confirmation à accepter. L'execute suit par le même chemin que
    /// Send Money, après confirmation explicite.
    func quote(_ bill: Bill, amount: Decimal, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `true` si cette implémentation demande un devis au serveur.
    ///
    /// Distingue **« je ne sais pas faire de devis »** de **« le serveur a
    /// refusé ce devis »**, que `capabilityUnavailable` disait tous les deux.
    /// L'écran repliait donc un refus serveur — `CF_004`, « Channel not
    /// supported: BILLER » — sur un paiement direct, c'est-à-dire qu'il
    /// tentait de débiter après que le serveur a dit non.
    var providesQuotes: Bool { get }

    /// `POST /pay-bill/requery` (§5.1) — où en est une facture payée : le
    /// débit **et** sa prise en compte par le facturier.
    ///
    /// Le geste du `REQUERY_BILLER` d'une carte : l'argent est parti, le
    /// facturier n'a pas confirmé. **Jamais un nouvel execute** — on relit.
    /// Un paiement abouti mais non livré rend `.pendingReconciliation`.
    func requery(_ reference: FinancialReference) async -> Result<PaymentStatus, FinanceError>
}

public extension BillPaying {
    /// Par défaut : rien à relire. Seule une implémentation branchée sur
    /// `/pay-bill/requery` sait où en est le facturier.
    func requery(_ reference: FinancialReference) async -> Result<PaymentStatus, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Sans devis serveur (implémentations locales) : pas de devis — l'écran
    /// garde le paiement direct de `pay`.
    func quote(_ bill: Bill, amount: Decimal, conversationID: String?,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Par défaut non : seule une implémentation branchée sur `/pay-bill/prepare`
    /// l'affirme.
    var providesQuotes: Bool { false }
}

// MARK: - Formulaire

/// Valide un champ de formulaire facturier : la raison du refus, ou `nil`.
///
/// La règle (requis, longueurs, motif) vit dans
/// `DomainKit.DynamicBillerFormLogic` — la même que le Wallet. Le Chat ne
/// dépend pas de DomainKit : l'app l'injecte sous cette forme. Sans texte :
/// le Chat formule la raison dans la langue de l'app.
public typealias BillFieldValidating = @Sendable (DynamicBillerField, [String: String]) -> BillFieldIssue?
//
// `DynamicForm`, `DynamicFormField` et `Biller` ont été **supprimés** d'ici :
// ils dupliquaient `DynamicBiller`, `DynamicBillerField` et `BillerForm` de
// `CoreKit/Protocols/DomainKit/DynamicBiller/DynamicBillerModels.swift`, en
// moins complet. La validation et la logique de cascade vivent dans
// `DomainKit/Domain/DynamicBiller/DynamicBillerFormLogic.swift` et arrivent au
// Chat par l'implémentation injectée.

// MARK: - Facture

public struct Bill: Codable, Sendable, Hashable {

    public let reference: FinancialReference
    public let billerID: String
    public let customerLabel: String

    public let amountDue: Decimal
    public let currency: String
    /// Arriérés cumulés, rendus séparément du montant courant.
    public let arrears: Decimal?

    public let dueDate: Date?
    /// Instant de lecture **serveur**. Une facture datée ne se paie pas en
    /// silence : le montant a pu changer depuis.
    public let fetchedAt: Date
    public let allowsPartialPayment: Bool

    public init(reference: FinancialReference, billerID: String,
                customerLabel: String, amountDue: Decimal, currency: String,
                arrears: Decimal? = nil, dueDate: Date? = nil,
                fetchedAt: Date, allowsPartialPayment: Bool) {
        self.reference = reference
        self.billerID = billerID
        self.customerLabel = customerLabel
        self.amountDue = amountDue
        self.currency = currency
        self.arrears = arrears
        self.dueDate = dueDate
        self.fetchedAt = fetchedAt
        self.allowsPartialPayment = allowsPartialPayment
    }
}

public extension Bill {

    /// Au-delà, la facture doit être relue avant paiement.
    ///
    /// Cinq minutes : assez pour un parcours de saisie ordinaire, assez court
    /// pour qu'un montant révisé ne soit pas payé à l'ancienne valeur.
    static let freshnessWindow: TimeInterval = 300

    func isStale(asOf now: Date = Date()) -> Bool {
        now.timeIntervalSince(fetchedAt) > Self.freshnessWindow
    }

    /// `true` si ce montant peut être payé sur cette facture.
    ///
    /// Un paiement partiel n'est permis que si le facturier l'accepte, et jamais
    /// au-delà du dû : payer plus créerait un avoir que le Chat ne sait pas suivre.
    func accepts(amount: Decimal) -> Bool {
        guard amount > 0, amount <= amountDue else { return false }
        return allowsPartialPayment || amount == amountDue
    }
}
