//
//  FileFinancialObjectPersistence.swift
//  Waangu
//
//  Persistance des objets financiers — lot 2.1 du plan de travail restant.
//  Déplacé de l'AppTarget vers WaanguChatSDK (plan SDK, étape 1.9) : il ne sert plus qu'à
//  importer l'ancien fichier JSON, une fois, dans la base du chat.
//
//  Vit dans l'AppTarget parce que lui seul connaît le compte courant et le
//  stockage : `FeatureChat` ne dépend ni de `StorageKit` ni du système de
//  fichiers, et ne doit pas commencer.
//

import Foundation
import CryptoKit
import WaanguCoreKit

/// Conserve les objets financiers entre deux lancements, **par compte**.
///
/// Ce que la persistance retient est volontairement maigre : type, identifiant,
/// révision, statut et date. De quoi savoir **qu'il faut requêter**, jamais de
/// quoi reconstruire une carte à afficher. Un montant relu du disque et présenté
/// comme courant est un montant faux dès que le backend a bougé.
actor FileFinancialObjectPersistence: FinancialObjectPersisting {

    private let fileURL: URL
    private let accountID: String

    /// Cache mémoire, pour ne pas relire le disque à chaque écriture.
    private var cache: [String: PersistedFinancialObject]?

    /// - Parameter accountID: identifiant du compte connecté. **Entre dans le
    ///   chemin du fichier** : deux comptes sur le même appareil n'écrivent
    ///   jamais dans le même fichier, ce qui rend la fuite entre comptes
    ///   impossible par construction plutôt que par un filtre à la lecture.
    init(accountID: String, directory: URL? = nil) {
        self.accountID = accountID

        let base = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())

        // Le nom de fichier est haché : un identifiant de compte en clair dans
        // l'arborescence se lit dans une sauvegarde iTunes ou un rapport de
        // crash sans qu'aucun code n'ait fui.
        let scoped = base.appendingPathComponent("Finance", isDirectory: true)
        self.fileURL = scoped.appendingPathComponent(
            "objects-\(Self.scopeHash(accountID)).json"
        )
    }

    // MARK: - Contrat

    func load() async -> [PersistedFinancialObject] {
        if let cache { return Array(cache.values) }

        guard let data = try? Data(contentsOf: fileURL) else {
            cache = [:]
            return []
        }

        do {
            let stored = try JSONDecoder().decode([PersistedFinancialObject].self, from: data)
            cache = Dictionary(uniqueKeysWithValues: stored.map { ($0.identityKey, $0) })
            return stored
        } catch {
            // Un fichier illisible — corruption, format d'une version
            // antérieure — ne doit pas empêcher le démarrage. On repart vide :
            // le contenu est de toute façon un pense-bête, et tout sera
            // requêté au serveur.
            cache = [:]
            try? FileManager.default.removeItem(at: fileURL)
            return []
        }
    }

    func save(_ object: PersistedFinancialObject) async {
        // `??` évalue sa droite dans une autoclosure, qui n'admet pas `await`.
        var current: [String: PersistedFinancialObject]
        if let cache {
            current = cache
        } else {
            let loaded = await load()
            current = Dictionary(uniqueKeysWithValues: loaded.map { ($0.identityKey, $0) })
        }

        // Ne jamais reculer sur disque : une écriture concurrente plus ancienne
        // écraserait une révision plus récente déjà retenue.
        if let existing = current[object.identityKey], existing.version > object.version {
            return
        }

        current[object.identityKey] = object
        cache = current
        await flush(current)
    }

    func remove(type: String, id: String) async {
        var current: [String: PersistedFinancialObject]
        if let cache {
            current = cache
        } else {
            let loaded = await load()
            current = Dictionary(uniqueKeysWithValues: loaded.map { ($0.identityKey, $0) })
        }
        guard current.removeValue(forKey: PersistedFinancialObject.identityKey(type: type, id: id)) != nil else {
            return
        }
        cache = current
        await flush(current)
    }

    func clear() async {
        cache = [:]
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Écriture

    private func flush(_ objects: [String: PersistedFinancialObject]) async {
        do {
            let directory = fileURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true
            )

            let data = try JSONEncoder().encode(Array(objects.values))

            // `.completeFileProtection` : illisible tant que l'appareil n'a pas
            // été déverrouillé une fois. Ces données sont des statuts de
            // paiement — elles n'ont aucune raison d'être lisibles par un
            // processus de fond sur un téléphone verrouillé.
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
        } catch {
            // L'échec d'écriture ne casse rien de visible : l'état mémoire
            // reste juste, et la prochaine lecture serveur le rétablira. Ne
            // pas propager évite qu'un disque plein fasse échouer un paiement.
            NSLog("[Finance] persistance indisponible : \(error.localizedDescription)")
        }
    }

    /// Empreinte courte et **stable** du compte, pour le nom de fichier.
    ///
    /// SHA-256 et non `Hasher` : celui-ci est initialisé avec une graine
    /// aléatoire à chaque lancement du processus. Le nom de fichier aurait donc
    /// changé à chaque démarrage, et la restauration n'aurait jamais rien
    /// retrouvé — en laissant croire que la persistance fonctionnait, puisque
    /// l'écriture, elle, réussissait.
    private static func scopeHash(_ value: String) -> String {
        let digest = SHA256.hash(data: Data(value.utf8))
        return digest.compactMap { String(format: "%02x", $0) }
            .joined().prefix(16).description
    }
}
