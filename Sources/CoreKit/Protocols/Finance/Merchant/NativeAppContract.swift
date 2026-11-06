//
//  NativeAppContract.swift
//  CoreKit
//
//  Mini-apps et commerce conversationnel — Bloc 6, chapitre 52.
//
//  **BACKEND CONTRACT REQUIRED** — registre des applications, résolution
//  d'objet, callback, requête d'état.
//

import Foundation

/// Objets appartenant à une application propriétaire.
///
/// Neuf modules existent dans ce dépôt — course, livraison, marché, pharmacie,
/// location, billets, assurance, consultation, portefeuille. Chacun a **sa
/// vérité**, et Divin n'en détient aucune : il affiche une carte, ouvre un lien,
/// et corrèle une référence financière.
///
/// Un contrat **générique** plutôt qu'un par application. Neuf protocoles
/// parallèles divergeraient au premier ajout, et la dixième intégration
/// recopierait la neuvième avec ses défauts. Ce qui varie — les champs métier —
/// reste opaque à cette couche.
public protocol NativeAppObjectProviding: Sendable {

    /// Applications déclarées pour cet utilisateur, avec leurs capacités.
    func registry() async -> Result<[NativeAppDescriptor], FinanceError>

    /// Résout un objet appartenant à une application.
    ///
    /// **Toujours par le backend.** Lire l'objet depuis la charge d'un lien
    /// reviendrait à faire confiance à ce qu'on veut vérifier.
    func resolve(
        appID: String,
        objectType: String,
        objectID: String
    ) async -> Result<NativeAppObject, FinanceError>

    /// Redemande l'état d'un objet.
    ///
    /// Le pendant du §19 côté mini-app : un objet dont l'état est incertain se
    /// requête, il ne se recrée pas.
    func requery(_ reference: NativeObjectReference) async -> Result<NativeAppObject, FinanceError>

    /// Enregistre le retour d'une mini-app après une action.
    ///
    /// Le callback est **vérifié**, pas cru : il arrive par un canal que
    /// l'utilisateur traverse, donc il est falsifiable.
    func acknowledgeCallback(
        _ callback: NativeAppCallback,
        idempotency: IdempotencyContext
    ) async -> Result<NativeAppObject, FinanceError>
}

// MARK: - Registre

/// Une application propriétaire, et ce qu'elle a le droit de faire.
public struct NativeAppDescriptor: Codable, Sendable, Hashable, Identifiable {

    public var id: String { appID }

    /// Identifiant logique — `waangu.ride`, `waangu.pharmacy`.
    public let appID: String

    /// Propriétaire de la vérité pour cette application.
    public let owner: String

    public let displayNameKey: String

    /// Types d'objets que l'application expose.
    public let objectTypes: [String]

    /// Capacités accordées. Une application peut lire sans pouvoir facturer.
    public let capabilities: Set<NativeAppCapability>

    /// Version du contrat supportée par cette application.
    public let contractVersion: String

    /// L'application est-elle installée et joignable sur cet appareil ?
    public let isAvailable: Bool
    public let unavailableReasonKey: String?

    /// Ce qu'il faut faire quand elle n'est pas joignable.
    ///
    /// Sans repli, un objet référencé dans une conversation devient un cul-de-
    /// sac le jour où l'application est retirée du marché.
    public let fallback: NativeAppFallback

    public init(appID: String, owner: String, displayNameKey: String,
                objectTypes: [String], capabilities: Set<NativeAppCapability>,
                contractVersion: String, isAvailable: Bool,
                unavailableReasonKey: String? = nil, fallback: NativeAppFallback) {
        self.appID = appID
        self.owner = owner
        self.displayNameKey = displayNameKey
        self.objectTypes = objectTypes
        self.capabilities = capabilities
        self.contractVersion = contractVersion
        self.isAvailable = isAvailable
        self.unavailableReasonKey = unavailableReasonKey
        self.fallback = fallback
    }

    /// L'application peut-elle traiter ce type d'objet ?
    ///
    /// Vérifié avant d'ouvrir : router un objet de pharmacie vers l'application
    /// de course produit un écran vide et un ticket de support.
    public func handles(objectType: String) -> Bool {
        objectTypes.contains(objectType)
    }
}

public enum NativeAppCapability: String, Codable, Sendable, CaseIterable {
    /// Afficher une carte dans la conversation.
    case renderCard      = "RENDER_CARD"
    /// Ouvrir l'application sur un objet.
    case deepLink        = "DEEP_LINK"
    /// Demander un paiement rattaché à un objet.
    case requestPayment  = "REQUEST_PAYMENT"
    /// Émettre un remboursement.
    case issueRefund     = "ISSUE_REFUND"
    /// Publier des mises à jour d'état.
    case publishUpdates  = "PUBLISH_UPDATES"
}

