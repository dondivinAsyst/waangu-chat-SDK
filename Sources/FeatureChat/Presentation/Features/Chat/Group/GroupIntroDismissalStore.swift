import Foundation

/// Persists whether a group chat has ever had user messages (intro must not return).
enum GroupIntroDismissalStore {
    private static func key(for conversationId: String) -> String {
        "groupEverHadUserMessages.\(conversationId)"
    }
    
    static func isDismissed(conversationId: String) -> Bool {
        UserDefaults.standard.bool(forKey: key(for: conversationId))
    }
    
    static func markDismissed(conversationId: String) {
        UserDefaults.standard.set(true, forKey: key(for: conversationId))
    }
}
