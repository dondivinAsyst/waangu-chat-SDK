//
//  SchemaVersioning.swift
//  CoreKit
//
//  Versionnement des contrats — Bloc 6, niveau 6 (§13, §25).
//

import Foundation

/// Un objet dont le schéma porte sa version.
///
/// Le niveau 6 exige que chaque contrat déclare son schéma et que la
/// compatibilité soit vérifiable. Sans version, deux questions restent sans
/// réponse : ce client sait-il lire cet objet, et ce qu'il en comprend est-il
/// complet ?
///
/// **La version voyage avec l'objet, jamais à côté.** Une version tenue dans un
/// en-tête HTTP ou déduite d'un chemin d'API se perd dès que l'objet est mis en
/// cache, journalisé, ou rejoué depuis une file d'attente.
public protocol SchemaVersioned {

    /// Version du schéma que **ce client** sait lire.
    static var currentSchemaVersion: SchemaVersion { get }

    /// Version portée par **cette instance**, telle que le backend l'a émise.
    var schemaVersion: SchemaVersion { get }
}

/// Ce qu'un client peut faire d'un objet reçu.
public enum SchemaCompatibility: Sendable, Equatable {

    /// Même majeure, mineure identique ou inférieure : lecture complète.
    case fullyCompatible

    /// Même majeure, mineure **supérieure** : l'objet porte des champs que ce
    /// client ignore. Lisible, mais incomplet.
    ///
    /// Acceptable en lecture, **jamais en écriture** : réécrire un objet dont
    /// on ne comprend pas tous les champs les efface silencieusement.
    case forwardCompatible(unknownFieldsPossible: Bool)

    /// Majeure différente. **Rien n'est lisible.**
    case incompatible(expected: SchemaVersion, received: SchemaVersion)

    /// L'objet peut être lu.
    public var permitsRead: Bool {
        if case .incompatible = self { return false }
        return true
    }

    /// L'objet peut être renvoyé au backend après modification.
    ///
    /// Plus strict que la lecture, et délibérément : un client qui relit et
    /// réécrit un objet plus récent que lui perd les champs qu'il n'a pas
    /// décodés.
    public var permitsWrite: Bool { self == .fullyCompatible }
}

public extension SchemaVersion {

    /// Règle de compatibilité, exposée sans instance pour être testable.
    ///
    /// Plus fine qu'``isReadable(by:)``, qui répond par oui ou non. Le §25
    /// demande de distinguer « lisible complètement » de « lisible avec des
    /// champs ignorés » : la seconde autorise la lecture mais **interdit la
    /// réécriture**, et un booléen ne peut pas porter cette nuance.
    static func compatibility(
        of received: SchemaVersion,
        against supported: SchemaVersion
    ) -> SchemaCompatibility {
        guard received.major == supported.major else {
            return .incompatible(expected: supported, received: received)
        }
        if received.minor > supported.minor {
            return .forwardCompatible(unknownFieldsPossible: true)
        }
        return .fullyCompatible
    }
}

public extension SchemaVersioned {

    /// Compare la version reçue à celle que ce client sait lire.
    var compatibility: SchemaCompatibility {
        SchemaVersion.compatibility(of: schemaVersion, against: Self.currentSchemaVersion)
    }
}

// MARK: - Enveloppe à charge typée (§16)

/// Une ``EventEnvelope`` accompagnée de sa charge typée.
///
/// Le §16 décrit un `WaanguEventEnvelope<T>` portant toutes les métadonnées.
/// `EventEnvelope` les porte **déjà** et est utilisée par le Bloc 4 : en
/// refaire une seconde ferait diverger les deux au premier champ ajouté.
///
/// Cette enveloppe **compose** l'existante plutôt que de la remplacer. Elle
/// ajoute la seule chose qui manquait — une charge typée — et laisse les
/// métadonnées à leur unique source.
public struct TypedEventEnvelope<Payload: Codable & Sendable>: Codable, Sendable {

    public let metadata: EventEnvelope
    public let payload: Payload