public enum NativeAppFallback: String, Codable, Sendable, CaseIterable {
    /// Ouvrir une page web équivalente.
    case web         = "WEB"
    /// Proposer l'installation.
    case install     = "INSTALL"
    /// Afficher la carte sans action.
    case cardOnly    = "CARD_ONLY"
    /// Rien n'est possible — le dire.
    case none        = "NONE"

    /// Repli inconnu ⇒ carte seule. Ni installation imposée, ni cul-de-sac.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NativeAppFallback(rawValue: raw) ?? .cardOnly
    }
}

// MARK: - Référence et objet

/// Ce qui suffit à retrouver un objet, sans le contenir.
///
/// Circule dans les conversations et les liens. **Ne porte aucune donnée
/// métier** : un identifiant partagé qui contiendrait le prix ou l'adresse
/// serait une fuite dès le premier transfert de message.
public struct NativeObjectReference: Codable, Sendable, Hashable {
    public let appID: String
    public let objectType: String
    public let objectID: String
    /// Version connue de l'objet, pour détecter une évolution.
    public let version: String?

    public init(appID: String, objectType: String, objectID: String, version: String? = nil) {
        self.appID = appID
        self.objectType = objectType
        self.objectID = objectID
        self.version = version
    }
}

/// Un objet appartenant à une application propriétaire.
///
/// Divin ne connaît **ni** sa structure métier **ni** ses règles. Il en connaît
/// l'enveloppe : qui le possède, où il en est, ce qu'il coûte, et comment
/// l'ouvrir. Le reste est présenté par ``UniversalCard``, que l'application
/// remplit.
public struct NativeAppObject: Codable, Sendable, Hashable, Identifiable {

    public var id: String { reference.objectID }
    public let reference: NativeObjectReference

    public let lifecycle: NativeObjectLifecycle

    /// Carte à afficher, composée **par l'application propriétaire**.
    public let card: UniversalCard

    /// Corrélation financière : le paiement rattaché à cet objet, s'il existe.
    ///
    /// C'est ce champ qui rend le rapprochement possible. Sans lui, une
    /// commande payée et un débit constaté restent deux faits sans lien.
    public let financialReference: FinancialReference?

    /// Classification de confidentialité, appliquée à l'affichage.
    public let privacyClass: NativeObjectPrivacyClass

    public let updatedAt: Date

    public init(reference: NativeObjectReference, lifecycle: NativeObjectLifecycle,
                card: UniversalCard, financialReference: FinancialReference? = nil,
                privacyClass: NativeObjectPrivacyClass, updatedAt: Date) {
        self.reference = reference
        self.lifecycle = lifecycle
        self.card = card
        self.financialReference = financialReference
        self.privacyClass = privacyClass
        self.updatedAt = updatedAt
    }
}

/// Où en est un objet, indépendamment de son métier.
///
/// Une course, une ordonnance et un billet ont des cycles différents, mais tous
/// se ramènent à ces sept temps. C'est ce qui permet une carte générique sans
/// connaître les neuf métiers.
public enum NativeObjectLifecycle: String, Codable, Sendable, CaseIterable {
    case draft      = "DRAFT"
    case pending    = "PENDING"
    case confirmed  = "CONFIRMED"
    case inProgress = "IN_PROGRESS"
    case completed  = "COMPLETED"
    case cancelled  = "CANCELLED"
    case failed     = "FAILED"
    /// État que ce client ne sait pas rendre. **Ni abouti, ni échoué.**
    case unknown    = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NativeObjectLifecycle(rawValue: raw) ?? .unknown
    }

    public var isTerminal: Bool {
        switch self {
        case .completed, .cancelled, .failed: return true
        default: return false
        }
    }

    /// Doit être requêté plutôt qu'affiché comme définitif.
    public var requiresRequery: Bool { self == .unknown || self == .pending }
}

public enum NativeObjectPrivacyClass: String, Codable, Sendable, CaseIterable {
    case publicInfo    = "PUBLIC"
    case conversational = "CONVERSATIONAL"
    case transactional = "TRANSACTIONAL"
    case sensitive     = "SENSITIVE"

    /// Classe inconnue ⇒ la plus restrictive.
    ///
    /// Une ordonnance ou une consultation médicale relève de `sensitive` ; se
    /// tromper dans ce sens masque trop, se tromper dans l'autre expose.
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NativeObjectPrivacyClass(rawValue: raw) ?? .sensitive
    }

    /// Peut être rendu dans le fil de conversation, visible d'un tiers qui
    /// regarde par-dessus l'épaule.
    public var canRenderInline: Bool {
        self == .publicInfo || self == .conversational
    }
}

// MARK: - Carte universelle

/// Une carte que Divin sait rendre sans connaître le métier.
///
/// L'application propriétaire remplit des **libellés**, pas des vues : c'est ce
/// qui empêche une mini-app d'injecter de l'interface arbitraire dans une
/// conversation, et ce qui garde le rendu cohérent entre neuf intégrations.
public struct UniversalCard: Codable, Sendable, Hashable {

