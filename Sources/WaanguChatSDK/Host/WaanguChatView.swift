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
/// Give chat its configuration and token closure once, at app start-up, then show it:
///
/// ```swift
/// // At start-up
/// await WaanguChat.warmUpSelfManaged(
///     configuration: WaanguChatConfiguration(
///         appId: "my-app-id",
///         userId: "my-user-id",
///         chatBaseURL: "<chat API>", chatUploadBaseURL: "<chat upload API>",
///         mainAPIBaseURL: "<main API>",
///         realtime: .init(host: "<mqtt host>", port: 8883, useTLS: true)),
///     accessToken: { await myApp.currentAccessToken() }
/// )
///
/// // When the user opens chat
/// WaanguChatView()
/// ```
///
/// The start-up call builds chat's database, registers its tables and topics and registers the
/// chat feature, so opening chat only builds the screens. Chat connects after its own sign-in,
/// and follows the app going to the background and back while this view is on screen. If
/// building the screens fails, or `warmUpSelfManaged` was never called, the view shows a retry
/// button (an icon, no text: the package carries no user-visible wording of its own).
///
/// With `init(chat:)`, a chat you built yourself, you call `warmUp()` at launch,
/// `startSession()` after each chat login, `appDidEnterForeground()`, `appDidEnterBackground()`
/// and `endSession()` on `WaanguChat` yourself, from your own start-up, scene and sign-out code.
@available(iOS 17.0, *)
public struct WaanguChatView: View {

    private enum Source {
        case provided(WaanguChat)
        /// The chat `WaanguChat.warmUpSelfManaged` built at start-up.
        case warmedUp
        /// Older form: the values again, on the view. Kept so existing hosts still compile.
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

    /// The chat set up at start-up with `WaanguChat.warmUpSelfManaged(configuration:accessToken:)`.
    /// Shows the retry button until that call has been made.
    public init(onClose: (() -> Void)? = nil) {
        self.source = .warmedUp
        self.onClose = onClose
    }

    /// Older form, still supported: the same values as `warmUpSelfManaged`, given again here.
    /// The values from the first call win. Prefer `init(onClose:)`.
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
            if case .provided = source { return }
            guard let chat else { return }
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
        case .warmedUp:
            guard let warmed = await SelfManagedChat.shared.current() else {
                failed = true
                return
            }
            chat = warmed
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

    /// Chat's start-up call, and the only place its configuration and token closure are given.
    /// Call it once from your app's start-up task; then show chat with `WaanguChatView()`. It
    /// builds chat's database, registers its tables and realtime topics and registers the chat
    /// feature, so opening chat only builds the screens. Safe to call again: later calls reuse the
    /// chat from the first one and ignore their values.
    public static func warmUpSelfManaged(
        configuration: WaanguChatConfiguration,
        accessToken: @escaping @Sendable () async -> String?
    ) async {
        let chat = await SelfManagedChat.shared.chat(configuration: configuration, accessToken: accessToken)
        await chat.warmUp()
    }

    /// Sign-out for a host that uses `warmUpSelfManaged` and `WaanguChatView()`: call it when the
    /// user chooses to sign out of your app. It clears the conversations kept on the device and
    /// disconnects. Do not call it when a session expires: the conversations stay.
    public static func signOutSelfManaged() async {
        await SelfManagedChat.shared.signOut()
    }
}
