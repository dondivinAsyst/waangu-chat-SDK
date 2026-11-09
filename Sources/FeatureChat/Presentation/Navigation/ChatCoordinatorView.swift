//
//  ChatCoordinatorView.swift
//  FeatureChat
//
//  Main chat coordinator view with TabView
//  Updated to use new TabStackCoordinator pattern
//

import SwiftUI
import Combine
import WaanguCoreKit

@available(iOS 16.0, *)
public struct ChatCoordinatorView: View {
    

    
    @ObservedObject var coordinator: ChatCoordinator
    @ObservedObject private var globalAudioManager = GlobalAudioPlaybackManager.shared
    @ObservedObject private var appState = AppState.shared
    @ObservedObject private var voip = VoipManager.shared
    @State private var localeToken: Int = 0
    /// Banner is deferred until the full CallScreen has finished dismissing,
    /// so the two never share the screen during the minimise transition.
    @State private var isMinimizedBannerPresented = false
    /// Picture-in-Picture outlives the call screen, so it is owned here rather
    /// than inside the view that minimising unmounts.
    @StateObject private var pip = CallPictureInPictureController()
    /// Mic/camera prompts once per Chat session when the inbox becomes visible.
    @State private var didPrimeCallCapturePermissions = false
    
    // MARK: - Init
    
    public init(coordinator: ChatCoordinator ) {

        self.coordinator = coordinator
       
    }
    
    // MARK: - Body
    
    private var modules: Set<ChatModule> { coordinator.feature.enabledModules }

    public var body: some View {
        Group {
            if coordinator.isAuthenticated {
                mainChatView
                    .onAppear {
                        primeCallCapturePermissionsIfNeeded()
                    }
            } else {
//                mainChatView
                authInitView
            }
        }
        .globalChatAppearance()
        .environment(\.chatEnabledModules, modules)
        .onAppear {
            ChatAppearanceStore.shared.reloadFromPersistence()
            syncMinimizedBannerPresentation(animated: false)
        }
    }

    private func primeCallCapturePermissionsIfNeeded() {
        guard !didPrimeCallCapturePermissions else { return }
        didPrimeCallCapturePermissions = true
        Task {
            await coordinator.feature.primeCallCapturePermissions()
        }
    }
    
    // MARK: - Auth Init View
    
    private var authInitView: some View {
        ChatAuthInitView(
            viewModel: coordinator.feature.makeChatAuthInitViewModel(),
            translationService: coordinator.feature.translationService,
            onClose: {
                coordinator.exitToMainApp()
            },
            onAuthSuccess: {
                coordinator.handleAuthSuccess()
            }
        )
    }
    
    // MARK: - Main Chat View

    /// Full CallScreen for any non-idle phase that has not been folded to the banner.
    private var isCallScreenVisible: Bool {
        voip.callPhase != .idle && !voip.isMinimized
    }

    /// Live call folded into the top banner (never during `.ended` / `.idle`).
    ///
    /// A minimised video call belongs in the floating window instead — but only
    /// once that window is actually coming. PiP does not exist in the Simulator
    /// and can fail on device, and a video call that minimised into neither a
    /// banner nor a window would be a live call with no way back to it.
    private var shouldShowMinimizedBanner: Bool {
        guard voip.isMinimized, voip.callPhase.showsLiveCallChrome else { return false }
        guard voip.minimizesToPictureInPicture else { return true }
        return !pip.isRunningOrStarting
    }

