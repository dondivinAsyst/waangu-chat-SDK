//
//  SelfManagedChat.swift
//  WaanguChatSDK
//
//  The chat a host gets without wiring anything: one per process, built on first use with its own
//  database and a token manager that asks the host for its access token.
//

import Foundation

actor SelfManagedChat {

    static let shared = SelfManagedChat()

    private var chat: WaanguChat?

    /// The same chat for every call: chat registers process-wide services (feature registry,
    /// database tables), so a second one would register them twice.
    func chat(
        configuration: WaanguChatConfiguration,
        accessToken: @escaping @Sendable () async -> String?
    ) async -> WaanguChat {
        if let chat { return chat }
        let database = await WaanguChat.makeDatabase()
        let created = WaanguChat(
            configuration: configuration,
            database: database,
            tokenManager: ProvidedTokenManager(provider: accessToken)
        )
        chat = created
        return created
    }

    /// Signs the user out of the chat built by `WaanguChatView(configuration:accessToken:)`.
    /// Does nothing when no such chat exists yet.
    func signOut() async {
        await chat?.signOut()
    }
}
