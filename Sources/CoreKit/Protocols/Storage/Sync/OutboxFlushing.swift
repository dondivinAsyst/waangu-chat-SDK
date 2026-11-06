// MARK: - OutboxFlushing.swift
//
// Module  : CoreKit
// Path    : CoreKit/Sources/Sync

import Foundation

// MARK: - Outbox Flushing Protocol

public protocol OutboxFlushing<Item>: Sendable {
    associatedtype Item: OutboxItemProtocol

    func enqueue(_ item: Item) async throws

    @discardableResult
    func flush() async -> [OutboxFlushResult]

    var pendingCount: Int { get async }
}

// MARK: - Outbox Item Protocol

public protocol OutboxItemProtocol: Codable, Sendable, Identifiable where ID == String {
    associatedtype ActionType: RawRepresentable<String> & Codable & Sendable
    
    var id: String { get }

    /// Type d'action (ex: "send_message", "reaction", "read_receipt").
    var actionType: ActionType { get }

    /// Contenu sérialisé de l'action — envoyé au serveur lors du flush.
    var payload: Data { get }

    /// Clé d'idempotence — déduplique côté client ET côté serveur.
    ///
    /// Deux items avec la même clé = la même action métier.
    /// L'outbox refuse l'enqueue si un item pending a déjà cette clé.
    /// Le serveur déduplique si la même clé arrive deux fois.
    ///
    /// Convention : `"{actionType}:{referenceId}"` ou un UUID déterministe.
    /// ```swift
    /// // L'utilisateur tape 3 fois "envoyer" sur le même message :
    /// idempotencyKey = "send_message:msg-abc123"
    /// → un seul item dans l'outbox, un seul message côté serveur
    /// ```
    var idempotencyKey: String { get }

    /// Date de création — détermine l'ordre d'envoi (FIFO).
    var createdAt: Date { get }

    /// Statut de synchronisation courant.
    var syncStatus: OutboxSyncStatus { get set }

    /// Nombre de tentatives d'envoi échouées.
    var retryCount: Int { get set }

    /// Dernière erreur rencontrée (pour le debugging).
    var lastError: String? { get set }
}

// MARK: - Outbox Sync Status

public enum OutboxSyncStatus: String, Sendable, Codable {
    case pending
    case syncing
    case synced
    case failed
}

// MARK: - Outbox Flush Result

public struct OutboxFlushResult: Sendable {
    public let localId: String
    public let success: Bool
    public let serverId: String?
    public let serverTimestamp: Date?
    public let error: String?
    public let errorCode: String?

    /// Décision du serveur : l'erreur est-elle récupérable ?
    /// `nil` si le serveur ne fournit pas cette info (vieux backend).
    public let retryable: Bool?

    /// Le serveur décide en priorité. Fallback client si le serveur ne dit rien.
    public var isRetryable: Bool {
        // 1. Le serveur a dit explicitement
        if let serverDecision = retryable { return serverDecision }
        // 2. Succès = pas de retry
        guard !success else { return false }
        // 3. Fallback client — codes permanents connus
        guard let code = errorCode else { return true }
        let permanentCodes: Set<String> = [
            "INVALID_PAYLOAD", "DUPLICATE", "FORBIDDEN", "NOT_FOUND"
        ]
        return !permanentCodes.contains(code)
    }

    public init(
        localId: String,
        success: Bool,
        serverId: String? = nil,
        serverTimestamp: Date? = nil,
        error: String? = nil,
        errorCode: String? = nil,
        retryable: Bool? = nil
    ) {
        self.localId = localId
        self.success = success
        self.serverId = serverId
        self.serverTimestamp = serverTimestamp
        self.error = error
        self.errorCode = errorCode
        self.retryable = retryable
    }
}
