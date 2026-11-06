//
//  TopUpOrdering.swift
//  CoreKit
//
//  Recharge — Bloc 3, chapitre 23.
//
//  Servi par Chat Core (INTEGRATION_CHAT_FINANCE.md §5.3) :
//  `GET /top-up/catalogue`, `POST /top-up/resolve-msisdn`, `/prepare`,
//  `/execute`, `/requery`. `/top-up/delivery` est refusé par le serveur
//  (`CF_054`) : aucune méthode ne l'expose.
//

import Foundation

/// Catalogue de recharges et passage d'ordres.
public protocol TopUpOrdering: Sendable {

    /// Produits disponibles pour ce numéro.
    ///
    /// - Parameter msisdn: numéro au format E.164. **L'opérateur est déterminé
    ///   par le backend**, pas par un préfixe deviné côté client : la portabilité
    ///   des numéros rend toute déduction locale fausse tôt ou tard, et recharger
    ///   le mauvais opérateur est une perte sèche pour l'utilisateur.
    func catalog(for msisdn: String) async -> Result<[TopUpProduct], FinanceError>

    /// Passe un ordre, éventuellement sur plusieurs lignes.
    ///
    /// **Jamais le chemin du serveur réel.** Le contrat §5.3 prépare, fait
    /// confirmer, puis exécute : rendre un ordre abouti d'un seul appel
    /// recharge sans que personne ait confirmé. Une implémentation branchée sur
    /// Chat Core le refuse et annonce ``providesQuotes``.
    func order(
        _ request: TopUpOrderRequest,
        idempotency: IdempotencyContext
    ) async -> Result<TopUpOrder, FinanceError>

    /// `POST /top-up/prepare` (§5.3) — **un devis**, pas une recharge.
    ///
    /// Même chemin que la facture et les espèces : le devis se confirme
    /// ensuite par l'execute unique de Send Money.
    func quote(_ request: TopUpOrderRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError>

    /// `POST /top-up/bulk` (§5.3) — **un devis par ligne**, jamais un seul.
    ///
    /// Le contrat est explicite : « chaque ligne = son propre FCO +
    /// confirmation (pas un seul execute pour le lot) ». Recharger cinq numéros
    /// est donc cinq opérations, qui peuvent aboutir séparément — c'est ce que
    /// ``TopUpOrder/Aggregate/partial(succeeded:failed:)`` représente.
    ///
    /// Une seule ligne passe par ``quote``: le lot n'a pas à exister pour un
    /// numéro, et `/prepare` est la route que le contrat lui donne.
    func quoteBatch(_ request: TopUpOrderRequest,
                    idempotency: IdempotencyContext) async -> Result<[TopUpQuotedLine], FinanceError>

    /// `true` si cette implémentation demande un devis au serveur.
    ///
    /// Distingue « je ne sais pas faire de devis » d'un refus serveur, que
    /// `capabilityUnavailable` disait tous les deux.
    var providesQuotes: Bool { get }

    func requery(_ reference: FinancialReference) async -> Result<TopUpOrder, FinanceError>
}

public extension TopUpOrdering {

    /// Par défaut : aucun devis. Les doublures gardent leur ordre direct, et
    /// ajouter ``quote`` au contrat ne casse aucune conformance existante.
    func quote(_ request: TopUpOrderRequest,
               idempotency: IdempotencyContext) async -> Result<TransferQuote, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func quoteBatch(_ request: TopUpOrderRequest,
                    idempotency: IdempotencyContext) async -> Result<[TopUpQuotedLine], FinanceError> {
        .failure(.capabilityUnavailable)
    }

    var providesQuotes: Bool { false }
}

/// Une ligne d'un lot et le devis qui lui appartient.
///
/// Le numéro voyage avec son devis parce que le compte rendu est **par
/// destinataire** : une référence seule ne dit pas à qui la recharge était
/// destinée, et c'est la première chose à relire quand trois lignes sur cinq
/// aboutissent.
public struct TopUpQuotedLine: Sendable, Hashable, Identifiable {
    public var id: String { quote.reference.id }
    public let msisdn: String
    public let quote: TransferQuote

    public init(msisdn: String, quote: TransferQuote) {
        self.msisdn = msisdn
        self.quote = quote
    }
}

// MARK: - Produit

public struct TopUpProduct: Codable, Sendable, Hashable, Identifiable {
    public let id: String
    public let kind: TopUpKind
    public let labelKey: String
    public let amount: Decimal
    public let currency: String
    public let operatorName: String

    public init(id: String, kind: TopUpKind, labelKey: String,
                amount: Decimal, currency: String, operatorName: String) {
        self.id = id
        self.kind = kind
        self.labelKey = labelKey
        self.amount = amount
        self.currency = currency
        self.operatorName = operatorName
    }
}

public enum TopUpKind: String, Codable, Sendable, CaseIterable {
    case airtime, data, voice, sms, bundle, roaming

