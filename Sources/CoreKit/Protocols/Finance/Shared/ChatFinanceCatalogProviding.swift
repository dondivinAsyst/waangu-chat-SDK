//
//  ChatFinanceCatalogProviding.swift
//  CoreKit
//
//  Catalogue des entrées financières proposables dans une conversation.
//  Bloc 3, chapitre 16.1.1.1.1.
//
//  **BACKEND CONTRACT REQUIRED** — `GET /v1/financial/capabilities`.
//

import Foundation

/// Ce que le Chat a le droit de proposer, ici et maintenant.
///
/// Distinct de `FinanceCapabilities`, qui dit ce que l'utilisateur peut faire
/// **en général**. Celui-ci dit ce qui s'affiche **dans cette conversation-ci** :
/// une conversation marchande ne propose pas les mêmes entrées qu'un groupe, et
/// la différence appartient au backend, pas à une condition écrite dans une vue.
///
/// Le client ne filtre jamais cette liste. Filtrer localement supposerait de
/// connaître les règles de marché, de KYC et de risque — donc de les dupliquer,
/// puis de les laisser diverger.
public protocol ChatFinanceCatalogProviding: Sendable {

    /// Entrées proposables, déjà filtrées par le backend.
    ///
    /// Ne lève jamais : toute erreur donne une liste vide. L'absence de `throws`
    /// est le même choix de sûreté que `FinanceCapabilityProviding.capabilities()` —
    /// un `try?` produirait `nil`, et un site d'appel finirait par écrire
    /// `?? .allEntries` « le temps de déboguer ».
    func entries(for context: ChatFinanceContext) async -> [FinanceCatalogEntry]

    /// Les mêmes entrées, mais en distinguant **« rien à proposer »** de
    /// **« catalogue injoignable »**.
    ///
    /// `entries(for:)` rend `[]` dans les deux cas, et l'écran ne peut alors
    /// qu'inventer une raison : il annonçait « les services dépendent de votre
    /// pays » alors que le serveur n'avait simplement pas répondu. Un accueil
    /// qui ne sait pas s'il est vide ou en panne ne peut pas se dessiner
    /// correctement.
    func load(for context: ChatFinanceContext) async -> Result<[FinanceCatalogEntry], FinanceError>

    /// Force une résolution. À appeler sur changement de compte, de pays, ou à
    /// réception d'un kill switch.
    func invalidate() async

    /// Le dossier personnel, pour les parcours ouverts **hors conversation**.
    ///
    /// Payer sa facture ou recharger son téléphone n'a pas d'interlocuteur, et
    /// le serveur exige pourtant une conversation pour porter l'opération. Il
    /// en tient une : un dossier à un seul membre, qu'il crée ou réutilise.
    /// C'est son identifiant que le devis puis l'exécution doivent porter — le
    /// même pour les deux.
    ///
    /// `nil` ⇒ le serveur n'en propose pas (version antérieure, ou parcours
    /// fermé). L'appelant ne le remplace pas par une conversation choisie au
    /// hasard : sans dossier, l'opération n'a pas lieu.
    func personalFolder() async -> PersonalFinanceFolder?

    /// `POST /hub/intent/parse` (§2.2) — un texte libre (« envoie 5000 à
    /// Jean ») lu comme un **brouillon**, jamais comme une commande.
    ///
    /// Le brouillon dit quelle action ouvrir et quel montant y proposer ; il
    /// ne désigne pas de bénéficiaire (le serveur ne résout jamais sur un nom,
    /// `CF_028`) et ne déclenche rien. L'écran du parcours reste celui qui
    /// prépare, fait confirmer, puis exécute.
    func draft(from text: String) async -> Result<FinanceTextDraft, FinanceError>

    /// `true` si cette implémentation sait émettre et consommer un handoff.
    ///
    /// Distingue « je ne sais pas faire de handoff » d'un **refus serveur**,
    /// que `capabilityUnavailable` dirait tous les deux — même raison que
    /// `BillPaying.providesQuotes`.
    var providesHandoff: Bool { get }

