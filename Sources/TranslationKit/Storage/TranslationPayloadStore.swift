//
//  TranslationPayloadStore.swift
//  TranslationKit
//
//  Persists TranslationPayload to UserDefaults.standard directly.
//  No StorageKit or any other kit dependency — pure Foundation.
//
//  Key convention: "translation.payload_<locale>"
//  e.g. "translation.payload_fr", "translation.payload_en"
//

import Foundation
import WaanguCoreKit

// MARK: - TranslationPayloadStore

final class TranslationPayloadStore {

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    // MARK: - Public API

    /// Encode and persist a payload to UserDefaults.
    func save(_ payload: TranslationPayload) {
        guard let data = try? encoder.encode(payload) else { return }
        defaults.set(data, forKey: userDefaultsKey(for: payload.locale))
    }

    /// Load and decode a persisted payload from UserDefaults.
    /// Returns nil if no payload has been saved for this locale.
    func load(for locale: String) -> TranslationPayload? {
        guard let data = defaults.data(forKey: userDefaultsKey(for: locale)) else {
            return nil
        }
        return try? decoder.decode(TranslationPayload.self, from: data)
    }

    /// Remove the persisted payload for a locale.
    func clear(for locale: String) {
        defaults.removeObject(forKey: userDefaultsKey(for: locale))
    }

    // MARK: - Key

    /// "translation.payload_<locale>" — matches the project's dot-notation convention.
    private func userDefaultsKey(for locale: String) -> String {
        "translation.payload_\(locale)"
    }
}
