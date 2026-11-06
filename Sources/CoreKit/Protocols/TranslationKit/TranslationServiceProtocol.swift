//
//  TranslationServiceProtocol.swift
//  CoreKit
//
//  Public contract for the translation engine.
//  Feature modules import CoreKit only — never import TranslationKit directly.
//

import Foundation

// MARK: - TranslationServiceProtocol

/// Self-contained translation engine protocol.
///
/// Features call resolve(key:module:args:) only.
/// The concrete service manages its own payload internally across three tiers:
///   1. In-memory active payload  (fastest)
///   2. UserDefaults persistence  (survives app restart, no kit dependency)
///   3. Bundled JSON fallback     (always available, works offline on fresh install)
public protocol TranslationServiceProtocol: AnyObject {

    // MARK: - Resolution

    /// Resolve a single translation key.
    /// The service manages the active payload internally — no payload param needed.
    /// - Parameters:
    ///   - key: Translation key e.g. `ChatTranslationKeys.USER_JOINED`
    ///   - module: Module section to search first e.g. `ChatTranslationKeys.MODULE`
    ///   - args: Positional interpolation args for %1$s, %2$s, … placeholders
    func resolve(key: String, module: String, args: [String]) -> TranslationResult

    /// Resolve multiple keys sharing the same arg list.
    func resolveAll(keys: [String], module: String, args: [String]) -> [TranslationResult]

    /// Resolve multiple keys where each key has its own arg list.
    func resolveRequests(
        _ requests: [(key: String, args: [String])],
        module: String
    ) -> [TranslationResult]

    // MARK: - Payload management

    /// Push a pre-mapped canonical payload into the engine.
    func updatePayload(_ payload: TranslationPayload)

    /// Push a raw JSON Data payload using a custom mapping closure.
    func updatePayload(from data: Data, using mapper: ([String: Any]) -> TranslationPayload?)

    /// Reload from UserDefaults (or bundle if none persisted) for the given locale.
    /// After reloading, posts a `TranslationKit.localeDidChange` notification on the main thread
    /// so that any ObservableObject can subscribe and trigger a SwiftUI re-render.
    func reloadPayload(for locale: String)

    /// The version number of the currently active in-memory payload. -1 = bundled fallback.
    var activePayloadVersion: Int { get }

    /// The locale code currently active (e.g. "fr", "en"). Used by views to observe changes.
    var activeLocale: String { get }
}

// MARK: - Convenience (no args)

public extension TranslationServiceProtocol {

    /// Resolve a key with no interpolation arguments.
    func resolve(key: String, module: String) -> TranslationResult {
        resolve(key: key, module: module, args: [])
    }
}
