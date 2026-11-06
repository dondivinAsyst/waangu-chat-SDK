//
//  ChatFinanceEndpoints.swift
//  FeatureChat
//
//  /chat-core → /v1 — WAANGU Chat Core Finance, served by the chat host (`chatUrl`).
//  INTEGRATION_CHAT_FINANCE.md §0.5.
//

import Foundation
import WaanguCoreKit
import WaanguNetworkKit

/// Opérations qui suivent la machine de Send Money : prepare → confirmation
/// humaine → execute (§5, « Pattern commun »). Une route par segment.
enum QuotedOperation: String, CaseIterable, Sendable {
    case sendMoney, payBill, qr, invoice, topUp, cashIn, cashOut
    /// `POST /refund` — **pas de `/prepare`** ; l'execute passe par Send Money.
    case refund

    var prepareRoute: String { self == .refund ? "/financial/refund" : "/financial/\(segment)/prepare" }

    /// Nature de l'objet que ce prepare crée — celle qui part sur le fil et
    /// choisit la carte du destinataire. Était `PAYMENT` pour toutes : une
    /// facture ou un retrait s'affichait comme un paiement reçu.
    ///
    /// `topUp` : `AIRTIME` par défaut. Le prepare ne dit pas encore s'il s'agit
    /// d'un forfait data ; le jour où il le dira, `DATA_BUNDLE` se choisira ici.
    /// `qr` : `PAYMENT` — rien ne dit encore si le QR est celui d'un marchand.
    var objectType: FinancialObjectType {
        switch self {
        case .sendMoney, .qr: return .payment
        case .payBill:        return .bill
        case .invoice:        return .merchantPayment
        case .topUp:          return .airtime
        case .cashIn:         return .cashIn
        case .cashOut:        return .cashOut
        case .refund:         return .refund
        }
    }
    /// Un remboursement s'exécute comme un envoi (`intentType` `WALLET_TRANSFER`) :
    /// il n'y a pas de `/refund/execute` (§10).
    var executeRoute: String { self == .refund ? "/financial/send-money/execute" : "/financial/\(segment)/execute" }

    private var segment: String {
        switch self {
        case .sendMoney: return "send-money"
        case .payBill:   return "pay-bill"
        case .qr:        return "qr"
        case .invoice:   return "invoice"
        case .topUp:     return "top-up"
        case .cashIn:    return "cash-in"
        case .cashOut:   return "cash-out"
        case .refund:    return "refund"
        }
    }
}

enum ChatFinanceEndpoints {

    // §1.1 — amorçage, dans l'ordre du contrat
    case experienceConfig
    case governanceCapabilities
    case securityCapabilities
    case sessionResumeState
    case resumeSession(ResumeSessionRequest)
    case hubActions(conversationType: String)
    /// §12 — capacité périmée (`CF_006` / `CF_012`). Sans corps : tout est relu.
    case refreshCapability
    /// §1.1, optionnel — préférences d'affichage de l'appareil. Réponse non publiée.
    case negotiateClientCapabilities(NegotiateClientCapabilitiesRequest)

    // §2.2 / §2.3 — Hub
    /// Un texte lu comme **brouillon**. Jamais une commande (`CF_027`).
    case parseIntent(ParseIntentRequest)
    /// Jeton à usage unique pour ouvrir un parcours depuis une conversation.
    case issueHandoff(IssueHandoffRequest)
    /// Rend le contexte du jeton une fois, puis le détruit (`CF_025` ensuite).
    case consumeHandoff(ConsumeHandoffRequest)

    // §5.1.1 — le dossier personnel, quand il n'y a pas de conversation
    case selfConversation

    // Phase 4 — lien de paiement d'une demande
    /// Création sous clé : `Idempotency-Key` obligatoire sur create (§0.5).
    case issuePaymentLink(IssuePaymentLinkRequest, IdempotencyContext)
    /// Contexte seulement — le paiement passe ensuite par `/request-money/pay`.
    case inspectPaymentLink(InspectPaymentLinkRequest)

    // §5.1 — Payer une facture
    /// `country` : le pays rendu par `/experience/config` (celui du JWT),
    /// jamais choisi par l'app. `nil` ⇒ paramètre absent.
    case billCatalogue(country: String?)
    /// Formulaire d'un facturier. Forme de la réponse pas encore publiée.
    case billSchema(billerID: String)
    /// Le montant dû, lu au Biller Hub. Forme de la réponse pas encore publiée.
    case billInquiry(BillInquiryRequest)
    /// Où en est la facture — paiement **et** prise en compte par le facturier.
    /// `/pay-bill/delivery` n'existe pas ici : le serveur le refuse (`CF_054`).
    case billRequery(TopUpRefRequest)
    /// Vérifie qu'une répartition fait le total. Calcul seulement — ne crée
    /// ni partage ni paiement (§5.1.2).
    case billSplitCheck(PayBillSplitRequest)

