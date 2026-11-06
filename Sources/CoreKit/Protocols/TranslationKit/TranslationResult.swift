//
//  TranslationResult.swift
//  CoreKit
//
//  Output model for a single key resolution.
//  Defined in CoreKit so feature ViewModels can use it
//  without importing TranslationKit.
//

import Foundation

// MARK: - TranslationResult

/// The outcome of resolving a single translation key.
/// `value` is always non-nil and non-empty — the engine never returns blank.
public struct TranslationResult: Sendable, Equatable {

    /// The key that was looked up.
    public let key: String

    /// The module namespace that was searched first.
    public let module: String

    /// The locale of the active payload used for resolution.
    public let locale: String

    /// The final resolved, interpolated string.
    /// Guaranteed non-nil. Worst case returns the raw key string.
    public let value: String

    /// Describes where the value was resolved from.
    public let resolution: ResolutionSource

    public init(
        key: String,
        module: String,
        locale: String,
        value: String,
        resolution: ResolutionSource
    ) {
        self.key = key
        self.module = module
        self.locale = locale
        self.value = value
        self.resolution = resolution
    }
}

// MARK: - ResolutionSource

/// Where the final string value came from.
public enum ResolutionSource: String, Sendable, Equatable {

    /// Found directly in the requested module.
    case module

    /// Not in the requested module; found in the "common" fallback module.
    case commonFallback

    /// Not found in any module; the raw key string was returned.
    case keyFallback

    /// Returned from the in-memory resolved-string cache (not re-resolved).
    case cache
}