    /// Identifiant de trace distribuée. Absent d'``EventEnvelope`` parce que le
    /// Bloc 4 n'en avait pas besoin ; exigé par le §23 pour l'observabilité.
    public let traceID: String?

    /// Clé d'idempotence de l'opération qui a produit l'événement. Relie un
    /// événement à la requête qui l'a causé, sans passer par la corrélation —
    /// qui, elle, regroupe plusieurs requêtes.
    public let idempotencyKey: String?

    public init(metadata: EventEnvelope, payload: Payload,
                traceID: String? = nil, idempotencyKey: String? = nil) {
        self.metadata = metadata
        self.payload = payload
        self.traceID = traceID
        self.idempotencyKey = idempotencyKey
    }

    /// Compatibilité de l'**enveloppe** avec ce client.
    ///
    /// Ne dit rien de la charge : c'est au consommateur de vérifier la sienne,
    /// et le nom de la méthode le rappelle.
    public func envelopeCompatibility(with supported: SchemaVersion) -> SchemaCompatibility {
        SchemaVersion.compatibility(of: metadata.schemaVersion, against: supported)
    }
}

// MARK: - Types d'événements (§16)

/// Les noms d'événements du Bloc 6.
///
/// Des constantes plutôt que des chaînes libres : une faute de frappe dans un
/// nom d'événement produit un abonnement qui ne reçoit jamais rien, et ce
/// silence ne se distingue pas d'une absence d'activité.
public enum FinancialEventType {

    public static let merchantVerified            = "merchant.verified"
    public static let merchantSuspended           = "merchant.suspended"
    public static let merchantCapabilitiesUpdated = "merchant.capabilities.updated"

    public static let invoiceIssued    = "invoice.issued"
    public static let invoiceExpired   = "invoice.expired"
    public static let invoiceCancelled = "invoice.cancelled"
    public static let invoicePaid      = "invoice.paid"

    public static let paymentIntentCreated = "payment.intent.created"
    public static let paymentSubmitted     = "payment.submitted"
    public static let paymentAuthorized    = "payment.authorized"
    public static let paymentProcessing    = "payment.processing"
    public static let paymentPending       = "payment.pending"
    public static let paymentConfirmed     = "payment.confirmed"
    public static let paymentFailed        = "payment.failed"
    public static let paymentReversed      = "payment.reversed"
    public static let paymentReceiptIssued = "payment.receipt.issued"

    public static let refundCreated    = "refund.created"
    public static let refundProcessing = "refund.processing"
    public static let refundConfirmed  = "refund.confirmed"
    public static let refundFailed     = "refund.failed"

    public static let cardIssued    = "card.issued"
    public static let cardActivated = "card.activated"
    public static let cardFrozen    = "card.frozen"
    public static let cardUnfrozen  = "card.unfrozen"
    public static let cardReplaced  = "card.replaced"

    public static let cardTransactionAuthorized = "card.transaction.authorized"
    public static let cardTransactionCaptured   = "card.transaction.captured"
    public static let cardTransactionReversed   = "card.transaction.reversed"
    public static let cardTransactionRefunded   = "card.transaction.refunded"

    public static let disputeOpened      = "dispute.opened"
    public static let disputeUpdated     = "dispute.updated"
    public static let chargebackOpened   = "chargeback.opened"
    public static let chargebackResolved = "chargeback.resolved"

    public static let splitCreated              = "split.created"
    public static let splitUpdated              = "split.updated"
    public static let splitContributionRequested = "split.contribution.requested"
    public static let splitContributionPaid     = "split.contribution.paid"
    public static let splitContributionRefused  = "split.contribution.refused"
    public static let splitClosed               = "split.closed"

    public static let collectionCreated             = "collection.created"
    public static let collectionSuspended           = "collection.suspended"
    public static let collectionContributionCreated = "collection.contribution.created"
    public static let collectionDisbursementCreated = "collection.disbursement.created"
    public static let collectionRefunded            = "collection.refunded"

    public static let nativeObjectUpdated = "native.object.updated"

    public static let reconciliationOpened   = "reconciliation.opened"
    public static let reconciliationResolved = "reconciliation.resolved"

    public static let supportCaseCreated = "support.case.created"
}
