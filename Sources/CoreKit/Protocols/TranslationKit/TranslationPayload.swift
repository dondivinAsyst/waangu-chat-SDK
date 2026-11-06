//
//  TranslationPayload.swift
//  CoreKit
//
//  Canonical internal model for the translation engine.
//  This is NOT tied to any HTTP response schema.
//
//  The engine only ever works with this type.
//  How the caller obtains this model — HTTP, push, file, or any other source —
//  is entirely up to them. They decode/map their payload into this type
//  and hand it to the engine via updatePayload(_:).
//

import Foundation

// MARK: - TranslationPayload

/// Canonical translation data model used internally by TranslationKit.
///
/// Schema-agnostic: the caller is responsible for mapping their HTTP
/// (or any other) response into this type. The engine never parses
/// raw network data.
///
/// Internal persistence format (UserDefaults, via JSONEncoder):
/// ```json
/// {
///   "locale": "fr",
///   "version": 1,
///   "modules": {
///     "common": { "ok": "OK" },
///     "chat":   { "user_joined": "%1$s a rejoint le groupe" }
///   }
/// }
/// ```
public struct TranslationPayload: Codable, Sendable, Equatable {

    /// BCP-47 locale code: "fr", "en", "es", "de"
    public let locale: String

    /// Monotonically increasing version — prevents stale downgrades.
    public let version: Int

    /// Module name → (translation key → translated string).
    /// e.g. `["chat": ["user_joined": "%1$s a rejoint le groupe"]]`
    public let modules: [String: [String: String]]

    public init(
        locale: String,
        version: Int,
        modules: [String: [String: String]]
    ) {
        self.locale = locale
        self.version = version
        self.modules = modules
    }
}

// MARK: - TranslationPayloadBuilder

/// Fluent builder to construct a TranslationPayload from any data source.
///
/// Usage — mapping from any HTTP response shape:
/// ```swift
/// let payload = TranslationPayloadBuilder(locale: "fr", version: response.v)
///     .addModule("common", translations: response.shared)
///     .addModule("chat",   translations: response.chatStrings)
///     .build()
/// translationService.updatePayload(payload)
/// ```
public struct TranslationPayloadBuilder {

    private let locale: String
    private let version: Int
    private var modules: [String: [String: String]] = [:]

    public init(locale: String, version: Int) {
        self.locale = locale
        self.version = version
    }

    /// Add a named module with its key→string map.
    @discardableResult
    public func addModule(_ name: String, translations: [String: String]) -> TranslationPayloadBuilder {
        var copy = self
        copy.modules[name] = translations
        return copy
    }

    /// Build the final canonical payload.
    public func build() -> TranslationPayload {
        TranslationPayload(locale: locale, version: version, modules: modules)
    }
}

