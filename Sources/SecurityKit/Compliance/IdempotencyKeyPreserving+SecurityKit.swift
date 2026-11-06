//
//  IdempotencyKeyPreserving+SecurityKit.swift
//  SecurityKit
//
//  Conformité de l'existant au contrat CoreKit — tâche 3.1.
//
//  Aucune logique nouvelle : `IdempotencyKeyPreserver` fait déjà le bon travail,
//  il n'était simplement joignable par aucune feature. Voir §1.5 de la spec.

import Foundation
import WaanguCoreKit

/// Rend `IdempotencyKeyPreserver` utilisable depuis les features, qui ne
/// dépendent que de CoreKit.
///
/// Adaptateur et non `extension IdempotencyKeyPreserver: IdempotencyKeyPreserving`,
/// pour deux raisons : le contrat CoreKit stocke le `IdempotencyContext` complet
/// là où l'acteur historique ne retient qu'une chaîne, et il expose `release`,
/// que l'acteur n'a pas.
public actor SecurityKitIdempotencyPreserver: IdempotencyKeyPreserving {

    private let keychain: any KeychainStoreProtocol
    private let logger: AppLogger

    /// Identifiant du compte courant, relu à chaque accès.
    ///
    /// Fourni par fermeture plutôt que capturé : le compte change en cours de
    /// processus, et une valeur figée à la construction ferait travailler le
    /// compte suivant dans l'espace de noms du précédent.
    private let currentUserID: @Sendable () -> String?

    /// Contextes en cours, chargés depuis le trousseau au premier accès.
    private var contexts: [String: IdempotencyContext] = [:]

    /// Espace de noms actuellement chargé en mémoire, ou `nil` si rien ne l'est.
    ///
    /// Remplace le booléen `didLoad` : savoir *que* l'on a chargé ne suffit pas,
    /// il faut savoir *pour qui*. Sans cela, un changement de compte continue de
    /// servir les contextes du compte précédent jusqu'au prochain lancement.
    private var loadedNamespace: String?

    private static let keychainKeyPrefix = "com.waangu.finance.idempotency-contexts"

    /// Espace de noms des clés du compte donné.
    ///
    /// Le trousseau survit à la déconnexion. Un espace de noms unique par compte
    /// est ce qui empêche l'identifiant d'opération de l'utilisateur B de
    /// retrouver la clé enregistrée par l'utilisateur A sur le même appareil —
    /// collision qui produit soit un refus injustifié, soit un rejeu.
    private static func keychainKey(for namespace: String) -> String {
        "\(keychainKeyPrefix).\(namespace)"
    }

    /// Espace de noms hors session.
    ///
    /// Aucune opération financière n'est atteignable sans session — les capacités
    /// sont fermées par défaut. Cet espace n'est donc jamais partagé entre deux
    /// comptes : il n'en sert aucun.
    private static let anonymousNamespace = "anonymous"

    /// Au-delà, la clé n'est plus garantie idempotente côté backend.
    ///
    /// **BACKEND CONTRACT REQUIRED** — contrat #4 : durée réelle de rétention.
    /// 24 h est un pari conservateur ; si le backend retient moins longtemps, une
    /// clé considérée ici comme valide sera traitée là-bas comme neuve.
    private let retentionWindow: TimeInterval = 86_400

    public init(
        keychain: any KeychainStoreProtocol,
        logger: AppLogger,
        currentUserID: @escaping @Sendable () -> String?
    ) {
        self.keychain = keychain
        self.logger = logger
        self.currentUserID = currentUserID
    }

    private func namespace() -> String {
        guard let id = currentUserID(), !id.isEmpty else { return Self.anonymousNamespace }
        return id
    }

    // MARK: - IdempotencyKeyPreserving

    public func register(operationID: String, context: IdempotencyContext) async throws {
        await ensureLoaded()

        if let existing = contexts[operationID] {
            guard existing.key == context.key else {
                // Réenregistrer sous une autre clé effacerait la clé d'origine,
                // donc autoriserait une seconde soumission de la même opération.
                await recordViolation("already_registered", operationID: operationID)
                throw IdempotencyViolation.alreadyRegistered(operationID: operationID)
            }
            return // idempotent : réenregistrer la même clé ne fait rien
        }

        contexts[operationID] = context
        await persist()
    }

    public func context(for operationID: String) async -> IdempotencyContext? {
        await ensureLoaded()
        return contexts[operationID]
    }

    public func assertSameKey(operationID: String, providedKey: String) async throws {
        await ensureLoaded()

        guard let stored = contexts[operationID] else {
            // Opération inconnue : l'appelant doit créer un contexte, pas rejouer.
            throw IdempotencyViolation.keyMismatch(operationID: operationID)
        }

        guard stored.key == providedKey else {
            await recordViolation("key_mismatch", operationID: operationID)
            throw IdempotencyViolation.keyMismatch(operationID: operationID)
        }

        guard stored.age() < retentionWindow else {
            // Hors fenêtre : le backend a pu oublier la première tentative, donc
            // un rejeu produirait une seconde opération. Il faut relire, pas retenter.
            await recordViolation("key_expired", operationID: operationID)
            throw IdempotencyViolation.keyExpired(operationID: operationID)
        }
    }

    public func release(operationID: String) async {
        await ensureLoaded()
        contexts.removeValue(forKey: operationID)
        await persist()
    }

    public func purge(userID: String) async {
        let target = userID.isEmpty ? Self.anonymousNamespace : userID

        // Vider la mémoire uniquement si c'est bien ce compte qui y est chargé :
        // purger le compte sortant ne doit pas effacer les clés du compte déjà
        // entrant si les deux événements se croisent.
        if loadedNamespace == target {
            contexts.removeAll()
            loadedNamespace = nil
        }

        do {
            try await keychain.remove(forKey: Self.keychainKey(for: target))
        } catch {
            // Échec de purge : les clés du compte sortant restent dans le
            // trousseau. C'est le cas de collision inter-comptes que cette
            // méthode existe pour empêcher — il doit être visible.
            await logger.log(
                "Purge des clés d'idempotence impossible — collision inter-comptes possible",
                level: .critical
            )
        }
    }

    // MARK: - Persistance

    private func ensureLoaded() async {
        let current = namespace()

        // Déjà chargé pour ce compte : rien à faire. Chargé pour un autre :
        // tout relire, sans conserver la moindre entrée du précédent.
        if loadedNamespace == current { return }

        loadedNamespace = current
        contexts = [:]

        guard let stored = try? await keychain.getCodable(
            [String: IdempotencyContext].self,
            forKey: Self.keychainKey(for: current)
        ) else { return }

        // Purge à la lecture des clés hors fenêtre : elles ne protègent plus rien
        // et leur présence ferait échouer `assertSameKey` avec `keyExpired` au
        // lieu de laisser l'appelant repartir proprement.
        contexts = stored.filter { $0.value.age() < retentionWindow }
    }

    private func persist() async {
        let target = loadedNamespace ?? namespace()
        do {
            try await keychain.saveCodable(contexts, forKey: Self.keychainKey(for: target))
        } catch {
            // Échec de persistance : la protection retombe au niveau mémoire.
            // Le signaler fort — c'est le cas où un kill d'application redevient
            // dangereux.
            await logger.log(
                "Persistance des clés d'idempotence impossible — protection dégradée",
                level: .critical
            )
        }
    }

    private func recordViolation(_ kind: String, operationID: String) async {
        await AuditBreadcrumb.shared.recordSecurity(
            action: .securityViolation,
            userId: nil,
            metadata: ["violation": "idempotency_\(kind)", "operationId": operationID]
        )
    }
}