    /// `POST /hub/handoff` puis `POST /hub/handoff/consume` (§2.3).
    ///
    /// Le contexte d'un parcours ouvert depuis une conversation — la
    /// conversation, l'action, le pays — **relu par le serveur** plutôt que
    /// cru sur parole. Le jeton est à usage unique et lié à l'utilisateur ;
    /// expiré ou rejoué ⇒ `CF_025`.
    func handoff(conversationID: String,
                 actionCode: String) async -> Result<FinanceHandoffContext, FinanceError>

    /// `GET /hub/copilot-tools` (§8) — les outils que Waangu Copilot peut invoquer
    /// **pour cet utilisateur, ici**. Aucun n'exécute : ils préparent, expliquent.
    func copilotTools() async -> Result<[FinanceCopilotTool], FinanceError>

    /// `POST /hub/copilot-tools/invoke` (§8). La réponse oriente vers un
    /// parcours (`handoffAction`) ; elle ne paie jamais (`CF_060` sinon).
    func invokeCopilotTool(_ name: String) async -> Result<FinanceCopilotReply, FinanceError>
}

public extension ChatFinanceCatalogProviding {

    /// Par défaut, un catalogue qui ne peut pas échouer : les fournisseurs
    /// locaux (fermé, doublures) rendent toujours une liste, et seule une
    /// source distante redéfinit cette méthode.
    func load(for context: ChatFinanceContext) async -> Result<[FinanceCatalogEntry], FinanceError> {
        .success(await entries(for: context))
    }

    /// Par défaut, aucun dossier : seule une source distante en connaît un.
    func personalFolder() async -> PersonalFinanceFolder? { nil }

    /// Par défaut, aucun brouillon : seul le Hub sait lire un texte.
    func draft(from text: String) async -> Result<FinanceTextDraft, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Par défaut non : seule une implémentation branchée sur `/hub/handoff`
    /// l'affirme.
    var providesHandoff: Bool { false }

    func handoff(conversationID: String,
                 actionCode: String) async -> Result<FinanceHandoffContext, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    /// Par défaut, pas de Waangu Copilot : seul le Hub publie ses outils.
    func copilotTools() async -> Result<[FinanceCopilotTool], FinanceError> {
        .failure(.capabilityUnavailable)
    }

    func invokeCopilotTool(_ name: String) async -> Result<FinanceCopilotReply, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}

/// Un outil de Waangu Copilot, tel que le Hub le publie (§8).
public struct FinanceCopilotTool: Sendable, Hashable {
    /// Identifiant serveur — `send_money.prepare`. Le seul nom invocable.
    public let name: String
    public let version: String?
    public let domain: String?
    /// `PREPARE`, `EXPLAIN`… Jamais `EXECUTE` : un tel outil n'est pas retenu.
    public let operation: String
    /// Le parcours vers lequel l'outil oriente, quand ce client sait l'ouvrir.
    public let kind: FinanceEntryKind?
    /// Description rédigée par le serveur.
    public let summary: String?

    public init(name: String, version: String?, domain: String?, operation: String,
                kind: FinanceEntryKind?, summary: String?) {
        self.name = name
        self.version = version
        self.domain = domain
        self.operation = operation
        self.kind = kind
        self.summary = summary
    }
}

/// Ce que Waangu Copilot répond à une invocation — un message et une orientation.
public struct FinanceCopilotReply: Sendable, Hashable {
    public let tool: String
    /// Message du serveur, affiché tel quel. Waangu Copilot n'en rédige pas.
    public let message: String?
    /// Parcours proposé (`handoffAction`). `nil` ⇒ rien à ouvrir.
    public let kind: FinanceEntryKind?
    public let nextSafeActions: [String]
    /// `authoritative` du serveur. `false` ⇒ les mots de Copilot, jamais un fait :
    /// montants et statuts viennent du devis ou de la carte de l'opération.
    public let isAuthoritative: Bool

