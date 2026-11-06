//
//  ProvidedTokenManager.swift
//  WaanguChatSDK
//
//  A token manager that holds nothing: every read asks the host for its current access token, so
//  the host keeps owning its login and renewal.
//

import Foundation
import WaanguCoreKit

final class ProvidedTokenManager: TokenManagerProtocol {

    private let provider: @Sendable () async -> String?

    init(provider: @escaping @Sendable () async -> String?) {
        self.provider = provider
    }

    func getAccessToken() async throws -> String? { await provider() }
    func getRefreshToken() async throws -> String? { nil }
    func hasValidAccessToken() async -> Bool { await provider() != nil }
    func hasValidRefreshToken() async -> Bool { false }

    // The host owns the tokens: chat never stores or clears them.
    func saveTokens(accessToken: String, accessTokenExpiration: Date,
                    refreshToken: String, refreshTokenExpiration: Date) async throws {}
    func clearTokens() async throws {}
}
