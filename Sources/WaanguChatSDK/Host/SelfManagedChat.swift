//
//  SelfManagedChat.swift
//  WaanguChatSDK
//
//  The chat a host gets without wiring anything: one per process, built on first use with its own
//  database and a token manager that asks the host for its access token.
//

import Foundation
import WaanguCoreKit

actor SelfManagedChat {

    static let shared = SelfManagedChat()

    /// A task, not the chat itself: the actor can switch callers at the `await` inside, so two
    /// callers arriving together (start-up `warmUp` and a tap on chat) must share one build.
    private var building: Task<WaanguChat, Never>?
    private var chat: WaanguChat?
    private var loginListener: Task<Void, Never>?

    /// The same chat for every call: chat registers process-wide services (feature registry,
    /// database tables), so a second one would register them twice.
    func chat(
        configuration: WaanguChatConfiguration,
        accessToken: @escaping @Sendable () async -> String?
    ) async -> WaanguChat {
        if let building { return await building.value }
        let task = Task {
            let database = await WaanguChat.makeDatabase()
            return WaanguChat(
                configuration: configuration,
                database: database,
                tokenManager: ProvidedTokenManager(provider: accessToken)
            )
        }
        building = task
        let created = await task.value
        if chat == nil {
            chat = created
            followChatLogins(of: created)
        }
        return created
    }

    /// The chat `warmUpSelfManaged` built, waiting for it if it is still being built; `nil` if
    /// no start-up call was made.
    func current() async -> WaanguChat? {
        guard let building else { return nil }
        return await building.value
    }

    /// The host app's `SessionManager` does this for the app that owns the code: the session
    /// starts once the chat login has happened, not at the same time as it. The chat sign-in
    /// screen publishes `UserChatDidLoginEvent` when it has a session; realtime and sync start
    /// then, with chat tokens that exist.
    private func followChatLogins(of chat: WaanguChat) {
        guard loginListener == nil else { return }
        loginListener = Task {
            for await _ in EventBus.shared.subscribe(to: UserChatDidLoginEvent.self) {
                await chat.startSession()
            }
        }
    }

    /// Signs the user out of the chat built by `WaanguChatView(configuration:accessToken:)`.
    /// Does nothing when no such chat exists yet.
    func signOut() async {
        await chat?.signOut()
    }
}
