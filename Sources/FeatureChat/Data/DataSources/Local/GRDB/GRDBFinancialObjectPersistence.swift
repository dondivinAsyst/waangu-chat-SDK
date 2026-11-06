//
//  GRDBFinancialObjectPersistence.swift
//  FeatureChat
//
//  Persistance des objets financiers dans la base du chat — un compte par instance.
//

import Foundation
import WaanguCoreKit

/// ``FinancialObjectPersisting`` sur la base GRDB du chat.
///
/// Une instance sert **un seul compte**, fixé à la construction : l'aiguillage
/// vers le compte courant reste à l'AppTarget, seul à le connaître. Chaque
/// lecture et chaque suppression filtrent sur ce compte.
///
/// Le contrat ne lève pas : un échec de stockage ne doit pas faire échouer un
/// paiement, et une lecture ratée se répare par une réconciliation serveur.
/// Les échecs sont donc journalisés ici plutôt que propagés.
public actor GRDBFinancialObjectPersistence: FinancialObjectPersisting {

    private let store: any DatabaseRepositoryProtocol
    private let accountID: String

    public init(store: any DatabaseRepositoryProtocol, accountID: String) {
        self.store = store
        self.accountID = accountID
    }

    // MARK: - Contrat

    public func load() async -> [PersistedFinancialObject] {
        do {
            return try await store.fetch(FinancialObjectModel.self, query: accountQuery)
                .map(\.persisted)
        } catch {
            NSLog("[Finance] lecture des objets financiers impossible : \(error.localizedDescription)")
            return []
        }
    }

    public func save(_ object: PersistedFinancialObject) async {
        do {
            try await write(object)
        } catch {
            // L'état mémoire reste juste ; la prochaine lecture serveur le
            // rétablira. Même règle que la persistance fichier.
            NSLog("[Finance] écriture d'un objet financier impossible : \(error.localizedDescription)")
        }
    }

    public func remove(type: String, id: String) async {
        do {
            try await store.delete(
                FinancialObjectModel.self,
                id: FinancialObjectModel.rowID(accountID: accountID, type: type, id: id)
            )
        } catch {
            NSLog("[Finance] suppression d'un objet financier impossible : \(error.localizedDescription)")
        }
    }

    public func clear() async {
        do {
            try await store.deleteAll(FinancialObjectModel.self, query: accountQuery)
        } catch {
            NSLog("[Finance] purge des objets financiers impossible : \(error.localizedDescription)")
        }
    }

    // MARK: - Import

    /// Enregistre des objets venus d'un autre stockage, **en levant** au premier
    /// échec.
    ///
    /// Pour l'import du fichier JSON historique : l'appelant ne supprime sa
    /// source que si tout est arrivé. `save` avale l'erreur, et un import qui
    /// l'utiliserait effacerait le fichier après une écriture ratée — perdant
    /// précisément les opérations tuées en vol que ce stockage doit reprendre.
    public func importObjects(_ objects: [PersistedFinancialObject]) async throws {
        for object in objects {
            try await write(object)
        }
    }

    // MARK: - Écriture

    private func write(_ object: PersistedFinancialObject) async throws {
        let rowID = FinancialObjectModel.rowID(accountID: accountID, type: object.type, id: object.id)

        // Ne jamais reculer : une écriture concurrente plus ancienne écraserait
        // une révision plus récente déjà retenue. L'acteur sérialise la lecture
        // et l'écriture pour ce compte.
        if let existing = try await store.fetchOne(FinancialObjectModel.self, id: rowID),
           existing.version > object.version {
            return
        }

        try await store.save(FinancialObjectModel(accountID: accountID, object: object))
    }

    private var accountQuery: QuerySpec {
        QuerySpec(filter: FilterSpec("account_id = %@", .string(accountID)))
    }
}
