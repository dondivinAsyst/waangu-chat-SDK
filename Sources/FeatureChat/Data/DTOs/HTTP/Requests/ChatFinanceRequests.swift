//
//  ChatFinanceRequests.swift
//  FeatureChat
//
//  Corps des requêtes Chat Core Finance — INTEGRATION_CHAT_FINANCE.md.
//
//  Typés plutôt que des `[String: Any]` montés à la main : le contrat est
//  strict sur les noms de champs (`beneficiaryToken`, jamais `beneficiaryId`),
//  et une faute de frappe dans une clé de dictionnaire compile sans broncher.
//  Les optionnels absents ne partent pas — l'encodage synthétisé les omet.
//
//  `idempotencyKey` n'apparaît dans aucun de ces types : l'endpoint l'ajoute
//  au corps depuis le même `IdempotencyContext` que l'en-tête, pour que les
//  deux ne puissent jamais diverger (CF_071).
//

import Foundation

// MARK: - §1.1 Négociation client

/// `POST /client-capabilities/negotiate` (§1.1, optionnel) — ce que l'appareil
/// préfère : données réduites, mouvements réduits.
///
/// `networkQuality` n'est pas envoyé : le contrat n'en publie pas les valeurs,
/// et une valeur devinée serait lue comme un fait par le serveur.
struct NegotiateClientCapabilitiesRequest: Encodable, Sendable {
    let platform: String
    let appVersion: String
    let lowData: Bool?
    let reducedMotionPreferred: Bool?
}

// MARK: - §2.2 / §2.3 Hub

/// `POST /hub/intent/parse` — le texte tel que saisi.
struct ParseIntentRequest: Encodable, Sendable {
    let text: String
}

/// `POST /hub/handoff` — l'action ouverte depuis une conversation.
struct IssueHandoffRequest: Encodable, Sendable {
    let conversationId: String
    let actionCode: String
    let financialIntentRef: String?
}

/// `POST /hub/handoff/consume` — le jeton, une seule fois.
struct ConsumeHandoffRequest: Encodable, Sendable {
    let token: String
}

// MARK: - §3.2 Devis expiré

/// `POST /send-money/quote/refresh` — `RefreshQuoteBody`. Rend un
/// `PrepareSendMoneyResponse` : nouveau devis, nouvelle empreinte, même FCO.
struct RefreshQuoteRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let deviceId: String
}

// MARK: - §5.2 Facture marchande

/// `POST /invoice/inquire` — `InvoiceInquireBody`. `merchantId` facultatif :
/// le Merchant Backend le complète ; le client ne l'invente pas.
struct InvoiceInquireRequest: Encodable, Sendable {
    let invoiceRef: String
    let merchantId: String?
}

// MARK: - Phase 8 — Waangu Copilot

/// `POST /hub/copilot-tools/invoke` — `CopilotToolBody`.
struct InvokeCopilotToolRequest: Encodable, Sendable {
    let name: String
}

// MARK: - Phase 8 — traduction

/// `POST /hub/translation/mask` — `MaskBody`.
struct MaskTextRequest: Encodable, Sendable {
    let text: String
}

/// `POST /hub/translation/translate` — `TranslateBody`. Rend la traduction du
/// texte **masqué par le serveur** : ses jetons y restent, à rétablir.
struct TranslateTextRequest: Encodable, Sendable {
    let text: String
    let sourceLang: String
    let targetLang: String
}

// MARK: - Phase 10 — reçus, litiges

/// `POST /receipts/issue` — `ReceiptBody`. `documentBody` facultatif : sans
/// lui, le serveur compose le texte canonique du reçu.
/// `POST /receipts/verify` — `VerifyReceiptBody`.
struct VerifyReceiptRequest: Encodable, Sendable {
    let receiptRef: String
    /// Les mêmes octets que ceux émis.
    let documentBody: String
}

/// `POST /receipt/share` — `ReceiptShareRequest` : la carte publiée dans la conversation.
struct ReceiptCardShareRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String
    let receiptRef: String
}

struct IssueReceiptRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let documentBody: String?
}

/// `POST /disputes` — `OpenDisputeBody`. `category` vient de la taxonomie
/// serveur (`GET /disputes/taxonomy`), jamais inventée (`CF_048`).
struct OpenDisputeRequest: Encodable, Sendable {
    let conversationId: String?
    let financialIntentRef: String
    let category: String
    let priority: String?
}

/// `POST /disputes/{id}/evidence` — `EvidenceBody`, en JSON (pas multipart).
struct DisputeEvidenceRequest: Encodable, Sendable {
    let type: String
    let content: String
    let visibility: String
}

// MARK: - §1.6 Session

/// `POST /financial/session/resume` — les quatre affirmations du §1.6.
struct ResumeSessionRequest: Encodable, Sendable {
    let deviceId: String
    let syncAcknowledged: Bool
    let iamValid: Bool
    let complianceValid: Bool
    let capabilityValid: Bool