    // §5.2 — QR
    /// Lire un QR. **Jamais un execute.** Forme de la réponse pas encore publiée.
    case parseQR(ParseQRRequest)

    // §5.2 — facture marchande : le reste dû, lu au Merchant Backend.
    case inquireInvoice(InvoiceInquireRequest)

    // §5.3 — Recharge
    /// `country` : celui de `/experience/config`, jamais choisi par l'app.
    case topUpCatalogue(country: String?)
    /// Le serveur normalise le numéro et **nomme l'opérateur** : un préfixe
    /// deviné ici devient faux dès qu'un numéro est porté (`CF_044`).
    case resolveMsisdn(TopUpMsisdnRequest)
    /// Où en est la recharge — paiement **et** livraison, distincts.
    case topUpRequery(TopUpRefRequest)
    /// Plusieurs numéros, **un FCO par ligne**. Écriture sous clé.
    case topUpBulk(TopUpBulkRequest, IdempotencyContext)
    // `/top-up/delivery` n'existe pas ici : le serveur le refuse (`CF_054`).

    // §3 — Send Money et opérations quotées
    case resolveBeneficiary(ResolveBeneficiaryRequest)
    case prepareSendMoney(PrepareSendMoneyRequest, IdempotencyContext)
    /// Devis expiré avant confirmation (`CF_029`) : nouveau devis sur le même
    /// FCO. **Invalide l'ancienne empreinte** — jamais appelé sur un devis valide.
    case refreshSendMoneyQuote(RefreshQuoteRequest)
    /// Le corps de prepare des opérations quotées **n'est pas publié** par le
    /// contrat : l'appelant le fournit tel quel, une fois connu.
    case prepareQuoted(QuotedOperation, body: [String: Any], IdempotencyContext)
    /// **Jamais rejoué** — en cas de doute, `requery` (§0.3.3).
    case execute(QuotedOperation, ExecuteIntentRequest, CorrelationId)

    // §2 / §9 — carte FCO et doute
    case financialObject(ref: String)
    case requery(RequeryIntentRequest, CorrelationId)

    // §4 — Request Money
    case createMoneyRequest(CreateMoneyRequestRequest, IdempotencyContext)
    case moneyRequest(ref: String)
    case remindMoneyRequest(RemindMoneyRequestRequest, CorrelationId)
    /// Ouvre un Send Money : rend un devis, jamais un débit.
    case payMoneyRequest(PayMoneyRequestRequest, IdempotencyContext)
    case declineMoneyRequest(DeclineMoneyRequestRequest, CorrelationId)

    // §4 — partage d'addition. Trois routes, et pas une de plus : le contrat
    // ne publie ni liste, ni réponse de participant, ni relance pour un partage.
    case createSplitBill(CreateSplitBillRequest, IdempotencyContext)
    case splitBill(ref: String)
    /// Rend un `PrepareSendMoneyResponse` — un devis, jamais un débit.
    case paySplitShare(PaySplitShareRequest, IdempotencyContext)

    // §6 — Cash-in / Cash-out : les canaux ouverts sur ce marché.
    //
    // Liste **vide** = aucun canal ici (le Canada, aujourd'hui). Ce n'est pas
    // une panne, et surtout pas un `if pays` à écrire côté client : le contrat
    // dit « vider l'UI si le GET est `[]` ».
    case cashInChannels
    case cashOutChannels
    /// L'agent est-il celui qu'il dit ? `CF_037` sinon.
    case verifyAgent(CashAgentRequest)
    /// L'agent a reçu les espèces — **pas** un crédit (`CF_038`).
    case confirmPhysical(CashRefRequest)
    /// Jeton de retrait **émis par Finance** — `CF_051` si non câblé.
    case issueCashOutToken(CashAgentRequest)
    /// Code présenté — **pas** une finalité financière.
    case consumeCashOutToken(CashTokenRequest)
    case revokeCashOutToken(CashRefRequest)
    /// Espèces remises — **n'écrit pas le ledger**.
    case confirmRemittance(CashRefRequest)
    /// Écart constaté — **n'écrit pas le ledger**.
    case cashOutIncident(CashRefRequest)

