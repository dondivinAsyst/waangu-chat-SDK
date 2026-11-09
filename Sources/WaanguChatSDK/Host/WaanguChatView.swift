//
//  WaanguChatView.swift
//  WaanguChatSDK
//
//  The whole chat as one SwiftUI view, so a host imports nothing but WaanguChatSDK.
//

import SwiftUI
import WaanguFeatureChat

/// Chat, ready to present: a tab of your app, a sheet, a full-screen cover.
///
/// It prepares chat, connects the signed-in session and builds the chat screens. While it does,
/// it shows a progress indicator; if that fails it shows a retry button (an icon, no text: the
/// package carries no user-visible wording of its own).
///
/// ```swift
/// WaanguChatView(chat: chat)
/// ```
///
/// With `init(chat:)` you still call `warmUp()` at launch, `startSession()` after each chat
/// login, `appDidEnterForeground()`, `appDidEnterBackground()` and `endSession()` on
/// `WaanguChat` yourself, from your own start-up, scene and sign-out code.
///
/// The short form needs one more call, at app start-up, with the same values:
/// `await WaanguChat.warmUpSelfManaged(configuration:accessToken:)`. It builds chat's database,
/// registers its tables and topics and registers the chat feature, so opening chat only builds
/// the screens. Chat then connects after its own sign-in, and follows the app going to the
/// background and back while this view is on screen.
///
/// ```swift
/// WaanguChatView(
///     configuration: WaanguChatConfiguration(
///         appId: "my-app-id",
///         userId: "my-user-id",
///         chatBaseURL: "<chat API>", chatUploadBaseURL: "<chat upload API>",
///         mainAPIBaseURL: "<main API>",
///         realtime: .init(host: "<mqtt host>", port: 8883, useTLS: true)),
///     accessToken: { await myApp.currentAccessToken() }
/// )
/// ```
@available(iOS 17.0, *)
public struct WaanguChatView: View {

    private enum Source {
        case provided(WaanguChat)
        case selfManaged(WaanguChatConfiguration, @Sendable () async -> String?)
    }

    private let source: Source
    @State private var chat: WaanguChat?
    @State private var coordinator: ChatCoordinator?
    @State private var failed = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dismiss) private var dismiss

    /// Called when the user leaves chat (its back and exit buttons). `nil` dismisses this view,
    /// which is right for a sheet, a full-screen cover or a pushed screen.
    private let onClose: (() -> Void)?

    /// A chat you built and wired yourself.
    public init(chat: WaanguChat, onClose: (() -> Void)? = nil) {
        self.source = .provided(chat)
        self.onClose = onClose
    }

    /// Plug and play. `accessToken` is asked each time chat needs the signed-in user's token; it
    /// returns `nil` when nobody is signed in.
    public init(
        configuration: WaanguChatConfiguration,
        accessToken: @escaping @Sendable () async -> String?,
        onClose: (() -> Void)? = nil
    ) {
        self.source = .selfManaged(configuration, accessToken)
        self.onClose = onClose
    }

    public var body: some View {
        Group {
            if let coordinator {
                ChatCoordinatorView(coordinator: coordinator)
            } else if failed {
                Button {
                    Task { await load() }
                } label: {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.largeTitle)
                }
                .accessibilityIdentifier("waangu.chat.retry")
            } else {
                ProgressView()
            }
        }
        .task { await load() }
        .onChange(of: scenePhase) { _, phase in
            guard case .selfManaged = source, let chat else { return }
            Task {
                switch phase {
                case .active: await chat.appDidEnterForeground()
                case .background: await chat.appDidEnterBackground()
                default: break
                }
            }
        }
    }

    @MainActor
    private func load() async {
        guard coordinator == nil else { return }
        failed = false
        let chat: WaanguChat
        switch source {
        case .provided(let provided):
            chat = provided
        case .selfManaged(let configuration, let accessToken):
            chat = await SelfManagedChat.shared.chat(configuration: configuration, accessToken: accessToken)
        }
        self.chat = chat
        // Done at app start-up when the host calls `warmUp`; then this returns at once.
        await chat.warmUp()
        let built: ChatCoordinator
        do {
            built = try await chat.makeCoordinator()
        } catch {
            failed = true
            return
        }
        built.onCrossFeature = { _ in close() }
        coordinator = built

        // Same order as the app this SDK comes from: the session starts on open only when a chat
        // session already exists. Otherwise the sign-in screen logs in, and the session starts on
        // `UserChatDidLoginEvent` (see `SelfManagedChat`). Starting it now would run a second
        // chat login next to the sign-in screen's own.
        if await chat.chatTokens.hasValidAccessToken() {
            Task { await chat.startSession() }
        }
    }

    @MainActor
    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

extension WaanguChat {

    /// Launch work for a host that uses `WaanguChatView(configuration:accessToken:)`: call it once
    /// from your app's start-up task, with the same values you give the view. It builds chat's
    /// database, registers its tables and realtime topics and registers the chat feature. Without
    /// it, all of that runs when the user first opens chat, behind the spinner.
    public static func warmUpSelfManaged(
        configuration: WaanguChatConfiguration,
        accessToken: @escaping @Sendable () async -> String?
    ) async {
        let chat = await SelfManagedChat.shared.chat(configuration: configuration, accessToken: accessToken)
        await chat.warmUp()
    }

    /// Sign-out for a host that uses `WaanguChatView(configuration:accessToken:)`: call it when the
    /// user chooses to sign out of your app. It clears the conversations kept on the device and
    /// disconnects. Do not call it when a session expires: the conversations stay.
    public static func signOutSelfManaged() async {
        await SelfManagedChat.shared.signOut()
    }
}
