//
//  TranslationKit.swift
//  TranslationKit
//
//  Self-contained translation engine.
//  Depends on CoreKit only.
//
//  Three-tier payload loading:
//   1. In-memory (fastest, session-scoped)
//   2. UserDefaults (persists across app restarts, pure Foundation)
//   3. Bundled JSON (always available, ships with the module)
//
//  Schema-agnostic: the caller maps any HTTP response shape
//  into TranslationPayload via TranslationPayloadBuilder.
//

import Foundation

/// TranslationKit module version.
public enum TranslationKit {
    public static let version = "1.0.0"
}
