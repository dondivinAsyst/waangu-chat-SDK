//
//  AccountScopedFinancialObjectPersistence.swift
//  WaanguChatSDK
//  Moved from the Waangu app target into WaanguChatSDK (SDK plan, step 1.9).
//
//  Branche la persistance des objets financiers sur le compte courant.
//

import Foundation
import WaanguCoreKit
import WaanguFeatureChat

/// Aiguille chaque lecture et écriture vers les lignes **du compte courant**
/// dans la base du chat.
///
/// `FileFinancialObjectPersistence` existait, testée, mais n'était construite
/// nulle part : elle exige l'identifiant du compte à sa construction, alors que
/// le graphe de dépendances est assemblé avant la connexion. Le magasin financier
/// vivait donc en mémoire seule, et une opération tuée en vol ne laissait aucune
/// trace à reprendre au lancement suivant.
///
/// Le stockage est désormais la base GRDB du chat (`FinancialObjectModel`),
/// comme le reste de la feature. Le fichier JSON par compte n'est plus relu
/// que pour être importé une fois, puis supprimé.
///
/// Le compte est relu à chaque appel, comme pour le gardien des clés
/// d'idempotence : il change en cours de processus.
public actor AccountScopedFinancialObjectPersistence: FinancialObjectPersisting {

    private let database: any DatabaseRepositoryProtocol
    private let currentAccountID: @Sendable () -> String?

    /// Dossier du fichier JSON historique, pour l'import. `nil` : le dossier
    /// par défaut de `FileFinancialObjectPersistence`.
    private let legacyDirectory: URL?

    private var stores: [String: GRDBFinancialObjectPersistence] = [:]

    /// Comptes dont le fichier historique a été importé dans ce processus.
    private var importedAccounts: Set<String> = []

    /// Dernier compte servi. Sert à `clear()` : à la déconnexion, la session
    /// courante peut déjà avoir été effacée quand la purge arrive, et il faut
    /// alors vider les lignes du compte qui part — pas aucune.
    private var lastAccountID: String?

    public init(
        database: any DatabaseRepositoryProtocol,
        currentAccountID: @escaping @Sendable () -> String?,
        legacyDirectory: URL? = nil
    ) {
        self.database = database
        self.currentAccountID = currentAccountID
        self.legacyDirectory = legacyDirectory
    }

    public func load() async -> [PersistedFinancialObject] {
        // Hors session : rien à relire, et surtout pas les lignes d'un autre.
        guard let store = await resolve() else { return [] }
        return await store.load()
    }

    public func save(_ object: PersistedFinancialObject) async {
        guard let store = await resolve() else { return }
        await store.save(object)
    }

    public func remove(type: String, id: String) async {
        guard let store = await resolve() else { return }
        await store.remove(type: type, id: id)
    }

    public func clear() async {
        let account = currentAccountID() ?? lastAccountID
        guard let account else { return }
        await store(for: account).clear()
        // Un fichier jamais importé — import raté, ou compte jamais relu depuis
        // la mise à jour — ne doit pas survivre à la déconnexion non plus.
        await FileFinancialObjectPersistence(accountID: account, directory: legacyDirectory).clear()
        importedAccounts.remove(account)
    }

    // MARK: - Aiguillage

    private func resolve() async -> GRDBFinancialObjectPersistence? {
        guard let account = currentAccountID() else { return nil }
        lastAccountID = account
        let store = store(for: account)
        await importLegacyFileIfNeeded(for: account, into: store)
        return store
    }

    private func store(for account: String) -> GRDBFinancialObjectPersistence {
        if let existing = stores[account] { return existing }
        let created = GRDBFinancialObjectPersistence(store: database, accountID: account)
        stores[account] = created
        return created
    }

    // MARK: - Import du fichier historique

    /// Reporte le fichier JSON du compte dans la base, puis le supprime.
    ///
    /// Le fichier n'est supprimé **que si tout a été écrit** : il porte les
    /// opérations tuées en vol, celles que la réconciliation au lancement doit
    /// reprendre. Sur échec, il reste en place et l'import est retenté au
    /// prochain appel. Rejouer l'import est sans risque : même clé de ligne,
    /// et une révision plus ancienne n'écrase jamais une plus récente.
    private func importLegacyFileIfNeeded(
        for account: String,
        into store: GRDBFinancialObjectPersistence
    ) async {
        guard !importedAccounts.contains(account) else { return }

        let legacy = FileFinancialObjectPersistence(accountID: account, directory: legacyDirectory)
        let objects = await legacy.load()

        do {
            try await store.importObjects(objects)
            await legacy.clear()
            importedAccounts.insert(account)
        } catch {
            NSLog("[Finance] import du fichier financier historique reporté : \(error.localizedDescription)")
        }
    }
}
