import Foundation

/// Local data source for per-conversation / per-contact preferences (mute, pin, archive,
/// wallpaper, lock, ephemeral messages, etc.).
/// Backed by ChatPreferenceModel — one row per (targetType, targetKey).
protocol LocalChatPreferenceDataSourceProtocol {
    /// Fetch the preference for a conversation UUID.
    func fetchPreference(conversationId: String) async throws -> UserConversationSetting?
    /// Fetch the preference for a direct-chat phone number.
    func fetchPreference(phone: String) async throws -> UserConversationSetting?
    /// Persist a setting for a conversation UUID.
    func savePreference(_ setting: UserConversationSetting, conversationId: String) async throws
    /// Persist a setting for a direct-chat phone number.
    func savePreference(_ setting: UserConversationSetting, phone: String) async throws
    /// Delete preference for a conversation UUID.
    func deletePreference(conversationId: String) async throws
}
