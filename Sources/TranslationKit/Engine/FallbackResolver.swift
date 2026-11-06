//
//  FallbackResolver.swift
//  TranslationKit
//
//  Three-level key resolution chain:
//   1. Requested module
//   2. "common" fallback module
//   3. Raw key string (never nil, never throws)
//

import Foundation
import WaanguCoreKit

// MARK: - FallbackResolver

struct FallbackResolver {

    private let commonModule = "common"

    /// Resolve a key from a payload using the three-level fallback chain.
    /// - Returns: (resolved string, where it came from)
    func resolve(
        key: String,
        module: String,
        payload: TranslationPayload
    ) -> (value: String, source: ResolutionSource) {

        // Level 1 — target module
        if let value = payload.modules[module]?[key], !value.isEmpty {
            return (value, .module)
        }

        // Level 2 — "common" module (only if not already searching common)
        if module != commonModule,
           let value = payload.modules[commonModule]?[key],
           !value.isEmpty {
            return (value, .commonFallback)
        }

        // Level 3 — return the raw key so the UI is never blank
        return (key, .keyFallback)
    }
}
