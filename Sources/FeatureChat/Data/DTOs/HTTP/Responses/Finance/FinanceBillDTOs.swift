//
//  FinanceBillDTOs.swift
//  FeatureChat
//
//  Phase 5.1 — Pay Bill : catalogue, schéma, inquiry (§5.1).
//

import Foundation

/// Un facturier du catalogue — `GET /pay-bill/catalogue` (§5.1). Forme lue sur
/// la réponse réelle du backend (22/09) : une liste plate, la catégorie portée
/// par chaque facturier.
struct BillerCatalogueEntryDTO: Decodable, Equatable, Sendable {
    let billerId: String
    let officialName: String?
    let category: String?
    let country: String?
    let verified: Bool?
    let brandingRef: String?
    let status: String?
}

/// Formulaire d'un facturier — `GET /pay-bill/schema?billerId=` (§5.1). Forme
/// lue sur la réponse réelle du backend (22/09).
struct BillerSchemaDTO: Decodable, Equatable, Sendable {
    let billerId: String
    let schemaVersion: String?
    /// Version du **parcours**, distincte de celle du formulaire : un facturier
    /// peut redécouper ses étapes sans changer ses champs.
    let workflowVersion: String?
    /// Étapes déclarées par le facturier. Absentes ⇒ formulaire d'un tenant.
    let steps: [BillerSchemaStepDTO]?
    let fields: [BillerSchemaFieldDTO]?
}

/// Une étape du formulaire — `steps[]`. Le titre et la description sont
/// **rédigés par le serveur** et affichés tels quels.
struct BillerSchemaStepDTO: Decodable, Equatable, Sendable {
    let id: Int
    let title: String?
    let description: String?
}

struct BillerSchemaFieldDTO: Decodable, Equatable, Sendable {
    let name: String
    /// `STRING`, `ENUM`, …
    let type: String?
    /// Nature du champ (`ACCOUNT_REF`, `MSISDN`, `METER`, …) : c'est elle qui
    /// nomme le champ à l'écran, pas la clé technique.
    let semanticType: String?
    let required: Bool?
    let minLength: Int?
    let maxLength: Int?
    let pattern: String?
    /// Ordre d'affichage voulu par le facturier.
    let order: Int?
    /// Étape du formulaire (`steps`), quand le facturier en découpe un.
    let step: Int?
    /// `ALWAYS`, ou une condition que cette version ne sait pas évaluer.
    let visibility: String?
    /// Valeurs admises d'un `ENUM`.
    let allowedValues: [String]?
}

/// Facture lue au Biller Hub — `POST /pay-bill/inquiry` (§5.1). Forme lue sur
/// la réponse réelle du backend (22/09). Masquée : ni référence ni nom en clair.
struct BillInquiryDTO: Decodable, Equatable, Sendable {
    let inquiryRef: String
    let billerId: String?
    let accountRefMasked: String?
    let dueAmountMinor: Int64?
    let currency: String?
    let customerNameMasked: String?
    let snapshotId: String?
}

/// `POST /pay-bill/split` → `PayBillSplitResult` (§5.1.2). `valid` : la somme
/// des parts égale exactement le total, chaque part ≥ 0 (`CF_041` sinon).
struct PayBillSplitResultDTO: Decodable, Equatable, Sendable {
    let totalMinor: Int64?
    let parts: [Int64]?
    let valid: Bool?
}

/// `POST /pay-bill/requery` → `BillOverlay` (§5.1.0) — où en est une facture.
///
/// Même découpage que `TopUpOverlayDTO` : `paymentStatus` dit le débit,
/// `fulfillmentStatus` et `deliveryStatus` disent si le facturier a pris le
/// paiement en compte. Payée mais non créditée chez le facturier, c'est le
/// `BILLER_NOT_UPDATED` des litiges — pas un succès.
struct BillOverlayDTO: Decodable, Equatable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let billerId: String?
    let billerName: String?
    let verifiedInstitution: Bool?
    let inquiryRef: String?
    let inquiryMasked: String?
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
    let schemaVersion: String?
}