    public let titleKey: String
    public let subtitleKey: String?

    /// Lignes de détail, dans l'ordre d'affichage.
    public let rows: [UniversalCardRow]

    public let imageURL: URL?

    /// Montant rattaché, quand l'objet en porte un.
    public let amount: Money?

    /// Actions proposées. **Déclaratives** : chacune désigne une intention que
    /// Divin sait traiter, jamais du code fourni par l'application.
    public let actions: [UniversalCardAction]

    /// Statut affichable, en clé — jamais la valeur brute du backend.
    public let statusKey: String?

    public init(titleKey: String, subtitleKey: String? = nil,
                rows: [UniversalCardRow] = [], imageURL: URL? = nil,
                amount: Money? = nil, actions: [UniversalCardAction] = [],
                statusKey: String? = nil) {
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.rows = rows
        self.imageURL = imageURL
        self.amount = amount
        self.actions = actions
        self.statusKey = statusKey
    }
}

public struct UniversalCardRow: Codable, Sendable, Hashable, Identifiable {
    public var id: String { labelKey }
    public let labelKey: String
    public let valueKey: String

    public init(labelKey: String, valueKey: String) {
        self.labelKey = labelKey
        self.valueKey = valueKey
    }
}

public struct UniversalCardAction: Codable, Sendable, Hashable, Identifiable {
    public var id: String { "\(kind.rawValue)-\(labelKey)" }
    public let kind: UniversalCardActionKind
    public let labelKey: String
    /// `false` ⇒ affichée grisée avec son motif, jamais masquée en silence.
    public let isEnabled: Bool
    public let disabledReasonKey: String?

    public init(kind: UniversalCardActionKind, labelKey: String,
                isEnabled: Bool, disabledReasonKey: String? = nil) {
        self.kind = kind
        self.labelKey = labelKey
        self.isEnabled = isEnabled
        self.disabledReasonKey = disabledReasonKey
    }
}

/// Ce qu'une carte peut demander.
///
/// Liste **fermée**. Une intention libre laisserait une mini-app inventer des
/// actions que Divin exécuterait sans les comprendre.
public enum UniversalCardActionKind: String, Codable, Sendable, CaseIterable {
    case open      = "OPEN"
    case pay       = "PAY"
    case track     = "TRACK"
    case cancel    = "CANCEL"
    case contact   = "CONTACT"
    case receipt   = "RECEIPT"
    /// Action inconnue de ce client : affichée grisée, jamais exécutée.
    case unknown   = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = UniversalCardActionKind(rawValue: raw) ?? .unknown
    }

    /// Une action inconnue ne s'exécute pas, quoi qu'en dise `isEnabled`.
    public var isExecutable: Bool { self != .unknown }
}

// MARK: - Callback

/// Le retour d'une mini-app après une action.
///
/// Traverse un canal que l'utilisateur emprunte — un lien, un retour
/// d'application. Il est donc **falsifiable**, et n'est jamais cru sur parole :
/// `acknowledgeCallback` le fait vérifier par le backend, qui seul sait si
/// l'objet a réellement bougé.
public struct NativeAppCallback: Sendable, Hashable, Codable {

    public let reference: NativeObjectReference

    /// Ce que l'application prétend qu'il s'est passé. **Une prétention**, pas
    /// un fait : le nom du champ le dit, pour que personne ne l'oublie.
    public let claimedLifecycle: NativeObjectLifecycle

    /// Contexte signé accompagnant le retour, quand l'application en émet un.
    public let signedContext: SignedDeepLinkContext?

    public let receivedAt: Date

    public init(reference: NativeObjectReference, claimedLifecycle: NativeObjectLifecycle,
                signedContext: SignedDeepLinkContext? = nil, receivedAt: Date) {
        self.reference = reference
        self.claimedLifecycle = claimedLifecycle
        self.signedContext = signedContext
        self.receivedAt = receivedAt
    }

    /// Un retour qui prétend un aboutissement **sans contexte signé** est
    /// suspect : c'est la forme qu'aurait un lien fabriqué pour faire croire
    /// qu'une commande est payée.
    public var claimsCompletionWithoutProof: Bool {
        signedContext == nil && (claimedLifecycle == .completed || claimedLifecycle == .confirmed)
    }
}

// MARK: - Défaut fermé

/// Ne résout aucun objet et n'accepte aucun retour.
public struct ClosedNativeAppObjectProvider: NativeAppObjectProviding {

    public init() {}

    public func registry() async -> Result<[NativeAppDescriptor], FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func resolve(appID: String, objectType: String,
                        objectID: String) async -> Result<NativeAppObject, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func requery(_ reference: NativeObjectReference) async -> Result<NativeAppObject, FinanceError> {
        .failure(.capabilityUnavailable)
    }
    public func acknowledgeCallback(_ callback: NativeAppCallback,
                                    idempotency: IdempotencyContext) async -> Result<NativeAppObject, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
