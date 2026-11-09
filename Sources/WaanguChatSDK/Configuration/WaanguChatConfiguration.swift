//
//  WaanguChatConfiguration.swift
//  WaanguChatSDK
//
//  What a host app tells the chat about itself (SDK plan, step 1.9). Every value is the host's
//  own: no URL, host name or identifier is built into the SDK.
//

import Foundation
import WaanguFeatureChat

public struct WaanguChatConfiguration: Sendable {

    /// The realtime (MQTT) broker.
    public struct Realtime: Sendable {
        public let host: String
        public let port: UInt16
        public let useTLS: Bool

        public init(host: String, port: UInt16, useTLS: Bool) {
            self.host = host
            self.port = port
            self.useTLS = useTLS
        }
    }

    /// The app's identifier in Identity, sent as `X-App-Id` on chat login. Identity asks that
    /// app's registered `verify-user` webhook who the signed-in user is.
    public let appId: String
    /// Who the user is, sent as `user_identifier` in the chat login body. Required, like `appId`.
    public let userId: String
    public let chatBaseURL: String
    public let chatUploadBaseURL: String
    /// The host's main API. Chat uses it for its legacy upload path and to tell which backend a
    /// local database belongs to.
    public let mainAPIBaseURL: String
    public let realtime: Realtime
    /// Sent as the `Authorization` header when the user has no token yet (for example the first
    /// call). The user's `Bearer` token replaces it as soon as there is one. `nil` sends nothing.
    public let basicAuthToken: String?
    /// Keychain service that holds the chat's tokens and signature keys. Use the service your app
    /// already uses, or tokens saved by an earlier version are no longer found. When the host
    /// passes none, the app's bundle identifier is used.
    public let keychainService: String
    /// The parts of chat the host turns on besides messaging, which is always there. A part that
    /// is off shows no entry point. Payments are off unless asked for, and the server's own
    /// capability answer still applies on top of them.
    public let modules: Set<ChatModule>

    public init(
        appId: String,
        userId: String,
        chatBaseURL: String,
        chatUploadBaseURL: String,
        mainAPIBaseURL: String,
        realtime: Realtime,
        basicAuthToken: String? = nil,
        keychainService: String? = nil,
        modules: Set<ChatModule> = ChatModule.standard
    ) {
        self.appId = appId
        self.userId = userId
        self.chatBaseURL = chatBaseURL
        self.chatUploadBaseURL = chatUploadBaseURL
        self.mainAPIBaseURL = mainAPIBaseURL
        self.realtime = realtime
        self.basicAuthToken = basicAuthToken
        self.keychainService = keychainService ?? Bundle.main.bundleIdentifier ?? "waangu.chat"
        self.modules = modules
    }
}