    // Phase 10 — annulation
    case cancelIntent(CancelIntentRequest, CorrelationId)
    /// Annulation **demandée** d'un objet peut-être déjà soumis — `CF_046` sinon.
    case cancelRequest(CancelIntentRequest, CorrelationId)
    /// `POST /reversal/request` — Finance exécute ; Chat journalise seulement.
    case requestReversal(CancelIntentRequest, CorrelationId)

    // Phase 8 — Waangu Copilot : outils publiés par le Hub, invoqués par leur nom.
    case copilotTools
    case invokeCopilotTool(InvokeCopilotToolRequest)

    // Phase 8 — traduction : le serveur masque, traduit, et refuse fermé
    // (`CF_063`) tant que le moteur n'est pas branché.
    case maskText(MaskTextRequest)
    case translateText(TranslateTextRequest)

    // Phase 10 — reçus : émis puis partagés par Finance (URL signée).
    case issueReceipt(IssueReceiptRequest)
    case shareReceipt(TopUpRefRequest)
    /// `POST /receipts/verify` — le document est-il celui que Finance a signé (`CF_045`).
    case verifyReceipt(VerifyReceiptRequest)
    /// `POST /receipt/share` — la carte du reçu, publiée dans la conversation.
    case postReceiptCard(ReceiptCardShareRequest)

    // Phase 10 — litiges, côté client : ouvrir, verser une note.
    case disputeTaxonomy
    /// `GET /disputes/{id}` — le dossier (`DisputeCase`), lu par son propriétaire.
    case dispute(id: String)
    /// `GET /disputes/{id}/timeline` — les étapes de l'opération contestée.
    case disputeTimeline(id: String)
    case openDispute(OpenDisputeRequest)
    case addDisputeEvidence(disputeID: String, DisputeEvidenceRequest)

    /// Préfixe des routes Chat Core.
    ///
    /// La passerelle réécrit `/chat-core/…` en `/v1/…`, et **les routes
    /// financières de ce serveur vivent sous `/v1/financial/…`**, sans `chat` :
    /// `/chat-core/chat/financial/session/resume` répond « No static resource
    /// v1/chat/financial/session/resume » (HTTP 500), alors que
    /// `/chat-core/financial/session/resume` répond 200. Seuls experience,
    /// governance et security existent sous les deux orthographes.
    ///
    /// Le contrat, lui, publie `/v1/chat/financial/…` : c'est le serveur qui
    /// diverge du document, pas l'inverse. À corriger côté serveur ou ici, mais
    /// pas en devinant — ce préfixe suit ce que le serveur sert aujourd'hui.
    static let basePath = "chat-core"
    /// Version de contrat de gouvernance annoncée au serveur (logs, pas autorisation).
    static let contractVersion = "1.4.0"
}

// MARK: - APIEndpoint

extension ChatFinanceEndpoints: APIEndpoint {

    /// `APIClient` concatène `baseURL + path` sans séparateur, et `chatUrl` ne
    /// finit pas par `/` : le chemin doit donc commencer par `/`, comme toutes
    /// les routes de l'app. Sans lui, `…:8000` + `chat-core/…` donne un port
    /// `8000chat-core` — URL invalide, et toute la finance injoignable.
    var path: String {
        "/" + Self.basePath + route
    }

