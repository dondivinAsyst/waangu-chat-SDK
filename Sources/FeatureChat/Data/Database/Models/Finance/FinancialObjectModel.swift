//
//  FinancialObjectModel.swift
//  FeatureChat
//
//  Ligne GRDB d'un objet financier connu — remplace le fichier JSON par compte.
//

import Foundation
import WaanguCoreKit

/// Ce que la base retient d'un objet financier, **pour un compte**.
///
/// Même contenu que ``PersistedFinancialObject`` et pour la même raison :
/// identité, révision, statut, instant de lecture — jamais le montant ni la
/// contrepartie. Une ligne relue sert à savoir **qu'il faut requêter**, pas à
/// afficher une carte : un montant relu du disque est faux dès que le backend a
/// bougé.
///
/// `accountId` est une colonne réelle et chaque requête filtre dessus. Le
/// fichier par compte rendait la fuite entre comptes impossible par
/// construction ; une table partagée ne la rend impossible que par ce filtre.
public struct FinancialObjectModel: Storable {

    public static let namespace = "chat"
    public static let schemaVersion = 1

    /// `status` indexé : les objets non finaux sont ceux qu'on reprend au
    /// lancement, et ceux qu'un écran « en attente » voudra lister.
    public static let indexedFields = ["accountId", "objectType", "status"]

    /// Compte et identité de l'objet — voir ``rowID(accountID:type:id:)``.
    public let id: String
    public let accountId: String
    public let objectType: String
    public let objectId: String
    public let version: Int
    public let status: String

    /// Horodatage **serveur** de la dernière lecture, quand il est connu.
    public let lastKnownAt: Date

    public init(accountID: String, object: PersistedFinancialObject) {
        self.id = Self.rowID(accountID: accountID, type: object.type, id: object.id)
        self.accountId = accountID
        self.objectType = object.type
        self.objectId = object.id
        self.version = object.version
        self.status = object.status
        self.lastKnownAt = object.lastKnownAt
    }

    /// Clé primaire : le compte **entre dans l'identité**. Deux comptes qui
    /// connaissent le même objet — une demande d'argent entre eux deux sur le
    /// même appareil — ont chacun leur ligne, et l'un ne peut pas écraser la
    /// révision de l'autre.
    public static func rowID(accountID: String, type: String, id: String) -> String {
        "\(accountID)|\(PersistedFinancialObject.identityKey(type: type, id: id))"
    }

    public var persisted: PersistedFinancialObject {
        PersistedFinancialObject(
            type: objectType,
            id: objectId,
            version: version,
            status: status,
            lastKnownAt: lastKnownAt
        )
    }
}