    /// L'amorçage qui précède vient de relire experience, gouvernance et
    /// sécurité pour ce compte : les quatre affirmations sont vraies.
    static func afterBootstrap(deviceID: String) -> ResumeSessionRequest {
        ResumeSessionRequest(deviceId: deviceID, syncAcknowledged: true, iamValid: true,
                             complianceValid: true, capabilityValid: true)
    }
}

// MARK: - §3 Send Money

/// `POST /financial/send-money/resolve-beneficiary`.
struct ResolveBeneficiaryRequest: Encodable, Sendable {
    var msisdn: String?
    var walletRef: String?
    /// Indication seulement : le serveur ne résout jamais sur un nom (CF_028).
    var displayNameHint: String?
}

/// `POST /financial/send-money/prepare`.
struct PrepareSendMoneyRequest: Encodable, Sendable {
    let currency: String
    let amountMinor: Int64
    let channel: String
    let deviceId: String
    /// Le jeton rendu par la résolution — seul identifiant que le prepare accepte.
    let beneficiaryToken: String
    let conversationId: String?
    let sourceWalletRef: String?
}

/// `POST /financial/{operation}/execute` — `QuotedExecuteRequest`, commun à
/// Send Money et aux opérations quotées.
struct ExecuteIntentRequest: Encodable, Sendable {
    let financialIntentRef: String
    let confirmationId: String
    let quoteId: String
    let deviceId: String
    let conversationId: String?
    let objectVersion: String?
    let executionPermitId: String?
}

// MARK: - §9 Doute

/// `POST /financial/intent/requery`.
struct RequeryIntentRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String
}

// MARK: - §4 Request Money

/// `POST /financial/request-money`.
struct CreateMoneyRequestRequest: Encodable, Sendable {
    /// Utilisateurs **Chat** — jamais des identifiants de partie Finance.
    let recipientUserIds: [String]
    /// `FIXED` · `FREE`.
    let amountMode: String
    let currency: String
    let amountMinor: Int64?
    let conversationId: String?
    let note: String?
}

/// `POST /financial/request-money/remind`.
struct RemindMoneyRequestRequest: Encodable, Sendable {
    let requestRef: String
    let partyUserId: String
}

/// `POST /request-money/pay` — §4. Rend un `PrepareSendMoneyResponse` : un
/// devis à confirmer, jamais un débit.
///
/// **Corps non publié par le contrat.** Celui-ci suit `/remind` (`requestRef`)
/// et le prepare de Send Money (`conversationId`, `amountMinor`). `amountMinor`
/// n'est envoyé que pour une demande à montant libre (`FREE`) : pour un montant
/// fixe, c'est le serveur qui connaît la part due.
struct PayMoneyRequestRequest: Encodable, Sendable {
    let requestRef: String
    let conversationId: String?
    let amountMinor: Int64?
    let currency: String?
    /// Comme le prepare de Send Money. L'empreinte de confirmation porte sur
    /// « device + montant + quote + bénéficiaire » (§3) : sans l'appareil au
    /// prepare, l'execute — qui l'envoie — ne correspondait plus
    /// (« Confirmation fingerprint does not match context »).
    let channel: String
    let deviceId: String
}

/// `POST /financial/split-bill` — §4, « N parts, somme exacte ».
///
/// **Forme relevée sur le serveur (24/09)**, et non celle que le contrat
/// publie : §4 ne décrit que la règle (« N parts, somme exacte — CF_041 »).
/// Une première version calquée sur `/request-money` envoyait des
/// `participantUserIds`, une `strategy` et un dictionnaire de parts ; le
/// serveur attend une **liste** de parts nommées, et rien d'autre.
///
/// Conséquence à connaître : sans champ `strategy`, **le client doit fournir
/// chaque montant**. Le partage en parts égales est donc divisé ici, ce que le
/// §50 réserve au serveur. À confirmer avec le backend — voir
/// `LiveSplitBillManaging.shares(_:total:)`.
struct CreateSplitBillRequest: Encodable, Sendable {
    let conversationId: String?
    /// Nom donné au partage par l'organisateur. Le partage en porte un au §50 ;
    /// sans lui, il n'a de nom nulle part.
    let label: String
    let currency: String
    let totalMinor: Int64
    /// `EQUAL` · `CUSTOM` · `PROPORTIONAL`.
    ///
    /// Renvoyée bien que la route accepte déjà des montants : c'est le seul
    /// champ qui permette au serveur de **recalculer** la répartition, comme le
    /// §50 le lui confie. Sans elle, l'arrondi d'un total indivisible reste une
    /// décision prise sur le téléphone.
    let strategy: String
    /// Qui voit quoi (§50). L'écran pose la question ; la réponse doit arriver.
    let privacyScope: String
    /// Une entrée par participant. Leur somme **doit** faire `totalMinor`.
    let shares: [SplitShareRequest]
}

