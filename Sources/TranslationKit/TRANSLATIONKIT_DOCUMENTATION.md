# TranslationKit — Full Module Documentation

> Version 1.0.0 · Waangu iOS · Swift Package Module

---

## Table of Contents

1. [Overview](#1-overview)
2. [Core Responsibilities](#2-core-responsibilities)
3. [Three-Tier Loading Chain](#3-three-tier-loading-chain)
4. [Module Position in the Architecture](#4-module-position-in-the-architecture)
5. [Payload Contract — JSON Shape](#5-payload-contract--json-shape)
6. [Persistence — UserDefaults via PreferenceStore](#6-persistence--userdefaults-via-preferencestore)
7. [Payload Lifecycle — Full Flow](#7-payload-lifecycle--full-flow)
8. [Key Namespaces and ChatTranslationKeys](#8-key-namespaces-and-chattranslationkeys)
9. [Internal Architecture — Layer by Layer](#9-internal-architecture--layer-by-layer)
10. [TranslationPayload — The Data Model](#10-translationpayload--the-data-model)
11. [TranslationResult — The Output Model](#11-translationresult--the-output-model)
12. [TranslationServiceProtocol — The Public Contract](#12-translationserviceprotocol--the-public-contract)
13. [TranslationService — The Engine](#13-translationservice--the-engine)
14. [TranslationPayloadStore — Persistence Layer](#14-translationpayloadstore--persistence-layer)
15. [Key Resolution Rules](#15-key-resolution-rules)
16. [Interpolation System](#16-interpolation-system)
17. [Fallback Chain](#17-fallback-chain)
18. [In-Memory Cache](#18-in-memory-cache)
19. [ChatTranslationKeys — Full Reference](#19-chattranslationkeys--full-reference)
20. [Usage Examples](#20-usage-examples)
21. [Dependency Injection and Registration](#21-dependency-injection-and-registration)
22. [UserDefaultsKeys — Translation Namespace](#22-userdefaultskeys--translation-namespace)
23. [Adding a New Feature Module](#23-adding-a-new-feature-module)
24. [Error Catalogue](#24-error-catalogue)
25. [File Map](#25-file-map)
26. [Package.swift Registration](#26-packageswift-registration)
27. [Design Decisions and Trade-offs](#27-design-decisions-and-trade-offs)

---

## 1. Overview

`TranslationKit` is the **self-contained, reusable translation engine** for the Waangu iOS application. It fully manages its own translation data across three tiers — in-memory, UserDefaults (via the project's existing `PreferenceStore`), and a bundled JSON fallback — so that every feature in the app can resolve translated strings by passing only keys, with no knowledge of where the data comes from.

### What TranslationKit owns

| Concern | TranslationKit |
|---|---|
| Bundled default translations (shipped with the app, always available) | **Yes — loaded from `Resources/translations_<locale>.json`** |
| Persisting received payloads to UserDefaults (survives app restart) | **Yes — via `PreferenceStore` internally** |
| In-memory active payload (fast access, session lifetime) | **Yes — held as `var activePayload` on the engine** |
| In-memory resolved string cache | **Yes — `TranslationCache`** |
| Key resolution, fallback chain, interpolation | **Yes — core responsibility** |
| Accepting a fresher payload from any external source | **Yes — via `updatePayload(_:)`** |

### What TranslationKit does NOT own

| Concern | Who owns it |
|---|---|
| Where the payload comes from (HTTP, push, file) | The caller's data layer — `TranslationKit` only receives what it's given |
| Deciding when to refresh from the network | The caller's business logic |
| Deciding which locale to use | The caller / `AppSettings.languageCode` |
| UI string binding in SwiftUI | The caller's ViewModel |
| Feature-domain key definitions | Each feature's own key namespace struct |
| Audit / GDPR tracing | `SecurityKit/TranslationTracer` |

---

## 2. Core Responsibilities

```
┌────────────────────────────────────────────────────────────────────┐
│                        TranslationKit                              │
│                                                                    │
│  1. On init: check UserDefaults → if found, load to memory         │
│             otherwise load bundled JSON → hold in memory           │
│  2. Receive updatePayload(_:) from any caller                      │
│     → validate version → persist to UserDefaults → update memory   │
│  3. Resolve key from active in-memory payload                      │
│  4. Interpolate %1$s / %2$s positional arguments                   │
│  5. Fallback: module → common → raw key (never nil, never throws)  │
│  6. Cache resolved strings in memory for the session               │
│  7. Serve every feature — fully decoupled from all domains         │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. Three-Tier Loading Chain

This is the complete decision tree on every `resolve()` call:

```
resolve(key:module:args:) called
         │
         ▼
Tier 1 — Is there an in-memory activePayload?
  YES ──► use it immediately (fastest path)
  NO  ──►
         │
         ▼
Tier 2 — Does UserDefaults have a saved payload for this locale?
          Key: "translation.payload_<locale>" (raw JSON Data)
  YES ──► decode it, hold in memory as activePayload, use it
  NO  ──►
         │
         ▼
Tier 3 — Load bundled translations_<locale>.json from Bundle.module
  found ──► hold in memory as activePayload, use it
  not found ──► fall back to "en" bundle, or use raw key as last resort
         │
         ▼
Key resolution from activePayload
  found in module ──► interpolate args ──► return
  not found       ──► check "common" module ──► interpolate ──► return
  not found there ──► return raw key string
```

### Why three tiers?

| Tier | Purpose | Speed | Survives restart |
|---|---|---|---|
| In-memory `activePayload` | Fastest — zero I/O per call | Instant | No |
| UserDefaults `PreferenceStore` | Persisted — survives kill/restart | ~1ms on load | **Yes** |
| Bundled JSON | Always-available fallback — works offline on fresh install | ~5ms on load | **Yes (immutable)** |

After the first `updatePayload()` call, the app never needs HTTP to have translations on launch. UserDefaults is loaded once on init, promoted to memory, and every subsequent `resolve()` is pure in-memory dictionary lookup.

---

## 4. Module Position in the Architecture

```
┌───────────────────────────────────────────────────────────────────┐
│                         App Target                                │
│  DependencyContainer creates TranslationService(                  │
│      locale: appSettings.languageCode.rawValue,                   │
│      store: preferenceStore                                       │
│  )                                                                │
│  When network layer gets fresh payload:                           │
│      translationService.updatePayload(decoded)                    │
└───────────────────────┬───────────────────────────────────────────┘
                        │ any TranslationServiceProtocol (CoreKit)
┌───────────────────────▼───────────────────────────────────────────┐
│  Feature modules                                                  │
│  FeatureChat · FeatureWallet · FeatureDoctorConsult               │
│  FeatureRide · FeatureInsurance · FeatureMarketplace …            │
│                                                                   │
│  Import CoreKit only — never import TranslationKit directly       │
│  Each ViewModel calls: translator.resolve(key:module:args:)       │
│  Each feature owns its own key namespace struct                   │
└───────────────────────┬───────────────────────────────────────────┘
                        │
┌───────────────────────▼───────────────────────────────────────────┐
│                     TranslationKit                                │
│  → StorageKit (PreferenceStore — UserDefaults persistence)        │
│  → CoreKit    (protocol definition)                               │
│  → Bundle.module (bundled JSON files)                             │
└───────────────────────────────────────────────────────────────────┘
```

**SPM dependency rule:**
- `TranslationKit` depends on `CoreKit` and `StorageKit`.
- Feature modules depend on `CoreKit` only (protocol lives there).
- The App Target imports `TranslationKit` to register the concrete service.
- `TranslationKit` has no dependency on `NetworkKit`, `SecurityKit`, or any feature.

---

## 5. Payload Contract — JSON Shape

```json
{
  "locale": "fr",
  "version": 1,
  "hash": "abc123",
  "modules": {
    "common": {
      "ok": "OK",
      "cancel": "Annuler",
      "yes": "Oui",
      "no": "Non",
      "save": "Enregistrer",
      "delete": "Supprimer",
      "confirm": "Confirmer",
      "error": "Une erreur est survenue",
      "loading": "Chargement...",
      "retry": "Réessayer",
      "you": "Vous",
      "you_lowercase": "vous"
    },
    "chat": {
      "user_joined": "%1$s a rejoint le groupe",
      "user_joined_you": "Vous avez rejoint le groupe",
      "user_added_actor": "%1$s a ajouté %2$s",
      "user_added_you_actor": "Vous avez ajouté %1$s",
      "user_added_you_target": "%1$s vous a ajouté",
      "user_left": "%1$s a quitté le groupe",
      "user_left_you": "Vous avez quitté le groupe",
      "user_removed_actor": "%1$s a retiré %2$s",
      "user_removed_you_target": "%1$s vous a retiré",
      "add_admin_actor": "%1$s a promu %2$s en administrateur",
      "add_admin_you_actor": "Vous avez promu %1$s en administrateur",
      "add_admin_you_target": "%1$s vous a promu en administrateur",
      "remove_admin_actor": "%1$s a retiré les droits d'admin de %2$s",
      "remove_admin_you_actor": "Vous avez retiré les droits d'admin de %1$s",
      "remove_admin_you_target": "%1$s vous a retiré les droits d'admin",
      "group_created_actor": "%1$s a créé le groupe",
      "group_created_you": "Vous avez créé le groupe",
      "group_name_changed_actor": "%1$s a changé le nom du groupe",
      "group_name_changed_you": "Vous avez changé le nom du groupe",
      "group_picture_changed_actor": "%1$s a changé la photo du groupe",
      "group_picture_changed_you": "Vous avez changé la photo du groupe",
      "encryption_enabled": "Les messages sont chiffrés de bout en bout",
      "disappearing_on_actor": "%1$s a activé les messages éphémères",
      "disappearing_on_you": "Vous avez activé les messages éphémères",
      "disappearing_off_actor": "%1$s a désactivé les messages éphémères",
      "disappearing_off_you": "Vous avez désactivé les messages éphémères",
      "typing_text": "%1$s est en train d'écrire...",
      "recording_audio": "%1$s enregistre un message vocal..."
    }
  }
}
```

### Field descriptions

| Field | Type | Required | Description |
|---|---|---|---|
| `locale` | `String` | yes | BCP-47 locale: `"fr"`, `"en"`, `"es"`, `"de"` |
| `version` | `Int` | yes | Monotonically increasing — used to guard against downgrades |
| `hash` | `String` | yes | SHA-256 of the modules object. Empty string disables check |
| `modules` | `[String:[String:String]]` | yes | Module name → (key → translated string) |
| `modules.common` | `[String:String]` | yes | Shared strings used as fallback by all modules |
| `modules.<feature>` | `[String:String]` | optional | Feature-specific strings |

---

## 6. Persistence — UserDefaults via PreferenceStore

`TranslationKit` persists received payloads using your project's existing `PreferenceStore` / `PreferenceStoreProtocol` from `StorageKit`. This is the same mechanism used by `AppSettings` — no new storage dependency is introduced.

### UserDefaults keys

Following your project's existing `UserDefaultsKeys` namespacing convention (dot-notation, enum namespaces), the translation keys are:

```swift
// Added to UserDefaultsKeys.swift in StorageKit:

enum UserDefaultsKeys {
    // ... existing namespaces ...

    enum Translation {
        /// Raw JSON Data of the persisted payload, keyed per locale.
        /// e.g. "translation.payload_fr", "translation.payload_en"
        static func payloadKey(for locale: String) -> String {
            "translation.payload_\(locale)"
        }
    }
}
```

### What is stored

Each locale stores the raw `Data` (JSON bytes) of the `TranslationPayload`. On next launch, `TranslationService` decodes this data back into a `TranslationPayload` and promotes it to `activePayload`.

```
UserDefaults key                Value
"translation.payload_fr"   →   Data  (JSON bytes of TranslationPayload, locale "fr", version N)
"translation.payload_en"   →   Data  (JSON bytes of TranslationPayload, locale "en", version N)
```

### Version guard before persisting

Before writing to UserDefaults, `TranslationService` checks the version:

```
incoming.version > storedVersion ?
  YES → encode to Data → PreferenceStore.set(data, forKey: "translation.payload_fr")
        → update activePayload in memory
        → invalidate cache for this locale
  NO  → silently ignore (stale payload, do nothing)
```

### Why PreferenceStore and not direct UserDefaults?

Your project uses `PreferenceStore` as the abstraction layer over `UserDefaults.standard`. All other settings (`AppSettings`, `ChatActionsDataSource`, etc.) follow this pattern. `TranslationKit` respects that convention so the storage layer is consistent and testable — in tests you can inject a mock `PreferenceStoreProtocol`.

---

## 7. Payload Lifecycle — Full Flow

```
App first install (no UserDefaults entry yet)
    │
    ▼
TranslationService.init(locale: "fr", store: preferenceStore)
    │
    ├─ check preferenceStore.data(forKey: "translation.payload_fr") → nil
    │
    ├─ load Bundle.module/translations_fr.json → decode → activePayload (version: 1, bundled)
    │
    ▼
Features call resolve() → use bundled strings immediately

─────── Later, network layer fetches fresh payload ───────

    │
    ▼
Caller calls translationService.updatePayload(freshPayload)  [version: 5]
    │
    ├─ version 5 > 1 ✓
    ├─ encode freshPayload to Data
    ├─ preferenceStore.set(data, forKey: "translation.payload_fr")   ← persisted
    ├─ activePayload = freshPayload                                   ← memory updated
    ├─ cache.invalidate(locale: "fr")                                 ← cache cleared
    │
    ▼
All subsequent resolve() calls use version 5 strings

─────── App killed and relaunched ───────

    │
    ▼
TranslationService.init(locale: "fr", store: preferenceStore)
    │
    ├─ preferenceStore.data(forKey: "translation.payload_fr") → Data (version 5) ✓
    ├─ decode → activePayload (version: 5)                           ← persisted payload loaded
    │
    ▼
Features call resolve() → use version 5 strings immediately
No HTTP call needed. No bundled fallback needed.
```

---

## 8. Key Namespaces and ChatTranslationKeys

Each feature owns a **key namespace struct** — a plain Swift struct with `static let` string constants. This struct lives inside the feature module, not in `TranslationKit`. The engine only ever sees plain `String` values, keeping it fully domain-agnostic.

### Why a struct with static lets

- No exhaustiveness checks — keys can be added freely.
- No `rawValue` overhead. Keys are `String` at the point of use.
- `MODULE` constant documents exactly which JSON section the keys map to.
- Trivial to grep, autocomplete, and refactor.

### ChatTranslationKeys — full definition

```swift
// Packages/Sources/FeatureChat/Translation/ChatTranslationKeys.swift

import Foundation

struct ChatTranslationKeys {

    // Must match payload.modules key exactly
    static let MODULE = "chat"

    // MARK: Membership events
    static let USER_JOINED             = "user_joined"
    static let USER_JOINED_YOU         = "user_joined_you"
    static let USER_ADDED_ACTOR        = "user_added_actor"
    static let USER_ADDED_YOU_ACTOR    = "user_added_you_actor"
    static let USER_ADDED_YOU_TARGET   = "user_added_you_target"
    static let USER_LEFT               = "user_left"
    static let USER_LEFT_YOU           = "user_left_you"
    static let USER_REMOVED_ACTOR      = "user_removed_actor"
    static let USER_REMOVED_YOU_TARGET = "user_removed_you_target"

    // MARK: Admin events
    static let ADD_ADMIN_ACTOR           = "add_admin_actor"
    static let ADD_ADMIN_YOU_ACTOR       = "add_admin_you_actor"
    static let ADD_ADMIN_YOU_TARGET      = "add_admin_you_target"
    static let REMOVE_ADMIN_ACTOR        = "remove_admin_actor"
    static let REMOVE_ADMIN_YOU_ACTOR    = "remove_admin_you_actor"
    static let REMOVE_ADMIN_YOU_TARGET   = "remove_admin_you_target"

    // MARK: Group lifecycle
    static let GROUP_CREATED_ACTOR       = "group_created_actor"
    static let GROUP_CREATED_YOU         = "group_created_you"
    static let GROUP_NAME_CHANGED_ACTOR  = "group_name_changed_actor"
    static let GROUP_NAME_CHANGED_YOU    = "group_name_changed_you"
    static let GROUP_PIC_CHANGED_ACTOR   = "group_picture_changed_actor"
    static let GROUP_PIC_CHANGED_YOU     = "group_picture_changed_you"

    // MARK: Security
    static let ENCRYPTION_ENABLED        = "encryption_enabled"

    // MARK: Disappearing messages
    static let DISAPPEARING_ON_ACTOR     = "disappearing_on_actor"
    static let DISAPPEARING_ON_YOU       = "disappearing_on_you"
    static let DISAPPEARING_OFF_ACTOR    = "disappearing_off_actor"
    static let DISAPPEARING_OFF_YOU      = "disappearing_off_you"

    // MARK: Real-time presence
    static let TYPING_TEXT               = "typing_text"
    static let RECORDING_AUDIO           = "recording_audio"
}
```

### Suffix convention

| Suffix | Meaning |
|---|---|
| `_ACTOR` | Third-party performed the action |
| `_YOU_ACTOR` | Current user performed the action (first-person active) |
| `_YOU_TARGET` | Current user was acted upon (first-person passive) |
| `_YOU` | Current user as simple subject, no other participant |
| *(none)* | Third-party action with named participant(s) |

---

## 9. Internal Architecture — Layer by Layer

```
TranslationKit/
├── TranslationKit.swift                    Module version enum
├── TranslationService.swift                Engine — orchestrates all layers
├── Storage/
│   └── TranslationPayloadStore.swift       Persistence via PreferenceStoreProtocol
├── Resources/
│   ├── translations_fr.json                Bundled French (tier 3 fallback)
│   ├── translations_en.json                Bundled English
│   ├── translations_es.json                Bundled Spanish
│   └── translations_de.json                Bundled German
├── Models/
│   ├── TranslationPayload.swift            Codable JSON model (input & stored type)
│   └── TranslationResult.swift             Resolution output per key
├── Engine/
│   ├── FallbackResolver.swift              module → common → raw key
│   └── InterpolationEngine.swift           %1$s / %2$s argument substitution
└── Cache/
    └── TranslationCache.swift              In-memory LRU per session

CoreKit/Protocols/TranslationKit/
└── TranslationServiceProtocol.swift        Public contract for all feature modules
```

---

## 10. TranslationPayload — The Data Model

```swift
// TranslationKit/Models/TranslationPayload.swift

import Foundation

/// Codable model representing a complete translation payload.
/// Used as the decoded model, the in-memory active payload,
/// and the persisted value in UserDefaults (encoded as JSON Data).
public struct TranslationPayload: Codable, Sendable, Equatable {

    /// BCP-47 locale code: "fr", "en", "es", "de"
    public let locale: String

    /// Monotonically increasing version. Guards against stale downgrades.
    public let version: Int

    /// SHA-256 hash of the modules object. Empty string = skip hash check.
    public let hash: String

    /// Module name → (translation key → translated string)
    /// e.g. ["chat": ["user_joined": "%1$s a rejoint le groupe"]]
    public let modules: [String: [String: String]]
}
```

---

## 11. TranslationResult — The Output Model

```swift
// TranslationKit/Models/TranslationResult.swift

import Foundation

public struct TranslationResult: Sendable, Equatable {
    public let key: String              // key that was looked up
    public let module: String           // module searched first
    public let locale: String           // locale of the active payload
    public let value: String            // final resolved string — never nil
    public let resolution: ResolutionSource
}

public enum ResolutionSource: String, Sendable, Equatable {
    case module          // found in the requested module
    case commonFallback  // found in "common" fallback module
    case keyFallback     // not found anywhere — raw key returned
    case cache           // returned from in-memory cache
}
```

---

## 12. TranslationServiceProtocol — The Public Contract

Lives in `CoreKit/Protocols/TranslationKit/` — features import `CoreKit` only.

```swift
// CoreKit/Protocols/TranslationKit/TranslationServiceProtocol.swift

import Foundation

/// Self-contained translation engine.
/// Features call resolve(key:module:args:) only.
/// The service manages its own payload internally across three tiers:
///   1. In-memory   2. UserDefaults (PreferenceStore)   3. Bundled JSON
public protocol TranslationServiceProtocol: Sendable {

    // MARK: Resolution — features only ever call these

    /// Resolve a single key. No payload param — engine manages that internally.
    func resolve(key: String, module: String, args: [String]) -> TranslationResult

    /// Resolve multiple keys sharing the same arg list.
    func resolveAll(keys: [String], module: String, args: [String]) -> [TranslationResult]

    /// Resolve multiple keys where each has its own arg list.
    func resolveRequests(
        _ requests: [(key: String, args: [String])],
        module: String
    ) -> [TranslationResult]

    // MARK: Payload update — called by App Target only

    /// Give the engine a fresh payload from any external source.
    /// Engine persists it to UserDefaults, updates memory, invalidates cache.
    /// Only accepted if payload.version > currently stored version.
    func updatePayload(_ payload: TranslationPayload)

    /// Re-read from UserDefaults and memory-load. Useful after locale change.
    func reloadPayload(for locale: String)

    /// The version currently active in memory. -1 means only bundled is loaded.
    var activePayloadVersion: Int { get }
}

// Convenience — no args
public extension TranslationServiceProtocol {
    func resolve(key: String, module: String) -> TranslationResult {
        resolve(key: key, module: module, args: [])
    }
}
```

---

## 13. TranslationService — The Engine

```swift
// TranslationKit/TranslationService.swift

import Foundation
import StorageKit

public final class TranslationService: TranslationServiceProtocol {

    private var activePayload: TranslationPayload?
    private var cache: TranslationCache
    private let interpolation = InterpolationEngine()
    private let fallback = FallbackResolver()
    private let payloadStore: TranslationPayloadStore
    private let locale: String

    public var activePayloadVersion: Int { activePayload?.version ?? -1 }

    public init(locale: String, store: any PreferenceStoreProtocol) {
        self.locale = locale
        self.cache = TranslationCache()
        self.payloadStore = TranslationPayloadStore(store: store)
        self.activePayload = loadInitialPayload(for: locale)
    }

    // MARK: - Initial loading (three-tier chain)

    private func loadInitialPayload(for locale: String) -> TranslationPayload? {
        // Tier 1 — UserDefaults (persisted from a previous updatePayload call)
        if let persisted = payloadStore.load(for: locale) {
            return persisted
        }
        // Tier 2 — Bundled JSON (always present, shipped with app)
        return loadBundledPayload(for: locale)
            ?? loadBundledPayload(for: "en") // last resort: English bundle
    }

    private func loadBundledPayload(for locale: String) -> TranslationPayload? {
        guard let url = Bundle.module.url(
            forResource: "translations_\(locale)", withExtension: "json"
        ),
        let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(TranslationPayload.self, from: data)
    }

    // MARK: - Resolution

    public func resolve(key: String, module: String, args: [String]) -> TranslationResult {
        guard let payload = activePayload else {
            return TranslationResult(key: key, module: module, locale: locale,
                                     value: key, resolution: .keyFallback)
        }
        let cacheKey = TranslationCache.Key(
            locale: payload.locale, version: payload.version,
            module: module, key: key, args: args
        )
        if let cached = cache.get(cacheKey) {
            return TranslationResult(key: key, module: module, locale: payload.locale,
                                     value: cached, resolution: .cache)
        }
        let (raw, source) = fallback.resolve(key: key, module: module, payload: payload)
        let final = args.isEmpty ? raw : interpolation.interpolate(template: raw, args: args)
        cache.set(cacheKey, value: final)
        return TranslationResult(key: key, module: module, locale: payload.locale,
                                 value: final, resolution: source)
    }

    public func resolveAll(keys: [String], module: String,
                           args: [String]) -> [TranslationResult] {
        keys.map { resolve(key: $0, module: module, args: args) }
    }

    public func resolveRequests(_ requests: [(key: String, args: [String])],
                                module: String) -> [TranslationResult] {
        requests.map { resolve(key: $0.key, module: module, args: $0.args) }
    }

    // MARK: - Payload management

    public func updatePayload(_ payload: TranslationPayload) {
        guard payload.version > activePayloadVersion else { return }
        payloadStore.save(payload)           // persist to UserDefaults
        activePayload = payload              // update memory
        cache.invalidate(locale: payload.locale) // clear stale resolved strings
    }

    public func reloadPayload(for locale: String) {
        activePayload = loadInitialPayload(for: locale)
        cache.invalidateAll()
    }
}
```

---

## 14. TranslationPayloadStore — Persistence Layer

`TranslationPayloadStore` is an internal class (not exposed via the protocol) that wraps `PreferenceStoreProtocol` to save and load `TranslationPayload` as JSON `Data`.

```swift
// TranslationKit/Storage/TranslationPayloadStore.swift

import Foundation
import StorageKit

/// Internal persistence layer for TranslationPayload.
/// Uses PreferenceStore (UserDefaults) via PreferenceStoreProtocol.
/// Keys follow the project's existing dot-notation convention:
///   "translation.payload_fr", "translation.payload_en", etc.
final class TranslationPayloadStore {

    private let store: any PreferenceStoreProtocol
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(store: any PreferenceStoreProtocol) {
        self.store = store
    }

    /// Persist a payload to UserDefaults.
    func save(_ payload: TranslationPayload) {
        guard let data = try? encoder.encode(payload) else { return }
        store.set(data, forKey: key(for: payload.locale))
    }

    /// Load a persisted payload from UserDefaults. Returns nil if none saved.
    func load(for locale: String) -> TranslationPayload? {
        guard let data = store.object(forKey: key(for: locale)) as? Data else {
            return nil
        }
        return try? decoder.decode(TranslationPayload.self, from: data)
    }

    /// Remove a persisted payload (e.g. on logout or locale reset).
    func clear(for locale: String) {
        store.removeAll(forKeys: [key(for: locale)])
    }

    // UserDefaults key following project convention: "translation.payload_<locale>"
    private func key(for locale: String) -> String {
        "translation.payload_\(locale)"
    }
}
```

### Key naming pattern

This follows the exact same convention as the rest of `UserDefaultsKeys` in your project:

| Area | Key pattern | Example |
|---|---|---|
| Chat session | `"chat.<property>"` | `"chat.chatSessionID"` |
| Preferences | `"preferences.<property>"` | `"preferences.languageCode"` |
| Session | `"session.<property>"` | `"session.currentUserId"` |
| **Translation** | `"translation.payload_<locale>"` | `"translation.payload_fr"` |

---

## 15. Key Resolution Rules

```swift
// TranslationKit/Engine/FallbackResolver.swift

public struct FallbackResolver {
    private let commonModule = "common"

    public func resolve(key: String, module: String,
                        payload: TranslationPayload) -> (value: String, source: ResolutionSource) {
        // Level 1 — requested module
        if let value = payload.modules[module]?[key], !value.isEmpty {
            return (value, .module)
        }
        // Level 2 — "common" fallback
        if module != commonModule,
           let value = payload.modules[commonModule]?[key], !value.isEmpty {
            return (value, .commonFallback)
        }
        // Level 3 — raw key (never crashes, never nil)
        return (key, .keyFallback)
    }
}
```

### Resolution priority table

| Scenario | `resolution` | What caller receives |
|---|---|---|
| Key in target module | `.module` | Correct translated string |
| Key not in module, in `common` | `.commonFallback` | Correct string from common |
| Key in neither | `.keyFallback` | Raw key e.g. `"user_joined"` |
| Already resolved this session | `.cache` | Correct string, instant |

---

## 16. Interpolation System

The payload uses **positional printf-style placeholders** matching Android convention: `%1$s`, `%2$s`, etc.

```swift
// TranslationKit/Engine/InterpolationEngine.swift

public struct InterpolationEngine {
    /// Replaces %1$s → args[0], %2$s → args[1], etc.
    /// Out-of-range indices are left as-is. Extra args are ignored.
    public func interpolate(template: String, args: [String]) -> String {
        var result = template
        for (index, arg) in args.enumerated() {
            result = result.replacingOccurrences(of: "%\(index + 1)$s", with: arg)
        }
        return result
    }
}
```

| Template | Args | Result |
|---|---|---|
| `%1$s a rejoint le groupe` | `["Alice"]` | Alice a rejoint le groupe |
| `%1$s a ajouté %2$s` | `["Alice","Bob"]` | Alice a ajouté Bob |
| `Vous avez créé le groupe` | `[]` | Vous avez créé le groupe |
| `%1$s a retiré les droits d'admin de %2$s` | `["Alice","Bob"]` | Alice a retiré les droits d'admin de Bob |

---

## 17. Fallback Chain

Three levels, fully automatic, never crashes.

```
Level 1 — activePayload.modules["chat"]["user_joined"]
  found → interpolate → return (.module)
  not found ↓
Level 2 — activePayload.modules["common"]["user_joined"]
  found → interpolate → return (.commonFallback)
  not found ↓
Level 3 — return "user_joined" as-is (.keyFallback)
```

---

## 18. In-Memory Cache

```swift
// TranslationKit/Cache/TranslationCache.swift

public struct TranslationCache {

    public struct Key: Hashable {
        let locale: String
        let version: Int
        let module: String
        let key: String
        let args: [String]
    }

    private var store: [Key: String] = [:]
    private let maxCapacity: Int

    public init(maxCapacity: Int = 500) { self.maxCapacity = maxCapacity }

    public func get(_ key: Key) -> String? { store[key] }

    public mutating func set(_ key: Key, value: String) {
        if store.count >= maxCapacity { store.removeValue(forKey: store.keys.first!) }
        store[key] = value
    }

    public mutating func invalidate(locale: String) {
        store = store.filter { $0.key.locale != locale }
    }

    public mutating func invalidateAll() { store.removeAll() }
}
```

Cache is invalidated automatically by `updatePayload(_:)`. The caller never manages the cache.

---

## 19. ChatTranslationKeys — Full Reference

### Membership events

| Constant | JSON key | Args | French template | Example |
|---|---|---|---|---|
| `USER_JOINED` | `user_joined` | 1 | `%1$s a rejoint le groupe` | Alice a rejoint le groupe |
| `USER_JOINED_YOU` | `user_joined_you` | 0 | `Vous avez rejoint le groupe` | Vous avez rejoint le groupe |
| `USER_ADDED_ACTOR` | `user_added_actor` | 2 | `%1$s a ajouté %2$s` | Alice a ajouté Bob |
| `USER_ADDED_YOU_ACTOR` | `user_added_you_actor` | 1 | `Vous avez ajouté %1$s` | Vous avez ajouté Bob |
| `USER_ADDED_YOU_TARGET` | `user_added_you_target` | 1 | `%1$s vous a ajouté` | Alice vous a ajouté |
| `USER_LEFT` | `user_left` | 1 | `%1$s a quitté le groupe` | Alice a quitté le groupe |
| `USER_LEFT_YOU` | `user_left_you` | 0 | `Vous avez quitté le groupe` | Vous avez quitté le groupe |
| `USER_REMOVED_ACTOR` | `user_removed_actor` | 2 | `%1$s a retiré %2$s` | Alice a retiré Bob |
| `USER_REMOVED_YOU_TARGET` | `user_removed_you_target` | 1 | `%1$s vous a retiré` | Alice vous a retiré |

### Admin events

| Constant | JSON key | Args | French template | Example |
|---|---|---|---|---|
| `ADD_ADMIN_ACTOR` | `add_admin_actor` | 2 | `%1$s a promu %2$s en administrateur` | Alice a promu Bob en administrateur |
| `ADD_ADMIN_YOU_ACTOR` | `add_admin_you_actor` | 1 | `Vous avez promu %1$s en administrateur` | Vous avez promu Bob en administrateur |
| `ADD_ADMIN_YOU_TARGET` | `add_admin_you_target` | 1 | `%1$s vous a promu en administrateur` | Alice vous a promu en administrateur |
| `REMOVE_ADMIN_ACTOR` | `remove_admin_actor` | 2 | `%1$s a retiré les droits d'admin de %2$s` | Alice a retiré les droits d'admin de Bob |
| `REMOVE_ADMIN_YOU_ACTOR` | `remove_admin_you_actor` | 1 | `Vous avez retiré les droits d'admin de %1$s` | Vous avez retiré les droits d'admin de Bob |
| `REMOVE_ADMIN_YOU_TARGET` | `remove_admin_you_target` | 1 | `%1$s vous a retiré les droits d'admin` | Alice vous a retiré les droits d'admin |

### Group lifecycle

| Constant | JSON key | Args | French template | Example |
|---|---|---|---|---|
| `GROUP_CREATED_ACTOR` | `group_created_actor` | 1 | `%1$s a créé le groupe` | Alice a créé le groupe |
| `GROUP_CREATED_YOU` | `group_created_you` | 0 | `Vous avez créé le groupe` | Vous avez créé le groupe |
| `GROUP_NAME_CHANGED_ACTOR` | `group_name_changed_actor` | 1 | `%1$s a changé le nom du groupe` | Alice a changé le nom du groupe |
| `GROUP_NAME_CHANGED_YOU` | `group_name_changed_you` | 0 | `Vous avez changé le nom du groupe` | Vous avez changé le nom du groupe |
| `GROUP_PIC_CHANGED_ACTOR` | `group_picture_changed_actor` | 1 | `%1$s a changé la photo du groupe` | Alice a changé la photo du groupe |
| `GROUP_PIC_CHANGED_YOU` | `group_picture_changed_you` | 0 | `Vous avez changé la photo du groupe` | Vous avez changé la photo du groupe |

### Security and presence

| Constant | JSON key | Args | French template | Example |
|---|---|---|---|---|
| `ENCRYPTION_ENABLED` | `encryption_enabled` | 0 | `Les messages sont chiffrés de bout en bout` | Les messages sont chiffrés de bout en bout |
| `DISAPPEARING_ON_ACTOR` | `disappearing_on_actor` | 1 | `%1$s a activé les messages éphémères` | Alice a activé les messages éphémères |
| `DISAPPEARING_ON_YOU` | `disappearing_on_you` | 0 | `Vous avez activé les messages éphémères` | Vous avez activé les messages éphémères |
| `DISAPPEARING_OFF_ACTOR` | `disappearing_off_actor` | 1 | `%1$s a désactivé les messages éphémères` | Alice a désactivé les messages éphémères |
| `DISAPPEARING_OFF_YOU` | `disappearing_off_you` | 0 | `Vous avez désactivé les messages éphémères` | Vous avez désactivé les messages éphémères |
| `TYPING_TEXT` | `typing_text` | 1 | `%1$s est en train d'écrire...` | Alice est en train d'écrire... |
| `RECORDING_AUDIO` | `recording_audio` | 1 | `%1$s enregistre un message vocal...` | Alice enregistre un message vocal... |

---

## 20. Usage Examples

### Example 1 — Simple key, no args

```swift
let result = translator.resolve(
    key: ChatTranslationKeys.GROUP_CREATED_YOU,
    module: ChatTranslationKeys.MODULE
)
// → "Vous avez créé le groupe"
// result.resolution → .module (or .cache on subsequent calls)
```

### Example 2 — One arg (someone joined)

```swift
let result = translator.resolve(
    key: ChatTranslationKeys.USER_JOINED,
    module: ChatTranslationKeys.MODULE,
    args: ["Alice"]
)
// → "Alice a rejoint le groupe"
```

### Example 3 — Two args (actor added someone)

```swift
let result = translator.resolve(
    key: ChatTranslationKeys.USER_ADDED_ACTOR,
    module: ChatTranslationKeys.MODULE,
    args: ["Alice", "Bob"]
)
// → "Alice a ajouté Bob"
```

### Example 4 — Typing indicator in ViewModel

```swift
// ViewModel imports CoreKit only — never imports TranslationKit
import CoreKit

final class ChatRoomTypingViewModel: ObservableObject {
    @Published var typingLabel: String = ""
    private let translator: any TranslationServiceProtocol

    init(translator: any TranslationServiceProtocol) {
        self.translator = translator
    }

    func showTyping(userName: String) {
        typingLabel = translator.resolve(
            key: ChatTranslationKeys.TYPING_TEXT,
            module: ChatTranslationKeys.MODULE,
            args: [userName]
        ).value
        // → "Alice est en train d'écrire..."
    }

    func showRecording(userName: String) {
        typingLabel = translator.resolve(
            key: ChatTranslationKeys.RECORDING_AUDIO,
            module: ChatTranslationKeys.MODULE,
            args: [userName]
        ).value
        // → "Alice enregistre un message vocal..."
    }
}
```

### Example 5 — Batch resolve (checkpoint bubble in chat)

```swift
let results = translator.resolveAll(
    keys: [
        ChatTranslationKeys.ENCRYPTION_ENABLED,
        ChatTranslationKeys.DISAPPEARING_ON_YOU,
        ChatTranslationKeys.GROUP_CREATED_YOU
    ],
    module: ChatTranslationKeys.MODULE,
    args: []
)
let encryptionText   = results[0].value  // "Les messages sont chiffrés de bout en bout"
let disappearingText = results[1].value  // "Vous avez activé les messages éphémères"
let createdText      = results[2].value  // "Vous avez créé le groupe"
```

### Example 6 — Per-key args (mixed system messages)

```swift
let requests: [(key: String, args: [String])] = [
    (ChatTranslationKeys.USER_ADDED_ACTOR,   ["Alice", "Bob"]),
    (ChatTranslationKeys.TYPING_TEXT,        ["Charlie"]),
    (ChatTranslationKeys.GROUP_CREATED_YOU,  [])
]

let results = translator.resolveRequests(
    requests, module: ChatTranslationKeys.MODULE
)
// results[0].value → "Alice a ajouté Bob"
// results[1].value → "Charlie est en train d'écrire..."
// results[2].value → "Vous avez créé le groupe"
```

### Example 7 — Receiving fresh payload from network (App Target only)

```swift
// In a use case, after the network layer returns a response:
let freshPayload = try JSONDecoder().decode(TranslationPayload.self, from: httpData)
translationService.updatePayload(freshPayload)
// TranslationKit:
//   1. Checks version > current version
//   2. Persists to UserDefaults ("translation.payload_fr")
//   3. Updates activePayload in memory
//   4. Invalidates cache for "fr"
// All features now get fresh strings on next resolve()
```

### Example 8 — Locale change (user switches language in Settings)

```swift
// In settings ViewModel or AppCoordinator:
appSettings.languageCode = .es
translationService.reloadPayload(for: "es")
// TranslationKit:
//   1. Checks UserDefaults for "translation.payload_es"
//   2. If found, loads it; otherwise loads bundled translations_es.json
//   3. Updates activePayload, clears all cache
// All subsequent resolve() calls return Spanish strings
```

---

## 21. Dependency Injection and Registration

```swift
// Waangu/App/DependencyInjection/DependencyContainer.swift

import TranslationKit   // Only imported here in the entire app

// Add alongside existing lazy vars:
lazy var translationService: any TranslationServiceProtocol = {
    TranslationService(
        locale: appSettings.languageCode.rawValue,  // e.g. "fr"
        store: preferenceStore                       // existing PreferenceStore instance
    )
}()
```

When a fresh payload arrives from the network:

```swift
// In a use case or coordinator (App Target):
translationService.updatePayload(decodedPayload)
```

Features receive the protocol via `ChatDependencies` or equivalent — same injection pattern used everywhere in the project:

```swift
// In ChatDependencies.swift:
public struct ChatDependencies {
    // ... existing fields ...
    public let translationService: any TranslationServiceProtocol
}
```

ViewModels hold `any TranslationServiceProtocol` — they never import `TranslationKit`.

---

## 22. UserDefaultsKeys — Translation Namespace

Add to `Packages/Sources/StorageKit/Preferences/UserDefaultsKeys.swift`:

```swift
enum UserDefaultsKeys {

    // ... existing namespaces (ChatSession, Onboarding, Preferences, Session…) ...

    enum Translation {
        /// Raw JSON Data of the persisted TranslationPayload, keyed per locale.
        /// Examples: "translation.payload_fr", "translation.payload_en"
        static func payloadKey(for locale: String) -> String {
            "translation.payload_\(locale)"
        }
    }
}
```

This follows the exact same dot-notation naming pattern used for every other key in your project.

---

## 23. Adding a New Feature Module

**Step 1** — Add the module section to the payload JSON files for each locale:

```json
// translations_fr.json — add inside "modules":
"marketplace": {
  "item_sold": "%1$s a vendu %2$s",
  "order_placed": "Commande passée avec succès",
  "order_cancelled": "%1$s a annulé la commande"
}
```

**Step 2** — Create the key namespace struct inside the feature:

```swift
// Packages/Sources/FeatureMarketplace/Translation/MarketplaceTranslationKeys.swift

struct MarketplaceTranslationKeys {
    static let MODULE         = "marketplace"
    static let ITEM_SOLD      = "item_sold"
    static let ORDER_PLACED   = "order_placed"
    static let ORDER_CANCELLED = "order_cancelled"
}
```

**Step 3** — Use it in a ViewModel exactly like chat:

```swift
let result = translator.resolve(
    key: MarketplaceTranslationKeys.ITEM_SOLD,
    module: MarketplaceTranslationKeys.MODULE,
    args: ["Alice", "Sac en cuir"]
)
// → "Alice a vendu Sac en cuir"
```

No changes to `TranslationKit`, `TranslationService`, `UserDefaultsKeys`, or `DependencyContainer` are needed. The module is open for extension with zero modification.

---

## 24. Error Catalogue

`TranslationKit` never throws. Every failure state is handled gracefully with a deterministic output.

| Situation | Behaviour | `resolution` | User sees |
|---|---|---|---|
| Normal resolution | Returns translated string | `.module` | Correct string |
| Key not in module, found in `common` | Silent fallback to common | `.commonFallback` | Correct common string |
| Key not found anywhere | Returns raw key string | `.keyFallback` | Raw key e.g. `"user_joined"` |
| In-memory cache hit | Returns cached string immediately | `.cache` | Correct string, instant |
| UserDefaults empty (first install) | Falls back to bundled JSON | `.module` | Bundled string |
| Bundled JSON missing for locale | Falls back to English bundle | `.module` | English string |
| `updatePayload` with lower/equal version | Silently ignored | — | Active payload unchanged |
| `updatePayload` fails to encode | Silently skips UserDefaults save | — | Memory updated, no persistence |
| Too few args for placeholders | Remaining `%N$s` left as-is | `.module` | Partial string, never crashes |
| Too many args | Extra args ignored silently | `.module` | Correct string |

---

## 25. File Map

```
TranslationKit/
├── TranslationKit.swift                    Module version enum
├── TranslationService.swift                Engine — three-tier load, resolve, persist
├── Storage/
│   └── TranslationPayloadStore.swift       PreferenceStore wrapper for payload persistence
├── Resources/
│   ├── translations_fr.json                Bundled French (tier 3 fallback)
│   ├── translations_en.json                Bundled English
│   ├── translations_es.json                Bundled Spanish
│   └── translations_de.json                Bundled German
├── Models/
│   ├── TranslationPayload.swift            Codable model — in-memory, persisted, and decoded type
│   └── TranslationResult.swift             Resolution output per key
├── Engine/
│   ├── FallbackResolver.swift              3-level key lookup chain
│   └── InterpolationEngine.swift           %1$s / %2$s substitution
└── Cache/
    └── TranslationCache.swift              In-memory LRU keyed by locale+version+module+key+args

CoreKit/Protocols/TranslationKit/
└── TranslationServiceProtocol.swift        Public contract — feature modules use only this

StorageKit/Preferences/UserDefaultsKeys.swift
    enum Translation { ... }               Add Translation namespace here

FeatureChat/Translation/
└── ChatTranslationKeys.swift               Chat key namespace (owned by FeatureChat)

Waangu/App/DependencyInjection/
└── DependencyContainer.swift               Add lazy var translationService
```

---

## 26. Package.swift Registration

```swift
// Products:
.library(name: "TranslationKit", targets: ["TranslationKit"]),

// Targets:
.target(
    name: "TranslationKit",
    dependencies: [
        "CoreKit",
        "StorageKit"   // for PreferenceStoreProtocol — UserDefaults persistence
    ],
    path: "Sources/TranslationKit",
    resources: [.process("Resources")]  // bundles the JSON files
),
```

Feature modules do **not** list `TranslationKit` as a dependency — they use `TranslationServiceProtocol` from `CoreKit`.

Only the App Target imports `TranslationKit` directly (in `DependencyContainer.swift`).

---

## 27. Design Decisions and Trade-offs

**Why UserDefaults (PreferenceStore) and not GRDB?**

Your project uses GRDB exclusively for relational data — messages, contacts, discussions, groups. A translation payload is a single JSON blob (~5–20KB), not a relational record. `PreferenceStore` is already used by `AppSettings` for exactly this kind of small serialized value. Using the same mechanism keeps the architecture consistent and avoids unnecessary database schema changes. GRDB would be the wrong tool here.

**Why does the module manage UserDefaults persistence itself?**

If the caller persisted the payload, they would need to reload it and pass it to `TranslationKit` on every launch — creating a circular dependency where the translation module's readiness depends on an external load cycle. By persisting internally, `TranslationKit` is self-sufficient: `init()` is enough for any feature to call `resolve()` immediately with no boot ceremony.

**Why not async / throws on `resolve()`?**

Resolution is pure in-memory dictionary lookups and string replacement after `init()`. There is no I/O per call. The one-time load from UserDefaults or bundle happens in `init()` synchronously. Making `resolve()` async would force every call site to `await`, adding complexity with no benefit.

**Why `%1$s` and not Swift's `String(format:)`?**

`%1$s` matches Android/backend convention so the same JSON payload works cross-platform. Positional placeholders let translated languages reorder words freely. The `InterpolationEngine` is four lines and independently testable.

**Why are key namespaces in the feature, not TranslationKit?**

Putting `ChatTranslationKeys` inside `TranslationKit` would couple the engine to the chat domain — breaking reusability for every other feature. Each feature owns its keys as plain strings; the engine is domain-blind and serves all features identically.

**Why a version guard on `updatePayload`?**

An older HTTP response arriving late (network retry, race condition) should not downgrade a newer cached payload. The version guard ensures the active payload always moves forward, never backward.

---

*End of TranslationKit documentation.*
