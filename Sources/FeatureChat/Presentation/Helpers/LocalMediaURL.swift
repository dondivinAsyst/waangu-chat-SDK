import Foundation

/// Resolves a stored media location string into a URL that can actually be read.
///
/// Media locations reach us as bare filesystem paths — `PHMediaManager` builds
/// them with `urlAsset.url.path` — but the obvious conversion is wrong:
///
/// ```swift
/// URL(string: path) ?? URL(fileURLWithPath: path)   // ❌
/// ```
///
/// `URL(string:)` does **not** fail on a path. A path-only string is a valid
/// relative URL reference, so it returns a URL with a nil scheme and the `??`
/// fallback never runs. `Data(contentsOf:)` then throws on that scheme-less URL,
/// which is why sent videos were never written to disk and uploads failed with
/// "Local file not found".
enum LocalMediaURL {

    /// - Returns: a file URL for filesystem paths, the original URL for strings
    ///   carrying a real scheme, and `nil` for empty input.
    static func resolve(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Absolute path — check before URL(string:), which would happily accept it.
        if trimmed.hasPrefix("/") {
            return URL(fileURLWithPath: trimmed)
        }

        // Genuine URL only when it carries a scheme.
        if let url = URL(string: trimmed), url.scheme != nil {
            return url
        }

        return URL(fileURLWithPath: trimmed)
    }
}