    public init(tool: String, message: String?, kind: FinanceEntryKind?, nextSafeActions: [String],
                isAuthoritative: Bool = false) {
        self.tool = tool
        self.message = message
        self.kind = kind
        self.nextSafeActions = nextSafeActions
        self.isAuthoritative = isAuthoritative
    }
}

/// Un texte libre lu par le Hub — §2.2. **Un brouillon, jamais une commande.**
///
/// Tout est candidat : l'action, le montant, la devise. `counterpartyHint`
/// n'est qu'un indice affichable ; il ne remplace jamais un bénéficiaire résolu.
public struct FinanceTextDraft: Sendable, Hashable {
    /// L'action à ouvrir. `nil` ⇒ le Hub n'en a reconnu aucune que ce client
    /// sache ouvrir.
    public let kind: FinanceEntryKind?
    public let amount: Decimal?
    public let currency: String?
    public let counterpartyHint: String?
    /// Message rédigé par le serveur, affichable tel quel.
    public let message: String?

    public init(kind: FinanceEntryKind?, amount: Decimal?, currency: String?,
                counterpartyHint: String? = nil, message: String? = nil) {
        self.kind = kind
        self.amount = amount
        self.currency = currency
        self.counterpartyHint = counterpartyHint
        self.message = message
    }
}

/// Le contexte d'un parcours, tel que le serveur l'a rendu au handoff — §2.3.
public struct FinanceHandoffContext: Sendable, Hashable {
    public let conversationID: String?
    public let actionCode: String?
    public let financialIntentRef: String?
    public let country: String?

    public init(conversationID: String?, actionCode: String?,
                financialIntentRef: String? = nil, country: String? = nil) {
        self.conversationID = conversationID
        self.actionCode = actionCode
        self.financialIntentRef = financialIntentRef
        self.country = country
    }
}

/// Le dossier personnel rendu par le serveur — « Mes factures ».
public struct PersonalFinanceFolder: Sendable, Hashable, Codable {

    public let conversationID: String
    /// Époque d'appartenance à porter sur les écritures ; `nil` si le serveur
    /// ne la rend pas.
    public let membershipEpoch: Int?
    /// Intitulé rédigé par le serveur. Vide ⇒ l'écran garde le sien.
    public let title: String

    public init(conversationID: String, membershipEpoch: Int? = nil, title: String = "") {
        self.conversationID = conversationID
        self.membershipEpoch = membershipEpoch
        self.title = title
    }
}

// MARK: - Entrée de catalogue

/// Une entrée proposable dans le menu financier d'une conversation.
public struct FinanceCatalogEntry: Codable, Sendable, Hashable, Identifiable {

    public let id: String
    public let kind: FinanceEntryKind

    /// Clé de localisation, **jamais un libellé**.
    ///
    /// Le backend décide de ce qui est proposable ; GEORGES décide de comment ça
    /// se dit. Transporter la chaîne finale mélangerait les deux et rendrait
    /// impossible de traduire sans redéployer le backend.
    public let titleKey: String

    /// Nom de symbole SF. Purement présentationnel.
    public let iconName: String

    /// `false` ⇒ l'entrée est **affichée grisée** avec son motif.
    ///
    /// Jamais masquée en silence : une entrée qui disparaît laisse l'utilisateur
    /// la chercher, puis conclure que l'application est cassée. Lui dire pourquoi
    /// elle est fermée coûte une ligne et évite un appel au support.
    public let isEnabled: Bool

    /// Clé de localisation du motif d'indisponibilité. Requise si `isEnabled`
    /// est `false` — une entrée grisée sans explication est pire que rien.
    public let unavailableReasonKey: String?

    /// Au-delà, l'entrée n'est plus proposable sans nouvelle résolution.
    public let expiresAt: Date?

    /// Identifiant de la cible de l'entrée — le marchand pour `merchant`, le
    /// facturier pour une facture pré-remplie.
    ///
    /// **Rendu par le backend, jamais déduit de la conversation.** Traiter un
    /// interlocuteur comme un marchand parce que le fil « ressemble » à une
    /// boutique donnerait à la conversation un pouvoir financier : c'est au
    /// backend d'établir qu'un acteur est marchand, et de le nommer ici.
    public let targetID: String?

