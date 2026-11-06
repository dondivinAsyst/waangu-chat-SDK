//
//  ChatFinanceOutbox.swift
//  FeatureChat
//
//  File d'attente des actions financières — tâches 8.1 à 8.5.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §7.

import Foundation
import WaanguCoreKit

// MARK: - Politique offline

/// Ce qui est permis hors ligne.
///
/// Table explicite plutôt que règle générale : « prévoir l'offline » ne dit pas
/// si accepter une demande d'argent est queueable. Ici chaque action a une réponse
/// unique, et une action non listée est refusée par défaut.
public enum FinanceOfflinePolicy {

    /// `Codable` : l'action est persistée avec l'item de file, qui doit survivre
    /// à un kill d'application — c'est tout l'intérêt d'une file offline.
    public enum Action: String, Codable, Sendable, CaseIterable {
        case readCard
        case readHistory
        case draftMoneyRequest
        case createIntent
        case confirmPayment
        case acceptMoneyRequest
        case changeBeneficiary
        case cancelOwnRequest
    }

    public enum Verdict: Sendable, Equatable {
        /// Autorisé, sur données locales.
        case allowedOffline
        /// Interdit hors ligne — doit être réévalué en ligne.
        case requiresNetwork
        /// Mis en file : sans effet monétaire et idempotent.
        case queueable
    }

    public static func verdict(for action: Action) -> Verdict {
        switch action {
        case .readCard, .readHistory:
            return .allowedOffline

        case .draftMoneyRequest:
            // Un brouillon reste local et n'est transmis à personne.
            return .allowedOffline

        case .createIntent:
            // Exige un devis et une décision Compliance, tous deux en ligne.
            return .requiresNetwork

        case .confirmPayment:
            // Jamais mis en file. Une confirmation différée s'exécuterait sur un
            // montant, un taux et un bénéficiaire qui ont pu changer entre-temps.
            return .requiresNetwork

        case .acceptMoneyRequest:
            // Montant et bénéficiaire doivent être revalidés avant tout débit.
            return .requiresNetwork

        case .changeBeneficiary:
            // Vecteur de fraude direct : la cible d'un paiement ne se modifie pas
            // hors de portée du contrôle serveur.
            return .requiresNetwork

        case .cancelOwnRequest:
            // Idempotent et sans effet monétaire : annuler deux fois équivaut à
            // annuler une fois.
            return .queueable
        }
    }
}

// MARK: - Item de file

/// Action financière en attente de réseau.
///
/// **File distincte de `ChatOutboxItem`.** Les sémantiques diffèrent : l'outbox
/// du chat republie jusqu'à acquittement, ce qui est correct pour un message et
/// catastrophique pour un paiement. Ici rien ne se republie sans que la clé
/// d'idempotence d'origine soit vérifiée, et un item ambigu part en
/// réconciliation plutôt qu'en republication.
public struct ChatFinanceOutboxItem: Codable, Sendable, Equatable {

    public let id: String
    public let action: FinanceOfflinePolicy.Action

    /// Objet visé.
    public let reference: FinancialReference

    /// Contexte d'idempotence, **écrit une fois à la création**.
    ///
    /// Ne porte pas de `var` : la clé ne peut pas être réécrite après coup, ce qui
    /// rend la faute impossible à commettre plutôt qu'interdite par convention.
    public let idempotency: IdempotencyContext

    public let createdAt: Date

    /// Tentatives déjà effectuées. N'influence jamais la clé.
    public let attemptCount: Int

    public init(
        id: String = UUID().lowercasedString,
        action: FinanceOfflinePolicy.Action,
        reference: FinancialReference,
        idempotency: IdempotencyContext,
        createdAt: Date = Date(),
        attemptCount: Int = 0
    ) {
        self.id = id
        self.action = action
        self.reference = reference
        self.idempotency = idempotency
        self.createdAt = createdAt
        self.attemptCount = attemptCount
    }

    /// Item pour la tentative suivante. La clé est conservée à l'identique.
    public func nextAttempt() -> ChatFinanceOutboxItem {
        ChatFinanceOutboxItem(
            id: id,
            action: action,
            reference: reference,
            idempotency: idempotency.nextAttempt(),
            createdAt: createdAt,
            attemptCount: attemptCount + 1
        )
    }
}

// MARK: - File

