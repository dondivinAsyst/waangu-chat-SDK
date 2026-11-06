//
//  SyncCursorStore.swift
//  CoreKit
//
//  Storage for synchronization cursors
//

import Foundation

// MARK: - Sync Cursor Store

/// - Warning: **Ne pas adopter.** Retiré au Bloc 8 (P0-5).
///
///   Ce magasin écrit les curseurs dans `UserDefaults`, qui n'est pas
///   transactionnel avec la base GRDB qui porte les données. L'écriture y est
///   de plus différée par le système : un curseur « sauvegardé » peut ne pas
///   survivre à un kill que les données, elles, ont survécu. Le §16 du Bloc 8
///   interdit précisément cet ordre — un curseur en avance sur ses données fait
///   sauter les événements de l'intervalle, définitivement et sans erreur.
///
///   Il n'a aujourd'hui **aucun appelant** : la synchronisation réelle vit dans
///   `FeatureSyncEngine` avec son propre `SyncState.currentCursor`. Le risque
///   n'est donc pas ce qu'il fait, mais qu'on le prenne un jour pour le
///   composant de référence — deux modèles pour la même notion, dont un faux.
///
///   Utiliser ``SyncCursorPersisting`` (`SyncIntegrity.swift`), dont la
///   signature exige un ``CommitReceipt`` et rend l'inversion impossible à
///   écrire.
///
///   Conservé plutôt que supprimé, comme `PaymentEnvelope.verifySignature` au
///   Bloc 1 : la dépréciation bloque l'adoption sans effacer l'historique.
@available(*, deprecated, message: "Non transactionnel avec la base de données. Utiliser SyncCursorPersisting (SyncIntegrity.swift), qui exige un CommitReceipt.")
public final class SyncCursorStore {
    
    // MARK: - Properties
    
    private let userDefaults: UserDefaults
    private let conversationsCursorKey = "sync.conversations.cursor"
    private let conversationsLastSyncKey = "sync.conversations.lastSync"
    
    // MARK: - Initialization
    
    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }
    
    // MARK: - Conversations Sync
    
    public func getConversationsCursor() -> String? {
        return userDefaults.string(forKey: conversationsCursorKey)
    }
    
    public func saveConversationsCursor(_ cursor: String) {
        userDefaults.set(cursor, forKey: conversationsCursorKey)
        userDefaults.set(Date(), forKey: conversationsLastSyncKey)
    }
    
    public func getConversationsLastSyncDate() -> Date? {
        return userDefaults.object(forKey: conversationsLastSyncKey) as? Date
    }
    
    public func clearConversationsSync() {
        userDefaults.removeObject(forKey: conversationsCursorKey)
        userDefaults.removeObject(forKey: conversationsLastSyncKey)
    }
    
    // MARK: - Per-Conversation Message Sync
    
    public func getMessagesCursor(for conversationId: String) -> String? {
        let key = "sync.messages.\(conversationId).cursor"
        return userDefaults.string(forKey: key)
    }
    
    public func saveMessagesCursor(_ cursor: String, for conversationId: String) {
        let cursorKey = "sync.messages.\(conversationId).cursor"
        let lastSyncKey = "sync.messages.\(conversationId).lastSync"
        userDefaults.set(cursor, forKey: cursorKey)
        userDefaults.set(Date(), forKey: lastSyncKey)
    }
    
    public func getMessagesLastSyncDate(for conversationId: String) -> Date? {
        let key = "sync.messages.\(conversationId).lastSync"
        return userDefaults.object(forKey: key) as? Date
    }
    
    public func clearMessagesSync(for conversationId: String) {
        let cursorKey = "sync.messages.\(conversationId).cursor"
        let lastSyncKey = "sync.messages.\(conversationId).lastSync"
        userDefaults.removeObject(forKey: cursorKey)
        userDefaults.removeObject(forKey: lastSyncKey)
    }
    
    // MARK: - Stories Sync
    
    private let storiesCursorKey = "sync.stories.cursor"
    private let storiesLastSyncKey = "sync.stories.lastSync"
    
    public func getStoriesCursor() -> String? {
        return userDefaults.string(forKey: storiesCursorKey)
    }
    
    public func saveStoriesCursor(_ cursor: String) {
        userDefaults.set(cursor, forKey: storiesCursorKey)
        userDefaults.set(Date(), forKey: storiesLastSyncKey)
    }
    
    public func getStoriesLastSyncDate() -> Date? {
        return userDefaults.object(forKey: storiesLastSyncKey) as? Date
    }
    
    public func clearStoriesSync() {
        userDefaults.removeObject(forKey: storiesCursorKey)
        userDefaults.removeObject(forKey: storiesLastSyncKey)
    }
    
    // MARK: - Calls Sync

    private let callsCursorKey = "sync.calls.cursor"
    private let callsLastSyncKey = "sync.calls.lastSync"

    public func getCallsCursor() -> String? {
        return userDefaults.string(forKey: callsCursorKey)
    }

    public func saveCallsCursor(_ cursor: String) {
        userDefaults.set(cursor, forKey: callsCursorKey)
        userDefaults.set(Date(), forKey: callsLastSyncKey)
    }

    public func getCallsLastSyncDate() -> Date? {
        return userDefaults.object(forKey: callsLastSyncKey) as? Date
    }

    public func clearCallsSync() {
        userDefaults.removeObject(forKey: callsCursorKey)
        userDefaults.removeObject(forKey: callsLastSyncKey)
    }

    // MARK: - Clear All

    public func clearAllSyncCursors() {
        clearConversationsSync()
        clearStoriesSync()
        clearCallsSync()
        clearAllMessagesSync()
    }

    /// Les curseurs de **toutes** les conversations. Après l'effacement local des
    /// messages, un curseur resté en place ne rapporterait que le nouveau : l'historique
    /// ne reviendrait jamais.
    public func clearAllMessagesSync() {
        for key in userDefaults.dictionaryRepresentation().keys where key.hasPrefix("sync.messages.") {
            userDefaults.removeObject(forKey: key)
        }
    }
}