    /// Le Hub exige une élévation avant d'ouvrir le parcours — capacités
    /// `PILOT` / `LIMITED` (§2.1, `requiresStepUp`).
    ///
    /// Optionnel pour rester décodable depuis un catalogue qui ne le porte pas :
    /// absent ⇒ aucune élévation **en plus** de celles du parcours lui-même.
    public let requiresStepUp: Bool?

    public init(
        id: String,
        kind: FinanceEntryKind,
        titleKey: String,
        iconName: String,
        isEnabled: Bool,
        unavailableReasonKey: String? = nil,
        expiresAt: Date? = nil,
        targetID: String? = nil,
        requiresStepUp: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.titleKey = titleKey
        self.iconName = iconName
        self.isEnabled = isEnabled
        self.unavailableReasonKey = unavailableReasonKey
        self.expiresAt = expiresAt
        self.targetID = targetID
        self.requiresStepUp = requiresStepUp
    }
}

public extension FinanceCatalogEntry {

    /// `true` si l'entrée est encore valide à l'instant donné.
    /// Une entrée sans échéance est valide — c'est au backend de la borner.
    func isValid(asOf now: Date = Date()) -> Bool {
        guard let expiresAt else { return true }
        return expiresAt > now
    }

    /// `true` si l'entrée peut être **activée** maintenant.
    ///
    /// Une entrée périmée n'est pas actionnable, même marquée `isEnabled` : le
    /// catalogue qui l'a autorisée n'est plus d'actualité.
    func isActionable(asOf now: Date = Date()) -> Bool {
        isEnabled && isValid(asOf: now)
    }
}

// MARK: - Nature de l'entrée

public enum FinanceEntryKind: String, Codable, Sendable, CaseIterable {
    case requestMoney = "REQUEST_MONEY"
    case sendMoney    = "SEND_MONEY"
    case cashIn       = "CASH_IN"
    case cashOut      = "CASH_OUT"
    case payBill      = "PAY_BILL"
    case qrPay        = "QR_PAY"
    case qrPresent    = "QR_PRESENT"
    case merchant     = "MERCHANT"
    case orders       = "ORDERS"
    case remoteForm   = "REMOTE_FORM"
    case invoice      = "INVOICE"
    case paymentLinks = "PAYMENT_LINKS"
    case cards        = "CARDS"
    case splitBill    = "SPLIT_BILL"
    case campaign     = "CAMPAIGN"
    case reconciliation = "RECONCILIATION"
    case topUp        = "TOP_UP"

    // ── Bloc 5 ───────────────────────────────────────────────
    case remittance   = "REMITTANCE"
    case fxConversion = "FX_CONVERSION"
    case credit       = "CREDIT"
    case savings      = "SAVINGS"
    case investment   = "INVESTMENT"
    case pfm          = "PFM"

    /// Une nature inconnue de ce client fait échouer le décodage de l'entrée.
    ///
    /// Pas de repli : afficher une entrée dont on ignore la nature conduirait à
    /// ouvrir un parcours qu'on ne sait pas rendre. L'appelant écarte l'entrée
    /// et affiche les autres — un client ancien perd une entrée, il n'en invente
    /// pas une fausse.
    /// Ce parcours se fait **sans interlocuteur** : ouvert hors conversation,
    /// c'est le dossier personnel qui porte l'opération (§5.1.1).
    ///
    /// Les quatre du groupe `WALLET` du Hub. Un envoi ou une demande n'en sont
    /// pas : ils s'adressent à quelqu'un, et sans conversation ils ont déjà un
    /// bénéficiaire à désigner.
    public var usesPersonalFolder: Bool {
        switch self {
        case .payBill, .topUp, .cashIn, .cashOut: return true
        default:                                  return false
        }
    }

