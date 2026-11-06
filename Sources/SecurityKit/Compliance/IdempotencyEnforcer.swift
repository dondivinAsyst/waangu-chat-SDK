import Foundation
import WaanguCoreKit

/// Enforces idempotency on critical operations
/// Ensures operations can be safely retried without side effects
///
/// **Persistant.** La version précédente conservait son état dans un dictionnaire
/// en mémoire, perdu à la fermeture de l'application — c'est-à-dire précisément
/// dans le scénario qu'elle devait couvrir : une opération soumise, l'application
/// tuée avant la réponse, puis relancée. Au retour, l'enforcer n'avait plus
/// mémoire de l'opération et laissait passer une seconde soumission.
///
/// L'état vit désormais au trousseau, avec le même TTL de 24 h.
public actor IdempotencyEnforcer {
    
    public static let shared = IdempotencyEnforcer()

    /// Cache mémoire, alimenté depuis le trousseau au premier accès.
    private var processedOperations: [String: ProcessedOperation] = [:]
    private var didLoad = false

    private var keychain: (any KeychainStoreProtocol)?

    private let ttl: TimeInterval = 86400 // 24 hours
    private static let keychainKey = "com.waangu.idempotency.processed-operations"
    
    private init() {}

    public struct ProcessedOperation: Codable, Sendable {
        public let operationId: String
        public let result: String
        public let timestamp: Date

        public init(operationId: String, result: String, timestamp: Date) {
            self.operationId = operationId
            self.result = result
            self.timestamp = timestamp
        }
    }

    // MARK: - Configuration

    /// Installe le stockage persistant.
    ///
    /// Sans appel à cette méthode, l'acteur se comporte comme avant — mémoire
    /// seule. Il journalise alors un avertissement plutôt que d'échouer : refuser
    /// de fonctionner casserait des chemins non financiers qui l'utilisent déjà,
    /// alors que le défaut ne devient critique qu'en contexte financier.
    public func configure(keychain: any KeychainStoreProtocol) async {
        self.keychain = keychain
        await load()
    }

    public var isPersistent: Bool { keychain != nil }
    
    /// Marks an operation as critical and requiring idempotency
    public func markCriticalOperation(_ operationId: String) async {
        await ensureLoaded()
        processedOperations[operationId] = ProcessedOperation(
            operationId: operationId,
            result: "PENDING",
            timestamp: Date()
        )
        await persist()
    }
    
    /// Records successful completion of an idempotent operation
    public func recordCompletion(_ operationId: String, result: String) async {
        await ensureLoaded()
        processedOperations[operationId] = ProcessedOperation(
            operationId: operationId,
            result: result,
            timestamp: Date()
        )
        await persist()
    }
    
    /// Checks if operation was already processed
    public func wasProcessed(_ operationId: String) async -> Bool {
        await ensureLoaded()
        guard let operation = processedOperations[operationId] else {
            return false
        }
        return Date().timeIntervalSince(operation.timestamp) < ttl
    }
    
    /// Gets cached result if operation was already processed
    public func getCachedResult(_ operationId: String) async -> String? {
        await ensureLoaded()
        guard let operation = processedOperations[operationId] else {
            return nil
        }
        
        guard Date().timeIntervalSince(operation.timestamp) < ttl else {
            processedOperations.removeValue(forKey: operationId)
            await persist()
            return nil
        }
        
        return operation.result
    }
    
    /// Validates operation is idempotent before execution
    public func validateIdempotency(for operationId: String) async throws {
        if await wasProcessed(operationId) {
            throw IdempotencyError.operationAlreadyProcessed(operationId: operationId)
        }
    }
    
    /// Cleanup expired operations
    public func cleanupExpired() async {
        await ensureLoaded()
        let now = Date()
        processedOperations = processedOperations.filter { _, operation in
            now.timeIntervalSince(operation.timestamp) < ttl
        }
        await persist()
    }

    // MARK: - Persistance

    private func ensureLoaded() async {
        guard !didLoad else { return }
        await load()
    }

    private func load() async {
        didLoad = true
        guard let keychain else { return }
        guard let stored = try? await keychain.getCodable(
            [String: ProcessedOperation].self,
            forKey: Self.keychainKey
        ) else { return }

        // Purge à la lecture : une entrée expirée n'a aucune raison de revenir
        // en mémoire, et cela borne la taille du blob avec le temps.
        let now = Date()
        processedOperations = stored.filter { now.timeIntervalSince($1.timestamp) < ttl }
    }

    private func persist() async {
        guard let keychain else { return }
        try? await keychain.saveCodable(processedOperations, forKey: Self.keychainKey)
    }
}

// MARK: - Erreurs

public enum IdempotencyError: Error, Sendable, Equatable {
    /// L'opération a déjà été traitée dans la fenêtre de rétention.
    case operationAlreadyProcessed(operationId: String)
}