    /// Le serveur a bien rendu une recharge, mais **n'a pas dit sa nature**.
    ///
    /// Le catalogue de Chat Core range ses produits par catégorie de facturier
    /// (`TOPUP`, `SUBSCRIPTION`, `FEES`, `TAX`) : crédit d'appel et forfait data
    /// y portent tous deux `TOPUP`, et seul le libellé les distingue. Ranger
    /// « Data 1 Go » sous « Crédit d'appel » parce qu'il faut bien choisir une
    /// nature serait une invention ; l'écran ne groupe donc pas ce qu'il ne sait
    /// pas distinguer.
    case unspecified
}

// MARK: - Ordre

public struct TopUpOrderRequest: Sendable, Hashable, Codable {
    /// Une ligne par destinataire. Une seule pour le cas ordinaire.
    public let lines: [TopUpLine]
    public let conversationID: String?

    public init(lines: [TopUpLine], conversationID: String? = nil) {
        self.lines = lines
        self.conversationID = conversationID
    }
}

public struct TopUpLine: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let msisdn: String
    public let productID: String

    public init(id: String = UUID().uuidString, msisdn: String, productID: String) {
        self.id = id
        self.msisdn = msisdn
        self.productID = productID
    }
}

// MARK: - Succès partiel

/// Un ordre de recharge et le sort de **chacune** de ses lignes.
///
/// **Le cas propre au chapitre 23.** Une recharge groupée de cinq lignes peut en
/// réussir trois. Le modèle « un objet, un statut » du Bloc 1 ne le représente
/// pas : afficher « échoué » sur une opération partiellement débitée est un faux
/// état, et le Bloc 1 a été écrit pour les empêcher.
///
/// La réponse retenue : un objet parent qui **ne porte pas de statut propre**,
/// et une ligne par destinataire qui en porte un. Le statut du parent est
/// *dérivé* des lignes, jamais rendu par le backend comme une vérité séparée —
/// deux sources se contrediraient.
public struct TopUpOrder: Sendable, Hashable, Codable {

    public let reference: FinancialReference
    public let results: [TopUpLineResult]

    public init(reference: FinancialReference, results: [TopUpLineResult]) {
        self.reference = reference
        self.results = results
    }
}

public struct TopUpLineResult: Sendable, Hashable, Codable, Identifiable {
    public let id: String
    public let msisdn: String
    public let status: PaymentStatus
    /// Motif d'échec, clé de localisation. Rendu par le backend.
    public let failureReasonKey: String?

    public init(id: String, msisdn: String, status: PaymentStatus,
                failureReasonKey: String? = nil) {
        self.id = id
        self.msisdn = msisdn
        self.status = status
        self.failureReasonKey = failureReasonKey
    }
}

// MARK: - Agrégation

public extension TopUpOrder {

    /// Ce que l'ordre est **globalement**, dérivé des lignes.
    public enum Aggregate: Sendable, Equatable {
        case allSucceeded
        case allFailed
        /// Certaines lignes ont abouti, d'autres non — l'utilisateur a été
        /// débité pour une partie seulement.
        case partial(succeeded: Int, failed: Int)
        case inFlight
        /// Au moins une ligne est ambiguë : rien ne peut être conclu.
        case undetermined
    }

    var aggregate: Aggregate {
        guard !results.isEmpty else { return .undetermined }

        // L'ignorance l'emporte sur tout le reste. Une ligne `unknown` interdit
        // de conclure « tout a réussi » comme « tout a échoué » : l'utilisateur
        // doit voir qu'on ne sait pas, pas une moyenne rassurante.
        if results.contains(where: { $0.status.requiresReconciliation }) { return .undetermined }

        if results.contains(where: { $0.status.isInFlight }) { return .inFlight }

        let succeeded = results.filter { $0.status == .confirmed || $0.status == .completed }.count
        let failed = results.count - succeeded

        if failed == 0 { return .allSucceeded }
        if succeeded == 0 { return .allFailed }
        return .partial(succeeded: succeeded, failed: failed)
    }

    /// Lignes qu'une reprise peut relancer — **elles seules**.
    ///
    /// Rejouer l'ordre entier redébiterait les lignes déjà abouties. C'est
    /// l'isolation d'échec exigée au chapitre 23.
    var retryableLines: [TopUpLineResult] {
        results.filter { $0.status.isSafeToRetryLine }
    }
}

private extension PaymentStatus {
    /// Une ligne ne se relance que sur un échec **franc**. Ni `unknown`, ni un
    /// état en vol : les deux pourraient avoir abouti.
    var isSafeToRetryLine: Bool {
        self == .failed || self == .expired || self == .cancelled
    }
}