    private var route: String {
        switch self {
        case .experienceConfig:             return "/experience/config"
        case .governanceCapabilities:       return "/governance/capabilities"
        case .securityCapabilities:         return "/security/capabilities"
        case .sessionResumeState,
             .resumeSession:                return "/financial/session/resume"
        case .hubActions:                   return "/financial/hub/actions"
        case .refreshCapability:            return "/financial/capability/refresh"
        // Rangé avec experience, hors `/financial` : c'est une route de session.
        case .negotiateClientCapabilities:  return "/client-capabilities/negotiate"
        case .parseIntent:                  return "/financial/hub/intent/parse"
        case .issueHandoff:                 return "/financial/hub/handoff"
        case .consumeHandoff:               return "/financial/hub/handoff/consume"
        case .selfConversation:             return "/financial/self-conversation"
        case .billCatalogue:                return "/financial/pay-bill/catalogue"
        case .billSchema:                   return "/financial/pay-bill/schema"
        case .billInquiry:                  return "/financial/pay-bill/inquiry"
        case .billRequery:                  return "/financial/pay-bill/requery"
        case .billSplitCheck:               return "/financial/pay-bill/split"
        case .parseQR:                      return "/financial/qr/parse"
        case .inquireInvoice:               return "/financial/invoice/inquire"
        case .topUpCatalogue:               return "/financial/top-up/catalogue"
        case .resolveMsisdn:                return "/financial/top-up/resolve-msisdn"
        case .topUpRequery:                 return "/financial/top-up/requery"
        case .topUpBulk:                    return "/financial/top-up/bulk"
        case .resolveBeneficiary:           return "/financial/send-money/resolve-beneficiary"
        case .prepareSendMoney:             return QuotedOperation.sendMoney.prepareRoute
        case .refreshSendMoneyQuote:        return "/financial/send-money/quote/refresh"
        case .prepareQuoted(let operation, _, _): return operation.prepareRoute
        case .execute(let operation, _, _): return operation.executeRoute
        case .financialObject(let ref):     return "/financial/objects/\(Self.encoded(ref))"
        case .requery:                      return "/financial/intent/requery"
        case .createMoneyRequest:           return "/financial/request-money"
        case .moneyRequest(let ref):        return "/financial/request-money/\(Self.encoded(ref))"
        case .remindMoneyRequest:           return "/financial/request-money/remind"
        case .payMoneyRequest:              return "/financial/request-money/pay"
        case .declineMoneyRequest:          return "/financial/request-money/decline"
        case .cancelIntent:                 return "/financial/intent/cancel"
        case .cancelRequest:                return "/financial/intent/cancel-request"
        case .requestReversal:              return "/financial/reversal/request"
        case .copilotTools:                 return "/financial/hub/copilot-tools"
        case .invokeCopilotTool:            return "/financial/hub/copilot-tools/invoke"
        case .maskText:                     return "/financial/hub/translation/mask"
        case .translateText:                return "/financial/hub/translation/translate"
        case .issueReceipt:                 return "/financial/receipts/issue"
        case .shareReceipt:                 return "/financial/receipts/share"
        case .verifyReceipt:                return "/financial/receipts/verify"
        case .postReceiptCard:              return "/financial/receipt/share"
        case .disputeTaxonomy:              return "/financial/disputes/taxonomy"
        case .dispute(let id):              return "/financial/disputes/\(Self.encoded(id))"
        case .disputeTimeline(let id):      return "/financial/disputes/\(Self.encoded(id))/timeline"
        case .openDispute:                  return "/financial/disputes"
        case .addDisputeEvidence(let id, _): return "/financial/disputes/\(Self.encoded(id))/evidence"
        case .cashInChannels:               return "/financial/cash-in/channels"
        case .cashOutChannels:              return "/financial/cash-out/channels"
        case .verifyAgent:                  return "/financial/cash-in/verify-agent"
        case .confirmPhysical:              return "/financial/cash-in/confirm-physical"
        case .issueCashOutToken:            return "/financial/cash-out/token"
        case .consumeCashOutToken:          return "/financial/cash-out/token/consume"
        case .revokeCashOutToken:           return "/financial/cash-out/token/revoke"
        case .confirmRemittance:            return "/financial/cash-out/confirm-remittance"
        case .cashOutIncident:              return "/financial/cash-out/incident"
        case .createSplitBill:              return "/financial/split-bill"
        case .splitBill(let ref):           return "/financial/split-bill/\(Self.encoded(ref))"
        case .paySplitShare:                return "/financial/split-bill/pay"
        // Phase 4 : « Base : /v1/chat/financial/request-money » — le lien en fait partie.
        case .issuePaymentLink:             return "/financial/request-money/payment-link"
        case .inspectPaymentLink:           return "/financial/request-money/payment-link/inspect"
        }
    }

    var method: HTTPMethod {
        switch self {
        case .experienceConfig, .governanceCapabilities, .securityCapabilities,
             .sessionResumeState, .hubActions, .financialObject, .moneyRequest,
             .billCatalogue, .billSchema, .selfConversation, .splitBill,
             .cashInChannels, .cashOutChannels, .topUpCatalogue, .disputeTaxonomy, .dispute,
             .disputeTimeline, .copilotTools:
            return .get
        case .resumeSession, .refreshCapability, .negotiateClientCapabilities, .parseIntent, .issueHandoff,
             .consumeHandoff, .resolveBeneficiary, .prepareSendMoney, .refreshSendMoneyQuote, .prepareQuoted,
             .execute, .requery, .createMoneyRequest, .remindMoneyRequest,
             .payMoneyRequest, .declineMoneyRequest, .cancelIntent, .cancelRequest, .requestReversal,
             .issuePaymentLink, .inspectPaymentLink, .billInquiry, .billRequery, .billSplitCheck, .parseQR,
             .createSplitBill, .paySplitShare, .verifyAgent, .confirmPhysical,
             .issueCashOutToken, .consumeCashOutToken, .revokeCashOutToken,
             .confirmRemittance, .cashOutIncident,
             .resolveMsisdn, .topUpRequery, .topUpBulk,
             .issueReceipt, .shareReceipt, .verifyReceipt, .postReceiptCard, .openDispute, .addDisputeEvidence,
             .maskText, .translateText, .inquireInvoice, .invokeCopilotTool:
            return .post
        }
    }

