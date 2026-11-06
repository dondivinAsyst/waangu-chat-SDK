//
//  SupportContextPackage.swift
//  CoreKit
//
//  Dossier de support contextualisé — Bloc 4 §45 (GAP-12).
//

import Foundation

/// Ce qui part au support avec une demande d'aide.
///
/// **L'utilisateur ne recopie rien.** Tout ce que le client sait est repris ;
/// tout ce qu'il ne doit pas transmettre est écarté par construction.
///
/// Le filtrage est dans le constructeur et non au site d'appel : un paquet de
/// support est assemblé au pire moment, quand quelqu'un vient de perdre de
/// l'argent, et personne ne relit alors la liste des champs.
public struct SupportContextPackage: Sendable, Hashable, Codable {

    public let supportCaseID: String
    public let paymentIntentID: String?
    public let providerReference: String?
    public let invoiceReference: String?

    /// Référence client **masquée**. Le support n'a pas besoin du numéro de
    /// compteur entier pour identifier un dossier.
    public let maskedCustomerReference: String?

    public let openedAt: Date
    public let observedStatus: PaymentStatus
    public let statusHistory: [SupportStatusEntry]
    public let reconciliationState: String?
    public let correlationID: CorrelationId

    /// Pièces jointes autorisées, par référence — **jamais leur contenu**.
    public let evidenceReferences: [String]

    public init(
        supportCaseID: String = UUID().uuidString,
        paymentIntentID: String? = nil,
        providerReference: String? = nil,
        invoiceReference: String? = nil,
        customerReference: String? = nil,
        openedAt: Date = Date(),
        observedStatus: PaymentStatus,
        statusHistory: [SupportStatusEntry] = [],
        reconciliationState: String? = nil,
        correlationID: CorrelationId,
        evidenceReferences: [String] = []
    ) {
        self.supportCaseID = supportCaseID
        self.paymentIntentID = paymentIntentID
        self.providerReference = providerReference
        self.invoiceReference = invoiceReference
        self.maskedCustomerReference = customerReference.map(Self.mask)
        self.openedAt = openedAt
        self.observedStatus = observedStatus
        self.statusHistory = statusHistory
        self.reconciliationState = reconciliationState
        self.correlationID = correlationID
        self.evidenceReferences = evidenceReferences
    }

    /// Ne laisse que les quatre derniers caractères.
    static func mask(_ value: String) -> String {
        guard value.count > 4 else { return String(repeating: "•", count: value.count) }
        return String(repeating: "•", count: value.count - 4) + value.suffix(4)
    }
}

public struct SupportStatusEntry: Sendable, Hashable, Codable {
    public let status: PaymentStatus
    public let observedAt: Date
    /// Clé de motif rendue par le backend, jamais une phrase composée ici.
    public let reasonKey: String?

    public init(status: PaymentStatus, observedAt: Date, reasonKey: String? = nil) {
        self.status = status
        self.observedAt = observedAt
        self.reasonKey = reasonKey
    }
}

public extension SupportContextPackage {

    /// Construit un dossier depuis une opération observée.
    static func from(
        reference: FinancialReference,
        observedStatus: PaymentStatus,
        history: [SupportStatusEntry] = [],
        providerReference: String? = nil,
        customerReference: String? = nil
    ) -> SupportContextPackage {
        SupportContextPackage(
            paymentIntentID: reference.id,
            providerReference: providerReference,
            customerReference: customerReference,
            observedStatus: observedStatus,
            statusHistory: history,
            // Reprise telle quelle : une corrélation neuve couperait le lien
            // avec les traces de l'opération, que le support doit retrouver.
            correlationID: reference.correlationID
        )
    }

    /// Le dossier contient-il de quoi enquêter ?
    ///
    /// Sans corrélation ni référence d'intention, le support reçoit une plainte
    /// qu'il ne peut rattacher à rien.
    var isActionable: Bool {
        paymentIntentID != nil && !correlationID.value.isEmpty
    }
}

// MARK: - Ouverture d'un dossier de support

/// Ouvre un dossier de support **corrélé** à une transaction.
///
/// **BACKEND CONTRACT REQUIRED** — ouverture, suivi, clôture.
///
/// La corrélation est le tout : un dossier ouvert sans référence de paiement
/// oblige l'agent à redemander à l'utilisateur ce que l'application connaît
/// déjà, et c'est là que les montants se recopient de travers.
public protocol SupportCaseOpening: Sendable {