/// La part d'un participant — `{ userId, amountMinor }`.
struct SplitShareRequest: Encodable, Sendable, Equatable {
    /// Utilisateur **Chat**, comme `recipientUserIds` de `/request-money`.
    let userId: String
    let amountMinor: Int64
}

/// `POST /financial/split-bill/pay` — §4.
///
/// **Une part, un consentement** : la requête ne porte jamais le total, et rien
/// ne permet de régler le partage entier d'un geste. La réponse est un
/// `PrepareSendMoneyResponse` — un devis à confirmer, jamais un débit.
///
/// Corps non publié : il suit `/request-money/pay`, dont il partage la réponse.
struct PaySplitShareRequest: Encodable, Sendable {
    let splitRef: String
    let conversationId: String?
    /// La part de ce participant. Absent : le serveur connaît le montant dû.
    let amountMinor: Int64?
    let currency: String?
    let channel: String
    let deviceId: String
}

/// `POST /cash-in/verify-agent` — `AgentBody` (§6, DTOs).
struct CashAgentRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    let agentId: String
}

/// `POST /cash-in/confirm-physical` — `RefBody` (§6, DTOs).
///
/// Déclare que l'agent a **reçu les espèces**. Ne crédite rien : le serveur
/// peut laisser `creditState` à `PENDING`, et l'écran doit le dire (`CF_038`).
struct CashRefRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
}

/// `POST /cash-out/token/consume` — `TokenBody` (§6, DTOs).
struct CashTokenRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    /// Le code présenté par le porteur. **Jamais journalisé.**
    let token: String
    let agentId: String
}

/// `POST /intent/cancel` — Phase 10. Répond à `CANCEL_INTENT` de `nextSafeActions`.
///
/// Corps non publié par le contrat : il suit `/intent/requery`
/// (`financialIntentRef`, `conversationId`). Une demande est aussi un objet FCO
/// (`intentType: PAYMENT_REQUEST`) sous la même référence.
struct CancelIntentRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
    /// `CancelBody.reason` de `/intent/cancel-request`. Absent sur `/intent/cancel`.
    var reason: String? = nil
}

/// `POST /request-money/decline` — §4. Corps non publié : `requestRef`, comme `/remind`.
struct DeclineMoneyRequestRequest: Encodable, Sendable {
    let requestRef: String
    let conversationId: String?
}

/// `POST /request-money/payment-link` — Phase 4. Corps non publié : la demande que le lien
/// désigne, comme `/decline` et `/remind`. Clé d'idempotence en plus (création).
struct IssuePaymentLinkRequest: Encodable, Sendable {
    let requestRef: String
    let conversationId: String?
}

/// `POST /request-money/payment-link/inspect` — Phase 4 : `{ "token", "nonce" }`.
struct InspectPaymentLinkRequest: Encodable, Sendable {
    let token: String
    let nonce: String
}

/// `POST /pay-bill/inquiry` — §5.1. Corps non publié : le facturier, la
/// version du formulaire et les champs saisis, sous les noms du schéma.
struct BillInquiryRequest: Encodable, Sendable {
    let billerId: String
    let schemaVersion: String?
    let fields: [String: String]
    let conversationId: String?
}

/// `POST /qr/parse` — §5.2. La charge brute et un nonce à usage unique : un
/// rejeu devient un refus explicite (`CF_043`), jamais un second débit.
struct ParseQRRequest: Encodable, Sendable {
    let payload: String
    let nonce: String
}

/// `POST /top-up/resolve-msisdn` — `MsisdnBody` (§5.3.1). Le numéro tel que
/// saisi : c'est le serveur qui le normalise et nomme l'opérateur.
struct TopUpMsisdnRequest: Encodable, Sendable {
    let msisdn: String
}

/// `POST /top-up/bulk` — `BulkBody` (§5.3.1).
///
/// **Un seul produit pour toutes les lignes** : c'est la forme que le contrat
/// publie. Recharger deux numéros de forfaits différents est donc deux lots,
/// pas un lot panaché.
struct TopUpBulkRequest: Encodable, Sendable {
    let conversationId: String?
    let productCode: String
    let msisdns: [String]
    let deviceId: String
}

/// `POST /pay-bill/split` — `SplitBody` (§5.1.2). **Une calculette** : ni
/// intent, ni facturier, ni paiement. Le serveur dit si les parts font le total.
struct PayBillSplitRequest: Encodable, Sendable {
    let totalMinor: Int64
    let parts: [Int64]
}

/// `POST /top-up/requery` et `POST /pay-bill/requery` — `RefBody` (§5.3.1, §5.1.0).
///
/// Le seul moyen de savoir où en est une recharge ou une facture : le client
/// ne voit ni le débit se régler, ni le fournisseur livrer.
struct TopUpRefRequest: Encodable, Sendable {
    let financialIntentRef: String
    let conversationId: String?
}
