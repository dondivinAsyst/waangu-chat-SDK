//
//  WaanguChatTokenStore.swift
//  WaanguChatSDK
//
//  What a host needs to give chat its login tokens, without importing any other module.
//

import Foundation
import WaanguCoreKit
import WaanguAuthKit
import WaanguStorageKit

/// Where the host's login tokens live. Chat sends the access token as `Authorization: Bearer`.
///
/// A host that already has a token manager passes it as it is. A host that has none uses
/// `WaanguChat.makeTokenStore(keychainService:)` and saves its tokens into it after its own login.
public typealias WaanguChatTokenStore = TokenManagerProtocol

extension WaanguChat {

    /// A token store backed by the Keychain, under the host's own service name.
    ///
    /// ```swift
    /// let tokens = WaanguChat.makeTokenStore(keychainService: "com.example.myapp")
    /// try await tokens.saveTokens(accessToken: token, accessTokenExpiration: expiry,
    ///                             refreshToken: refresh, refreshTokenExpiration: refreshExpiry)
    /// ```
    ///
    /// Use the same `keychainService` as in `WaanguChatConfiguration`.
    public static func makeTokenStore(keychainService: String) -> any WaanguChatTokenStore {
        makeTokenStore(keychain: KeychainStore(serviceName: keychainService))
    }

    /// The same store over any keychain. Internal: package unit tests run without an app host and
    /// have no Keychain access, so they use an in-memory one.
    static func makeTokenStore(keychain: any KeychainStoreProtocol) -> any WaanguChatTokenStore {
        TokenManager(keychain: keychain, keys: .auth)
    }
}