    private var mainChatView: some View {
        ZStack {
            VStack(spacing: 0) {

                // Minimised call banner, above the mini player so an ongoing
                // call always stays the topmost piece of persistent chrome.
                if isMinimizedBannerPresented {
                    CallMinimizedBanner(
                        callerName: voip.displayName,
                        duration: voip.formattedDuration,
                        isVideo: voip.hasVideo,
                        translationService: coordinator.feature.translationService,
                        onTap: { voip.expand() },
                        onEnd: {
                            if case .incomingRinging = voip.callPhase {
                                voip.declineCall()
                            } else {
                                voip.endCall()
                            }
                        }
                    )
                    .transition(
                        .move(edge: .top)
                            .combined(with: .opacity)
                    )
                }

                // Mini player as part of VStack
                // Pushes content down naturally
                if globalAudioManager.showMiniPlayer {
                    MiniAudioPlayerView(globalManager: globalAudioManager)
                        .transition(
                            .move(edge: .top)
                                .combined(with: .opacity)
                        )
                }
                
                // Main TabView content using new coordinators
                TabView(selection: $coordinator.selectedTab) {
                    
                    if Tab.updates.isEnabled(in: modules) {
                        ChatTabsFactory
                            .makeUpdatesTab(
                                coordinator: coordinator.updatesTabCoordinator
                            )
                            .tabItem {
                                Label(
                                    tabTitle(for: .updates),
                                    systemImage: Tab.updates.icon
                                )
                            }
                            .tag(Tab.updates)
                    }
                    
                    if Tab.calls.isEnabled(in: modules) {
                        ChatTabsFactory
                            .makeCallsTab(
                                coordinator: coordinator.callsTabCoordinator
                            )
                            .tabItem {
                                Label(
                                    tabTitle(for: .calls),
                                    systemImage: Tab.calls.icon
                                )
                            }
                            .tag(Tab.calls)
                    }
                    
                    if Tab.communities.isEnabled(in: modules) {
                        ChatTabsFactory
                            .makeCommunitiesTab(
                                coordinator: coordinator.communitiesTabCoordinator
                            )
                            .tabItem {
                                Label(
                                    tabTitle(for: .communities),
                                    systemImage: Tab.communities.icon
                                )
                            }
                            .tag(Tab.communities)
                    }
                    
                    ChatTabsFactory
                        .makeChatsTab(
                            coordinator: coordinator.chatsTabCoordinator
                        )
                     
                        .tabItem {
                            Label(
                                tabTitle(for: .chats),
                                systemImage: Tab.chats.icon
                            )
                        }
                        .tag(Tab.chats)
                    
                    ChatTabsFactory
                        .makeSettingsTab(
                            coordinator: coordinator.settingsTabCoordinator
                        )
                        .tabItem {
                            Label(
                                tabTitle(for: .settings),
                                systemImage: Tab.settings.icon
                            )
                        }
                        .tag(Tab.settings)
                }
                .id(localeToken)
            }
            .animation(
                .spring(response: 0.3),
                value: globalAudioManager.showMiniPlayer
            )
            .animation(
                .spring(response: 0.3),
                value: isMinimizedBannerPresented
            )

            // Animate only the CallScreen appearance/disappearance
            Group {
                if isCallScreenVisible {
                    CallScreen(feature: coordinator.feature)
                        // Slides away downwards on minimise and back up on
                        // restore, so the banner reads as the same call folded up.
                        .transition(
                            .asymmetric(
                                insertion: .move(edge: .bottom).combined(with: .opacity),
                                removal: .opacity
                            )
                        )
                        .zIndex(999)
                        .ignoresSafeArea()
                }
            }
            .animation(
                .easeOut(duration: 0.28),
                value: isCallScreenVisible
            )

            // Mounted for the life of the shell so minimising has something to
            // hand the call to. Invisible and 1x1 — see the host.
            CallPictureInPictureHost(pip: pip)
        }
        .onChange(of: voip.isMinimized) { _, _ in
            syncMinimizedBannerPresentation(animated: true)
        }
        .onChange(of: voip.callPhase) { _, _ in
            syncMinimizedBannerPresentation(animated: true)
        }
        // PiP failing (or being unavailable at all) is what promotes the banner
        // from "not needed" to "the only chrome this call has".
        .onChange(of: pip.isRunningOrStarting) { _, _ in
            syncMinimizedBannerPresentation(animated: true)
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSNotification.Name("DeepLinkRoute")
            )
        ) { notification in
            // Deep link handling removed
            // Implement in main app
            debugLog("[ChatCoordinator] Received deep link notification")
        }
        .chatAppearanceSheet(isPresented: $coordinator.isPresentingShare) {
            shareSelectionView()
        }
        // Push financier : l'objet est relu au serveur avant tout affichage.
        .sheet(item: $coordinator.presentedFinancialObject) { presented in
            FinancialObjectEntryView(
                reference: presented.reference,
                surface: coordinator.feature.financeSurface,
                onDismiss: { coordinator.presentedFinancialObject = nil }
            )
        }
        // Invitation à un canal : aperçu et adhésion, code validé au serveur (B08).
        .sheet(item: $coordinator.presentedChannelInvite) { invite in
            ChannelJoinPreviewSheet(
                viewModel: ChannelJoinViewModel(
                    inviteCode: invite.inviteCode,
                    channelUseCases: coordinator.feature.channelUseCases
                )
            )
        }
        // Lien de paiement : inspecté au serveur, puis payé par devis et confirmation.
        .sheet(item: $coordinator.presentedPaymentLink) { link in
            PaymentLinkOpenView(
                token: link.token, nonce: link.nonce,
                surface: coordinator.feature.financeSurface,
                objectReader: coordinator.feature.financialObjectUseCases,
                onDismiss: { coordinator.presentedPaymentLink = nil }
            )
        }
        .onReceive(
            NotificationCenter.default.publisher(
                for: Notification.Name("TranslationKit.localeDidChange")
            )
        ) { _ in
            localeToken += 1
        }
    }

    /// Hide the banner immediately when expanding; show it only after CallScreen
    /// has finished its dismiss animation when minimizing from full screen.
    /// Incoming-as-banner (never showed CallScreen) appears immediately.
    private func syncMinimizedBannerPresentation(animated: Bool) {
        if shouldShowMinimizedBanner {
            let deferMs: UInt64 = {
                // Never delay the first appearance of an incoming ring banner.
                if case .incomingRinging = voip.callPhase { return 0 }
                // Minimising an expanded call: wait for CallScreen fade-out.
                return animated ? 300_000_000 : 0
            }()

            Task { @MainActor in
                if deferMs > 0 {
                    try? await Task.sleep(nanoseconds: deferMs)
                }
                guard shouldShowMinimizedBanner else { return }
                if animated {
                    withAnimation(.spring(response: 0.3)) {
                        isMinimizedBannerPresented = true
                    }
                } else {
                    isMinimizedBannerPresented = true
                }
            }
        } else if isMinimizedBannerPresented {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    isMinimizedBannerPresented = false
                }
            } else {
                isMinimizedBannerPresented = false
            }
        }
    }
    
    // MARK: - Share Selection View
    
    private func shareSelectionView() -> some View {
        NavigationStack {
            ShareContactPickerView(
                coordinator: coordinator,
                onDismiss: {
                    coordinator.dismissShare()
                }
            )
        }
    }

    private func tabTitle(for tab: Tab) -> String {
        let key: String = switch tab {
        case .updates: ChatTranslationKeys.STORIES_UPDATES_TITLE
        case .calls: ChatTranslationKeys.CALLS_TITLE
        case .communities: ChatTranslationKeys.COMMUNITIES_TITLE
        case .chats: ChatTranslationKeys.CHAT_LIST_TITLE
        case .settings: ChatTranslationKeys.SETTINGS_TITLE
        }
        return coordinator.feature.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? tab.rawValue.capitalized
    }
}

enum Tab: String {
    case updates
    case calls
    case communities
    case chats
    case settings

    /// The module that owns this tab, if any. Chats and Settings are always there.
    var module: ChatModule? {
        switch self {
        case .updates:     return .status
        case .calls:       return .calls
        case .communities: return .communities
        case .chats, .settings: return nil
        }
    }

    func isEnabled(in modules: Set<ChatModule>) -> Bool {
        module.map(modules.contains) ?? true
    }

    /// The tab a link to this one lands on: itself, or Chats when its module is off.
    func landing(in modules: Set<ChatModule>) -> Tab {
        isEnabled(in: modules) ? self : .chats
    }
    
    var title: String {
        rawValue.capitalized
    }
    
    var icon: String {
        switch self {
        case .updates:
            return "circle.dashed.inset.filled"
            
        case .calls:
            return "phone"
            
        case .communities:
            return "person.3"
            
        case .chats:
            return "message"
            
        case .settings:
            return "gear"
        }
    }
}