    var parameters: [String: Any]? {
        switch self {
        case .experienceConfig, .governanceCapabilities, .securityCapabilities,
             .sessionResumeState, .moneyRequest, .selfConversation, .splitBill,
             .cashInChannels, .cashOutChannels, .disputeTaxonomy, .dispute, .disputeTimeline,
             .refreshCapability, .copilotTools:
            return nil
        case .hubActions(let conversationType):
            return ["conversationType": conversationType]
        case .billCatalogue(let country), .topUpCatalogue(let country):
            return country.map { ["country": $0] }
        case .billSchema(let billerID):
            return ["billerId": billerID]
        case .financialObject:
            return ["reasonForAccess": "SELF"]
        case .resumeSession(let request):
            return try? request.toDictionary()
        case .negotiateClientCapabilities(let request):
            return try? request.toDictionary()
        case .parseIntent(let request):
            return try? request.toDictionary()
        case .issueHandoff(let request):
            return try? request.toDictionary()
        case .consumeHandoff(let request):
            return try? request.toDictionary()
        case .resolveBeneficiary(let request):
            return try? request.toDictionary()
        case .refreshSendMoneyQuote(let request):
            return try? request.toDictionary()
        case .execute(_, let request, _):
            return try? request.toDictionary()
        case .requery(let request, _):
            return try? request.toDictionary()
        case .remindMoneyRequest(let request, _):
            return try? request.toDictionary()
        case .declineMoneyRequest(let request, _):
            return try? request.toDictionary()
        case .cancelIntent(let request, _), .cancelRequest(let request, _), .requestReversal(let request, _):
            return try? request.toDictionary()
        case .maskText(let request):
            return try? request.toDictionary()
        case .inquireInvoice(let request):
            return try? request.toDictionary()
        case .invokeCopilotTool(let request):
            return try? request.toDictionary()
        case .translateText(let request):
            return try? request.toDictionary()
        case .issueReceipt(let request):
            return try? request.toDictionary()
        case .shareReceipt(let request):
            return try? request.toDictionary()
        case .verifyReceipt(let request):
            return try? request.toDictionary()
        case .postReceiptCard(let request):
            return try? request.toDictionary()
        case .openDispute(let request):
            return try? request.toDictionary()
        case .addDisputeEvidence(_, let request):
            return try? request.toDictionary()
        case .inspectPaymentLink(let request):
            return try? request.toDictionary()
        case .billInquiry(let request):
            return try? request.toDictionary()
        case .billSplitCheck(let request):
            return try? request.toDictionary()
        case .verifyAgent(let request):
            return try? request.toDictionary()
        case .confirmPhysical(let request):
            return try? request.toDictionary()
        case .issueCashOutToken(let request):
            return try? request.toDictionary()
        case .consumeCashOutToken(let request):
            return try? request.toDictionary()
        case .revokeCashOutToken(let request), .confirmRemittance(let request),
             .cashOutIncident(let request):
            return try? request.toDictionary()
        case .parseQR(let request):
            return try? request.toDictionary()
        case .resolveMsisdn(let request):
            return try? request.toDictionary()
        case .topUpRequery(let request), .billRequery(let request):
            return try? request.toDictionary()
        case .topUpBulk(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .issuePaymentLink(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .payMoneyRequest(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .prepareSendMoney(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .createMoneyRequest(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .createSplitBill(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .paySplitShare(let request, let idempotency):
            return Self.keyed((try? request.toDictionary()) ?? [:], idempotency)
        case .prepareQuoted(_, let body, let idempotency):
            return Self.keyed(body, idempotency)
        }
    }

    /// `Authorization` est posé par le middleware d'authentification du client
    /// HTTP, comme pour toutes les routes du chat. `X-Country` n'est jamais
    /// envoyé : le pays du JWT fait foi.
    ///
    /// `Accept-Language` porte la langue choisie dans l'app : Chat Core rédige
    /// ses messages d'erreur, affichés tels quels, dans cette langue. Le reste
    /// de l'app garde `en` — voir `AuthMiddleware`.
    var headers: [String: String]? {
        var headers = [
            "Accept-Language": CurrentSessionInfo.shared.languageCode,
            "accept": "application/json",
            "Content-Type": "application/json",
            "x-chat-session": CurrentSessionInfo.shared.sessionId,
            "X-Correlation-Id": correlationID.value,
            "X-Channel": "MOBILE",
            "X-Contract-Version": Self.contractVersion,
        ]
        if let idempotency { headers["Idempotency-Key"] = idempotency.key }
        if let membershipEpoch { headers["X-Membership-Epoch"] = membershipEpoch }
        return headers
    }

    // MARK: - Helpers

    /// L'époque d'appartenance de la conversation que porte cette écriture.
    ///
    /// Elle se déduit du corps : toute mutation financière nomme sa
    /// conversation, et c'est celle-là dont l'époque compte. La poser ici, une
    /// fois, évite de la faire traverser chaque appelant jusqu'à l'en-tête —
    /// et d'en oublier un, ce que le serveur sanctionnerait par `CF_074`.
    ///
    /// Inconnue ⇒ pas d'en-tête : voir `FinanceMembershipEpochs`.
    private var membershipEpoch: String? {
        guard method == .post,
              let conversationID = parameters?["conversationId"] as? String,
              let epoch = FinanceMembershipEpochs.shared.epoch(for: conversationID)
        else { return nil }
        return String(epoch)
    }

    /// Écriture sous clé : la clé part deux fois, dans l'en-tête et dans le
    /// corps. Le contrat exige qu'elles soient identiques (sinon `CF_071`) ; les
    /// poser ici, depuis la même valeur, rend la divergence impossible.
    private var idempotency: IdempotencyContext? {
        switch self {
        case .prepareSendMoney(_, let context),
             .prepareQuoted(_, _, let context),
             .createMoneyRequest(_, let context),
             .payMoneyRequest(_, let context),
             .issuePaymentLink(_, let context),
             .createSplitBill(_, let context),
             .paySplitShare(_, let context),
             .topUpBulk(_, let context):
            return context
        default:
            return nil
        }
    }

    /// Les écritures portent la corrélation de l'opération ; une lecture ou une
    /// commande sans opération en reçoit une neuve.
    private var correlationID: CorrelationId {
        switch self {
        case .execute(_, _, let id), .requery(_, let id), .remindMoneyRequest(_, let id),
             .declineMoneyRequest(_, let id), .cancelIntent(_, let id), .cancelRequest(_, let id),
             .requestReversal(_, let id):
            return id
        default:
            return idempotency?.correlationID ?? CorrelationId()
        }
    }

    private static func keyed(_ body: [String: Any], _ idempotency: IdempotencyContext) -> [String: Any] {
        var body = body
        body["idempotencyKey"] = idempotency.key
        return body
    }

    private static func encoded(_ ref: String) -> String {
        ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ref
    }
}

// MARK: - Policies

extension ChatFinanceEndpoints: EndpointPolicyProviding, BusinessErrorEnvelopeEndpoint {

    /// Aucune réponse financière n'est servie depuis un cache.
    var cachePolicy: EndpointCachePolicy { .noCache }

    var circuitBreakerProfile: CircuitBreakerProfile { .standard }

    var priority: RequestPriority { .critical }

    var timeoutPolicy: EndpointTimeoutPolicy { .standard }

    var rateLimitPolicy: RateLimitPolicy { .none }

    /// Seules les lectures, les commandes et les créations sous clé se rejouent
    /// après un échec réseau. Un execute **ne se rejoue jamais** : en cas de
    /// doute, on requête l'état — contrat §0.3.3.
    var isIdempotent: Bool {
        if case .execute = self { return false }
        // Jeton à usage unique : rejouer la consommation la ferait échouer
        // (`CF_025`) alors que la première a peut-être abouti.
        if case .consumeHandoff = self { return false }
        return true
    }

    /// `true` si la requête peut déplacer de l'argent ou créer une intention :
    /// un échec ambigu après envoi n'y est plus une simple indisponibilité.
    var isMutation: Bool {
        switch self {
        case .prepareSendMoney, .prepareQuoted, .execute, .createMoneyRequest, .payMoneyRequest,
             .createSplitBill, .paySplitShare, .topUpBulk:
            return true
        default:
            return false
        }
    }
}