    /// Assemble le contexte à partir d'une transaction. Le contexte est
    /// **rendu par le backend** : le composer côté client reviendrait à faire
    /// confiance à l'écran qui signale un problème.
    func context(for reference: FinancialReference) async -> Result<SupportContextPackage, FinanceError>

    /// Ouvre le dossier avec le contexte présenté à l'utilisateur.
    ///
    /// `contextID` renvoie le contexte exact qui lui a été montré : ouvrir un
    /// dossier sur un contexte recalculé entre-temps ferait diverger ce que
    /// l'utilisateur a lu et ce que l'agent voit.
    func open(
        contextID: String,
        messageText: String,
        idempotency: IdempotencyContext
    ) async -> Result<SupportCase, FinanceError>
}

public struct SupportCase: Sendable, Hashable, Codable, Identifiable {

    public let id: String
    public let state: SupportCaseState
    public let openedAt: Date

    /// Délai de réponse annoncé **par le support**. `nil` ⇒ aucun délai promis,
    /// ce qui vaut mieux qu'un délai inventé que personne ne tiendra.
    public let expectedResponseSeconds: TimeInterval?

    public init(id: String, state: SupportCaseState, openedAt: Date,
                expectedResponseSeconds: TimeInterval? = nil) {
        self.id = id
        self.state = state
        self.openedAt = openedAt
        self.expectedResponseSeconds = expectedResponseSeconds
    }
}

/// Les onze états du §60.
///
/// Étendu au Bloc 7 : les cinq états d'origine ne distinguaient pas une attente
/// côté client d'une attente côté fournisseur, ni une escalade d'une remontée
/// en conformité. Or c'est exactement cette distinction que le SLA doit faire —
/// un dossier bloqué sur un tiers ne consomme pas le délai promis au client.
public enum SupportCaseState: String, Sendable, Codable, CaseIterable {

    case open                = "OPEN"

    /// Qualifié, pas encore pris en charge.
    case triaged             = "TRIAGED"

    case inProgress          = "IN_PROGRESS"

    /// En attente du client. **Suspend le SLA** — le délai qui court est le
    /// sien, pas le nôtre.
    case waiting             = "WAITING_ON_CUSTOMER"

    /// En attente d'un tiers — rail, banque, opérateur. Suspend aussi le SLA,
    /// mais n'est pas la même chose : confondre les deux ferait relancer le
    /// client pour une information qu'il n'a pas.
    case waitingOnProvider   = "WAITING_ON_PROVIDER"

    /// Remonté à un niveau supérieur.
    case escalated           = "ESCALATED"

    /// Remis à la conformité. Le support n'en décide plus.
    case pendingCompliance   = "PENDING_COMPLIANCE"

    case resolved            = "RESOLVED"

    /// Rouvert après résolution. Un dossier rouvert repart avec un SLA neuf.
    case reopened            = "REOPENED"

    case closed              = "CLOSED"

    /// Annulé — doublon, ouverture accidentelle. Distinct de `closed` : un
    /// dossier annulé ne compte dans aucune statistique de résolution.
    case cancelled           = "CANCELLED"

    case unknown             = "UNKNOWN"

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = SupportCaseState(rawValue: raw) ?? .unknown
    }

    /// Le compteur de SLA tourne-t-il ?
    public var consumesSLA: Bool {
        switch self {
        case .open, .triaged, .inProgress, .escalated, .reopened:
            return true
        case .waiting, .waitingOnProvider, .pendingCompliance,
             .resolved, .closed, .cancelled, .unknown:
            return false
        }
    }

    /// Le dossier est-il clos ?
    public var isTerminal: Bool {
        switch self {
        case .closed, .cancelled: return true
        default:                  return false
        }
    }
}

/// Refuse toute ouverture de dossier.
///
/// Le défaut ne fabrique pas de numéro de dossier : un numéro affiché sans
/// dossier derrière fait attendre une réponse qui ne viendra jamais.
public struct ClosedSupportCaseOpener: SupportCaseOpening {

    public init() {}

    public func context(for reference: FinancialReference) async -> Result<SupportContextPackage, FinanceError> {
        .failure(.capabilityUnavailable)
    }

    public func open(contextID: String, messageText: String,
                     idempotency: IdempotencyContext) async -> Result<SupportCase, FinanceError> {
        .failure(.capabilityUnavailable)
    }
}
