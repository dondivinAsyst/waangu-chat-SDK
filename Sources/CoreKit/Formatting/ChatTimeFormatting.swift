import Foundation

/// Clock style used for in-chat message timestamps.
public enum ChatTimeFormat: String, CaseIterable, Sendable, Codable, Hashable {
    case hour24
    case hour12

    /// English label, for logs and for callers with no translation service.
    ///
    /// Not for the settings screen: CoreKit holds no translation keys, so a UI
    /// that reads this shows English in every language. `FeatureChat` adds a
    /// `displayName(translationService:)` that resolves properly.
    public var fallbackDisplayName: String {
        switch self {
        case .hour24: return "24-hour"
        case .hour12: return "12-hour"
        }
    }
}

/// Shared formatter for chat bubble timestamps.
/// Default is 24-hour (`HH:mm`). Switch globally via `preferredFormat`.
public enum ChatTimeFormatting {
    public static let didChangeNotification = Notification.Name("CoreKit.ChatTimeFormat.didChange")

    private static let storageKey = "chat.preferredTimeFormat"
    private static let formatterLock = NSLock()
    private static var formatterCache: [ChatTimeFormat: DateFormatter] = [:]

    public static var preferredFormat: ChatTimeFormat {
        get {
            guard let raw = UserDefaults.standard.string(forKey: storageKey),
                  let format = ChatTimeFormat(rawValue: raw) else {
                return .hour24
            }
            return format
        }
        set {
            guard preferredFormat != newValue else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: storageKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    public static func formatTime(_ date: Date, format: ChatTimeFormat? = nil) -> String {
        formatter(for: format ?? preferredFormat).string(from: date)
    }

    private static func formatter(for format: ChatTimeFormat) -> DateFormatter {
        formatterLock.lock()
        defer { formatterLock.unlock() }

        if let cached = formatterCache[format] {
            return cached
        }

        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = .current
        formatter.dateStyle = .none
        formatter.timeStyle = .none
        switch format {
        case .hour24:
            formatter.dateFormat = "HH:mm"
        case .hour12:
            formatter.dateFormat = "h:mm a"
        }
        formatterCache[format] = formatter
        return formatter
    }
}