    /// Capacité `FinancialCapabilityID` correspondante, quand elle existe.
    ///
    /// Relie l'entrée de menu aux quatre portes du §16 : une entrée dont la
    /// capacité est fermée ne doit pas s'ouvrir, même si le catalogue la rend.
    /// Les deux sources se cumulent — le catalogue dit ce qui existe, les portes
    /// disent ce qui est permis.
    public var capabilityID: String? {
        switch self {
        // Clés publiées par la gouvernance Chat Core.
        case .sendMoney:    return FinancialCapabilityID.sendMoney
        case .requestMoney, .paymentLinks:
                            return FinancialCapabilityID.requestMoney
        case .payBill:      return FinancialCapabilityID.payBill
        case .qrPay:        return FinancialCapabilityID.scanQR
        case .splitBill:    return FinancialCapabilityID.splitBill
        case .topUp:        return FinancialCapabilityID.topUp
        case .cashIn:       return FinancialCapabilityID.cashIn
        case .cashOut:      return FinancialCapabilityID.cashOut
        case .remittance:   return FinancialCapabilityID.remittance
        case .fxConversion: return FinancialCapabilityID.fxConversion
        case .credit:       return FinancialCapabilityID.creditDiscovery
        case .savings:      return FinancialCapabilityID.savings
        case .investment:   return FinancialCapabilityID.investment
        case .pfm:          return FinancialCapabilityID.pfm
        // **Plus aucune entrée sans porte** — Bloc 13, P0 fermé.
        //
        // Ces entrées n'ont pas de clé dans la matrice de gouvernance. Elles
        // portent donc leur propre nom, qu'aucun instantané serveur ne contient :
        // la porte les trouve absentes et les ferme (`notEnabled`). Rendre `nil`
        // les ouvrait sans condition.
        case .qrPresent, .merchant, .orders, .remoteForm, .invoice,
             .cards, .campaign, .reconciliation:
            return rawValue
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        guard let value = FinanceEntryKind(rawValue: raw) else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath,
                      debugDescription: "Entrée financière inconnue : \(raw)")
            )
        }
        self = value
    }
}

// MARK: - Contexte

/// Ce pour quoi le catalogue est résolu.
public struct ChatFinanceContext: Sendable, Hashable, Codable {

    public let conversationID: String
    public let conversationKind: ConversationFinancialKind
    public let participantCount: Int

    public init(
        conversationID: String,
        conversationKind: ConversationFinancialKind,
        participantCount: Int
    ) {
        self.conversationID = conversationID
        self.conversationKind = conversationKind
        self.participantCount = participantCount
    }
}

/// Nature financière d'une conversation.
///
/// **BACKEND SOURCE OF TRUTH.** Le client ne déduit pas qu'une conversation est
/// marchande : le déduire du fil donnerait à la conversation un pouvoir
/// financier, ce que l'architecture interdit depuis le Bloc 1.
public enum ConversationFinancialKind: String, Codable, Sendable, CaseIterable {
    case direct, group, merchant, institution, support

    /// Son propre dossier : un membre, aucun correspondant.
    ///
    /// C'est ce qu'ouvrent les Réglages et le portefeuille — payer sa facture,
    /// recharger son téléphone, déposer ou retirer. Ces parcours n'ont pas
    /// d'interlocuteur, et les faire passer pour un tête-à-tête demandait au
    /// serveur les actions d'une conversation qui n'existe pas.
    ///
    /// **Nommé comme `ConversationTypeModel.selfChat`**, et pour la même chose.
    /// Il s'appelait `personal` : deux noms pour une seule notion, dans deux
    /// énumérations qui produisent toutes deux `SELF` — de quoi chercher le cas
    /// manquant dans l'une en le trouvant sous un autre nom dans l'autre.
    ///
    /// Valeur brute explicite : sans elle, ce cas se décodait de `"selfChat"`
    /// et jamais de `"SELF"`, donc un dossier personnel rendu par le serveur
    /// serait retombé en silence sur `direct`.
    case selfChat = "SELF"

    /// Une nature inconnue retombe sur `direct`, la plus restrictive : elle ne
    /// débloque aucun parcours marchand ni institutionnel.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ConversationFinancialKind(rawValue: raw) ?? .direct
    }
}