/// File des actions financières différables.
///
/// N'accepte que les actions dont la politique dit `.queueable`. Une action
/// `.requiresNetwork` est refusée à l'enfilement, pas au défilement : accepter
/// puis échouer plus tard laisserait croire à l'utilisateur que son opération est
/// partie.
///
/// **Persistée par compte** (lot 2.3) : chaque action est écrite avant d'être
/// acceptée en mémoire, restaurée à la connexion par ``restore()``, et retirée
/// du disque une fois acquittée. Sans stockage injecté, la file reste en
/// mémoire — le comportement d'origine, conservé pour les tests.
public actor ChatFinanceOutbox {

    private var items: [ChatFinanceOutboxItem] = []
    private let preserver: any IdempotencyKeyPreserving
    private let logger: any AppLoggerProtocol
    private let storage: (any ChatFinanceOutboxStoring)?
    private let currentAccountID: @Sendable () -> String?

    /// Un seul flush à la fois. L'acteur est réentrant à chaque `await` : sans
    /// ce verrou, un retour réseau pendant un flush relancerait l'envoi des
    /// mêmes items — deux fois la même action, même sous la même clé.
    private var isFlushing = false

    public init(
        preserver: any IdempotencyKeyPreserving,
        logger: any AppLoggerProtocol
    ) {
        self.init(preserver: preserver, logger: logger, storage: nil, currentAccountID: { nil })
    }

    init(
        preserver: any IdempotencyKeyPreserving,
        logger: any AppLoggerProtocol,
        storage: (any ChatFinanceOutboxStoring)?,
        currentAccountID: @escaping @Sendable () -> String?
    ) {
        self.preserver = preserver
        self.logger = logger
        self.storage = storage
        self.currentAccountID = currentAccountID
    }

    public var pendingCount: Int { items.count }

    /// Enfile une action différable.
    ///
    /// - Throws: `FinanceError.capabilityUnavailable` si l'action n'est pas
    ///   queueable. Le message est volontairement sec : c'est une erreur de
    ///   programmation, pas une condition d'exécution.
    public func enqueue(_ item: ChatFinanceOutboxItem) async throws {
        guard FinanceOfflinePolicy.verdict(for: item.action) == .queueable else {
            await logger.log(
                "Action financière non différable refusée: \(item.action.rawValue)",
                level: .error
            )
            throw FinanceError.capabilityUnavailable
        }

        // Enregistre la clé dès l'enfilement : si l'application est tuée avant le
        // premier envoi, la clé survit et la reprise ne fabrique pas d'opération
        // nouvelle.
        try await preserver.register(operationID: item.id, context: item.idempotency)

        // Sur disque avant la mémoire : un kill entre les deux laisse une action
        // restaurable, jamais une action acceptée puis oubliée.
        await persist(item)
        items.append(item)
    }

    /// Recharge les actions du compte courant — à appeler à la connexion.
    ///
    /// Ne restaure que ce que la politique autorise **aujourd'hui** : une action
    /// devenue non différable depuis son enfilement est retirée du disque, pas
    /// rejouée. Chaque action repart sous sa clé d'origine, que `flush` vérifie
    /// auprès du registre avant tout envoi.
    public func restore() async {
        guard let storage, let account = currentAccountID() else { return }

        let stored: [ChatFinanceOutboxItem]
        do {
            stored = try await storage.load(accountID: account)
        } catch {
            await logger.log(
                "File financière illisible — rien à restaurer : \(error.localizedDescription)",
                level: .warning
            )
            return
        }

        let known = Set(items.map(\.id))
        for item in stored where !known.contains(item.id) {
            guard FinanceOfflinePolicy.verdict(for: item.action) == .queueable else {
                await logger.log(
                    "Action financière non différable écartée à la restauration: \(item.action.rawValue)",
                    level: .error
                )
                await unpersist(item.id)
                continue
            }
            items.append(item)
        }
    }

    /// Vide la file en préservant la clé de chaque item.
    ///
    /// - Parameter send: exécute l'action. Retourne `true` si elle est acquittée.
    public func flush(
        send: @Sendable (ChatFinanceOutboxItem) async -> Bool
    ) async {
        guard !items.isEmpty, !isFlushing else { return }
        isFlushing = true
        defer { isFlushing = false }

        let batch = items
        var remaining: [ChatFinanceOutboxItem] = []

        for item in batch {
            let attempt = item.nextAttempt()

            // Vérifie que le retry porte bien la clé d'origine. Une divergence est
            // une faute de programmation : mieux vaut ne pas envoyer.
            do {
                try await preserver.assertSameKey(
                    operationID: item.id,
                    providedKey: attempt.idempotency.key
                )
            } catch {
                await logger.log(
                    "Clé d'idempotence divergente — envoi abandonné pour \(item.action.rawValue)",
                    level: .critical
                )
                // Écartée de la mémoire, donc aussi du disque : sinon chaque
                // restauration la ramènerait pour l'écarter de nouveau.
                await unpersist(item.id)
                continue
            }

            if await send(attempt) {
                await preserver.release(operationID: item.id)
                await unpersist(item.id)
            } else {
                // Le compteur a bougé, la clé non : c'est cette tentative-là
                // qu'une restauration doit reprendre.
                await persist(attempt)
                remaining.append(attempt)
            }
        }

        // Les actions enfilées pendant les envois ne sont pas dans `batch` :
        // `items = remaining` seul les aurait perdues.
        let processed = Set(batch.map(\.id))
        items = remaining + items.filter { !processed.contains($0.id) }
    }

    /// Vide la file en mémoire.
    ///
    /// - Parameter accountID: à renseigner **à la déconnexion** seulement, avec
    ///   le compte qui part : ses actions sont alors effacées du disque et leurs
    ///   clés libérées. Sans lui — la connexion, qui réinitialise aussi l'état —
    ///   seule la mémoire est vidée : le disque porte les actions que
    ///   ``restore()`` doit reprendre, et libérer leurs clés les rendrait
    ///   impossibles à renvoyer.
    public func clear(erasingPersistenceOf accountID: String? = nil) async {
        defer { items.removeAll() }
        guard let accountID else { return }

        for item in items {
            await preserver.release(operationID: item.id)
        }
        do {
            try await storage?.clear(accountID: accountID)
        } catch {
            await logger.log(
                "Purge de la file financière impossible : \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    // MARK: - Stockage

    /// Échec journalisé, pas propagé : l'action reste valable en mémoire, et
    /// faire échouer l'annulation pour un disque plein serait pire.
    private func persist(_ item: ChatFinanceOutboxItem) async {
        guard let storage, let account = currentAccountID() else { return }
        do {
            try await storage.save(item, accountID: account)
        } catch {
            await logger.log(
                "Action financière non persistée (\(item.action.rawValue)) : \(error.localizedDescription)",
                level: .warning
            )
        }
    }

    private func unpersist(_ id: String) async {
        guard let storage else { return }
        do {
            try await storage.remove(id: id)
        } catch {
            await logger.log(
                "Action financière non retirée du disque : \(error.localizedDescription)",
                level: .warning
            )
        }
    }
}
