//
//  TranslationService.swift
//  TranslationKit
//
//  Concrete translation engine.
//  Manages payload across three tiers:
//   Tier 1 — in-memory activePayload     (fastest, session-scoped)
//   Tier 2 — UserDefaults persistence    (survives app restart, no kit dep)
//   Tier 3 — bundled JSON fallback       (always available, works offline)
//
//  Dependencies: CoreKit only.
//

import Foundation
import WaanguCoreKit

// MARK: - Notification name

public extension Notification.Name {
    /// Posted on the main thread whenever the active locale changes via reloadPayload(for:).
    /// UserInfo key: "locale" → String
    static let translationLocaleDidChange = Notification.Name("TranslationKit.localeDidChange")
}

// MARK: - TranslationService

public final class TranslationService: TranslationServiceProtocol {

    // MARK: - Internal state

    private var activePayload: TranslationPayload?
    private let cache = TranslationCache()
    private let interpolation = InterpolationEngine()
    private let fallback = FallbackResolver()
    private let payloadStore: TranslationPayloadStore
    private(set) public var activeLocale: String

    // MARK: - Public

    public var activePayloadVersion: Int {
        activePayload?.version ?? -1
    }

    // MARK: - Init

    /// - Parameters:
    ///   - locale: BCP-47 locale code e.g. "fr", "en". Matches the user's app language.
    ///   - defaults: `UserDefaults` instance for persistence. Defaults to `.standard`.
    public init(
        locale: String,
        defaults: UserDefaults = .standard
    ) {
        self.activeLocale = locale
        self.payloadStore = TranslationPayloadStore(defaults: defaults)
        self.activePayload = Self.loadInitialPayload(
            for: locale,
            store: payloadStore
        )
    }

    // MARK: - Three-tier initial load

    private static func loadInitialPayload(
        for locale: String,
        store: TranslationPayloadStore
    ) -> TranslationPayload? {
        // Tier 2 — UserDefaults (persisted from a previous updatePayload call)
        if let persisted = store.load(for: locale) {
            return persisted
        }
        // Tier 3a — Bundled JSON for the requested locale
        if let bundled = loadBundledPayload(for: locale) {
            return bundled
        }
        // Tier 3b — Bundled English as absolute last resort
        return loadBundledPayload(for: "en")
    }

    private static func loadBundledPayload(for locale: String) -> TranslationPayload? {
        guard let url = Bundle.module.url(
            forResource: "translations_\(locale)",
            withExtension: "json"
        ) else { return nil }
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationPayload.self, from: data)
    }

    // MARK: - TranslationServiceProtocol — resolution

    public func resolve(
        key: String,
        module: String,
        args: [String]
    ) -> TranslationResult {
        guard let payload = activePayload else {
            return TranslationResult(
                key: key, module: module, locale: activeLocale,
                value: key, resolution: .keyFallback
            )
        }

        let cacheKey = TranslationCache.Key(
            locale: payload.locale,
            version: payload.version,
            module: module,
            key: key,
            args: args
        )

        // Check in-memory cache first
        if let cached = cache.get(cacheKey) {
            return TranslationResult(
                key: key, module: module, locale: payload.locale,
                value: cached, resolution: .cache
            )
        }

        // Resolve via fallback chain
        let (rawValue, source) = fallback.resolve(
            key: key, module: module, payload: payload
        )

        // Interpolate positional args
        let finalValue = interpolation.interpolate(template: rawValue, args: args)

        // Cache the resolved result
        cache.set(cacheKey, value: finalValue)

        return TranslationResult(
            key: key, module: module, locale: payload.locale,
            value: finalValue, resolution: source
        )
    }

    public func resolveAll(
        keys: [String],
        module: String,
        args: [String]
    ) -> [TranslationResult] {
        keys.map { resolve(key: $0, module: module, args: args) }
    }

    public func resolveRequests(
        _ requests: [(key: String, args: [String])],
        module: String
    ) -> [TranslationResult] {
        requests.map { resolve(key: $0.key, module: module, args: $0.args) }
    }

    // MARK: - TranslationServiceProtocol — payload management

    public func updatePayload(_ payload: TranslationPayload) {
        guard payload.version > activePayloadVersion else { return }
        payloadStore.save(payload)               // persist to UserDefaults
        activePayload = payload                  // update in-memory tier
        cache.invalidate(locale: payload.locale) // clear stale resolved strings
    }

    public func updatePayload(from data: Data, using mapper: ([String: Any]) -> TranslationPayload?) {
        guard let raw = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = mapper(raw) else { return }
        updatePayload(payload)
    }

    public func reloadPayload(for locale: String) {
        activeLocale = locale
        activePayload = Self.loadInitialPayload(for: locale, store: payloadStore)
        cache.invalidateAll()
        // Broadcast on main thread so any Combine subscriber or NotificationCenter
        // observer can trigger a SwiftUI re-render immediately.
        DispatchQueue.main.async {
            NotificationCenter.default.post(
                name: .translationLocaleDidChange,
                object: self,
                userInfo: ["locale": locale]
            )
        }
    }
}
