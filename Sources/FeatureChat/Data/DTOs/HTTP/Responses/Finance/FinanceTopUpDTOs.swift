//
//  FinanceTopUpDTOs.swift
//  FeatureChat
//
//  Phase 5.3 — recharge : catalogue, résolution du numéro, requery (§5.3.1).
//
//  Une frontière portée par les champs eux-mêmes : `operatorHint` est une
//  **indication**, et `authoritative` dit qu'elle n'est pas la vérité de
//  portabilité. Recharger le mauvais opérateur est une perte sèche.
//

import Foundation

/// Un produit du catalogue — `GET /top-up/catalogue?country=` (§5.3.1).
struct TopUpProductDTO: Decodable, Equatable, Sendable {
    let code: String
    let label: String?
    /// `AIRTIME`, `DATA`, … Inconnu ⇒ le produit n'est pas proposé.
    let kind: String?
    let country: String?
    let amountMinor: Int64?
    let currency: String?
    let billerId: String?
    let status: String?
}

/// `POST /top-up/resolve-msisdn` (§5.3.1) — le numéro normalisé par le serveur.
///
/// `operatorHint` n'est qu'un indice : `authoritative: false` et
/// `portabilityWarning` le disent dans la réponse même. Le préfixe ne décide
/// donc pas de l'opérateur, et aucune déduction locale ne le remplace.
struct ResolvedMsisdnDTO: Decodable, Equatable, Sendable {
    let msisdnNormalized: String?
    let msisdnMasked: String?
    let operatorHint: String?
    let authoritative: Bool?
    let portabilityWarning: String?
}

/// `POST /top-up/bulk` → `BulkResult` (§5.3.1) — **un `QuotedPrepareResponse`
/// par ligne**, et un identifiant de lot.
///
/// Le lot ne porte pas de statut : « chaque ligne = son propre FCO +
/// confirmation (pas un seul execute pour le lot) ». Un statut de lot serait
/// une seconde vérité à côté de celle des lignes, et les deux se
/// contrediraient dès qu'une ligne échoue seule.
struct TopUpBulkResultDTO: Decodable, Equatable, Sendable {
    let bulkId: String?
    let lines: [QuotedPrepareResponseDTO]?
}

/// `POST /top-up/requery` → `TopUpOverlay` (§5.3.1) — où en est une recharge.
///
/// Sept statuts distincts, et pas un seul « terminé » : `paymentStatus` dit le
/// débit, `fulfillmentStatus` et `deliveryStatus` disent la livraison du crédit
/// télécom. Un paiement abouti dont la recharge n'est pas livrée n'est pas un
/// succès, et les confondre est le `TOPUP_NOT_DELIVERED` des litiges.
struct TopUpOverlayDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let msisdnMasked: String?
    let msisdnHash: String?
    let productCode: String?
    let snapshotId: String?
    let snapshotHash: String?
    let inquiryStatus: String?
    let quoteStatus: String?
    let paymentStatus: String?
    let settlementStatus: String?
    let deliveryStatus: String?
    let fulfillmentStatus: String?
    let reconciliationStatus: String?
    let tokenPresent: Bool?
    /// Lot et mandat : lus, jamais fabriqués ici. Les parcours groupé et
    /// récurrent (`/bulk`, `/recurring`) ne sont pas encore ouverts.
    let bulkId: String?
    let recurringMandateRef: String?
    let bulkLineRefs: [String]?
}
