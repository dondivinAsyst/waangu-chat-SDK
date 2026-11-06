//
//  ChatDatabaseRegistration.swift
//  AppModules
//

import WaanguCoreKit

/// Registers all GRDB models for the Chat feature using the current model set.
public enum ChatDatabaseRegistration: DatabaseRegistrable, Sendable {

    /// Registration order: parents before children.
    public static let storableTypes: [any Storable.Type] = [
        // Roots — no foreign keys to other chat tables
        ConversationModel.self,
        ContactModel.self,
        ContactSyncStateModel.self,

        // Conversation participants (FK → ConversationModel)
        ConversationParticipantModel.self,

        // Group-specific
        GroupPermissionsModel.self,
        GroupSettingsModel.self,
        GroupJoinRequestModel.self,

        // Messages (FK → ConversationModel)
        MessageModel.self,
        MessageReactionModel.self,
        ReadReceiptModel.self,
        PinnedMessageModel.self,

        // Calls
        CallLogModel.self,

        // Statuses (per-segment)
        StatusModel.self,
        StatusViewerModel.self,

        // Chat preferences (mute / wallpaper / lock)
        ChatPreferenceModel.self,

        // Chat actions (audit trail)
        ChatActionModel.self,

        // Sync watermarks — one row per delta stream ("chat", "chat.conversations",
        // "chat.calls"). Unregistered, its table is never built and every write is
        // swallowed by the `try?` around it, which means a full re-sync on every
        // launch instead of a delta.
        SyncState.self,

        // Outbound actions awaiting a flush. Same trap as SyncState above:
        // unregistered, rows fall back to the shared JSON proxy table, where
        // filters are ignored — so the dedup check matched any row at all and
        // silently dropped every enqueue after the first.
        ChatOutboxItem.self,

        // Chat finance — objects to reconcile on launch, one row per account
        // and object. Replaces the per-account JSON file; the AppTarget imports
        // that file once, then deletes it.
        FinancialObjectModel.self,

        // Chat finance — deferrable actions (Bloc 1, 2.3), one row per account
        // and action, restored at login and flushed when the network returns.
        FinanceOutboxItemModel.self,

        // Waangu Copilot — the transcript of the on-device Copilot conversation,
        // one row per message, already cleaned of what must never be kept.
        CopilotMessageModel.self,
    ]

    public static let migrationSteps: [any MigrationStep] = [
        // StatusModel v1 → v2: local "I've opened this segment" flag (green ring).
        // INTEGER DEFAULT 0 — must NOT reuse viewCount (that's "others viewed my story").
        FieldMigration(
            from:         1,
            to:           2,
            entity:       StatusModel.self,
            field:        "viewed",
            defaultValue: "0"
        ),
        // StatusModel v2 → v3: upload retry metadata.
        FieldMigration(
            from:         2,
            to:           3,
            entity:       StatusModel.self,
            field:        "filename",
            defaultValue: nil
        ),
        FieldMigration(
            from:         2,
            to:           3,
            entity:       StatusModel.self,
            field:        "fileSize",
            defaultValue: "0"
        ),
        FieldMigration(
            from:         2,
            to:           3,
            entity:       StatusModel.self,
            field:        "localPath",
            defaultValue: nil
        ),
        // ConversationModel v1 → v2: dedicated serverId column (groups + synced direct chats).
        FieldMigration(
            from:         1,
            to:           2,
            entity:       ConversationModel.self,
            field:        "serverId",
            defaultValue: nil
        ),
        // StatusViewerModel v1 → v2: reaction emoji from STORY_REACTED.
        FieldMigration(
            from:         1,
            to:           2,
            entity:       StatusViewerModel.self,
            field:        "reaction",
            defaultValue: nil
        ),
    ]
}
