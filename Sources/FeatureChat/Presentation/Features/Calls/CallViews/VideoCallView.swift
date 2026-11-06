//
//  VideoCallView.swift
//  FeatureChat
//
//  Connected video call.
//
//  Layout (1:1):
//  - Ringing/connecting → local camera fills the stage, no PiP.
//  - Connected → remote is primary; local floats as PiP (camera or avatar+wave).
//  - Tap the PiP tile to swap primary ↔ PiP.
//
//  Camera off keeps this screen with avatar / waveform, not audio-only UI.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct VideoCallView: View {

    @ObservedObject private var voip = VoipManager.shared
    @ObservedObject private var camera: CallCameraController
    @StateObject private var chrome = CallControlsVisibilityViewModel()

    let callerName: String
    let callerImage: String?
    let translationService: (any TranslationServiceProtocol)?

    var onAddParticipant: () -> Void = {}
    var onOpenChat: () -> Void = {}
    var onMore: () -> Void = {}
    var onFlipCamera: () -> Void = {}
    var onToggleEffects: () -> Void = {}

    /// `nil` = automatic (local primary until remote video exists).
    /// Set only when the user taps the PiP tile.
    @State private var userPinnedLocalAsPrimary: Bool? = nil

    init(
        callerName: String,
        callerImage: String?,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAddParticipant: @escaping () -> Void = {},
        onOpenChat: @escaping () -> Void = {},
        onMore: @escaping () -> Void = {},
        onFlipCamera: @escaping () -> Void = {},
        onToggleEffects: @escaping () -> Void = {}
    ) {
        self.callerName = callerName
        self.callerImage = callerImage
        self.translationService = translationService
        self.onAddParticipant = onAddParticipant
        self.onOpenChat = onOpenChat
        self.onMore = onMore
        self.onFlipCamera = onFlipCamera
        self.onToggleEffects = onToggleEffects
        _camera = ObservedObject(wrappedValue: VoipManager.shared.fallbackCamera)
    }

    /// Local fills the stage while ringing/connecting; remote is primary once connected.
    private var isLocalPrimary: Bool {
        if let userPinnedLocalAsPrimary { return userPinnedLocalAsPrimary }
        return !isConnected
    }

    private var isConnected: Bool {
        if case .connected = voip.callPhase { return true }
        return false
    }

    /// The duration, unless something is wrong — then say what.
    ///
    /// A status other than `.connected` outranks the timer even while the phase
    /// is connected. Showing the duration regardless is what left a call that
    /// had lost its transport counting quietly upwards, which reads as a healthy
    /// call; the timer keeps running underneath and resumes at the right value.
    /// The duration, unless something is wrong — then say what.
    ///
    /// With a single remote their reconnect takes the timer's place: there is no
    /// tile of their own to carry it, and a duration ticking up over a stalled
    /// stage reads as a call that is still fine. A group keeps the timer — there
    /// the state belongs to the card of whoever dropped.
    private var topSubtitle: String {
        guard isConnected, voip.callStatus == .connected else {
            return t(voip.callStatus.translationKey)
        }
        if !voip.isGroupCall, voip.isOneToOneRemoteReconnecting {
            return t(ChatTranslationKeys.CALLS_RECONNECTING)
        }
        return voip.formattedDuration
    }

    var body: some View {
        ZStack {
            primaryStage

            // Above UIKit video (which eats touches), below PiP / chrome.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture { chrome.toggle() }

            if chrome.isVisible {
                chromeOverlay
                    .transition(.opacity)
            }

            // Above chrome so avatar PiP taps always reach swap (chrome Spacer
            // would otherwise eat hits in the middle of the screen).
            if showsFloatingPiP {
                floatingPiP
            }

            // No PiP anchor here. It used to live in this view, which is the one
            // minimising unmounts — so the window died exactly when it was
            // wanted. `CallPictureInPictureHost` holds it above the call screen.
        }
        .animation(CallTheme.Motion.controlsFade, value: chrome.isVisible)
        .animation(CallTheme.Motion.pipSnap, value: isLocalPrimary)
        .statusBar(hidden: !chrome.isVisible)
        .onAppear {
            chrome.show()
            Task {
                await Task.yield()
                voip.ensureLocalVideoPreview()
            }
        }
        .onDisappear {
            chrome.cancelPendingHide()
        }
        .onChange(of: voip.hasVideo) { _, hasVideo in
            if hasVideo {
                voip.ensureLocalVideoPreview()
            } else {
                voip.stopFallbackCameraPreview()
            }
        }
        .onChange(of: voip.localVideoTrack?.trackId) { _, trackId in
            if trackId != nil {
                voip.stopFallbackCameraPreview()
                voip.markLocalPreviewReady()
            } else if voip.hasVideo {
                voip.ensureLocalVideoPreview()
            }
        }
        .onChange(of: camera.status) { _, status in
            switch status {
            case .running, .denied, .failed:
                voip.markLocalPreviewReady()
            case .idle:
                break
            }
        }
    }

    /// The other person's name one-to-one; how many people, in a group.
    private var groupAwareTitle: String {
        guard voip.isGroupCall else {
            return voip.oneToOneTitle(unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN))
        }
        let count = t(
            ChatTranslationKeys.CALLS_PARTICIPANT_COUNT,
            args: ["\(voip.participantCount)"]
        )
        return "\(t(ChatTranslationKeys.CALLS_GROUP_CALL)) · \(count)"
    }

    // MARK: - Tracks

    private var remoteTrack: (any CallVideoTrackProtocol)? {
        voip.oneToOneRemoteVideoTrack()
    }

    private var hasLiveLocalCamera: Bool {
        voip.hasVideo && (voip.localVideoTrack != nil || camera.status == .running)
    }

    private var showsSelfPreviewOverlay: Bool {
        voip.isGroupCall || voip.isAnyoneSharingScreen
    }

    /// PiP stays visible when connected — camera on (live feed) or off (avatar).
    private var showsFloatingPiP: Bool {
        !showsSelfPreviewOverlay && isConnected
    }

    /// Flip in the top bar when local fills the main stage (swap / ringing).
    private var showsLocalPrimaryFlipButton: Bool {
        isLocalPrimary && !showsSelfPreviewOverlay && hasLiveLocalCamera
    }

    // MARK: - Primary / PiP stages (1:1)

    @ViewBuilder
    private var primaryStage: some View {
        ZStack {
            CallTheme.Palette.canvasElevated.ignoresSafeArea()

            if let sharer = voip.screenSharingParticipant(
                unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN)
            ) {
                screenShareStage(sharer)
            } else if voip.isGroupCall {
                CallParticipantGrid(participants: voip.callGridItems(
                    youLabel: t(ChatTranslationKeys.CALLS_YOU),
                    waitingLabel: t(ChatTranslationKeys.CALLS_CALLING),
                    unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN),
                    ringingLabel: t(ChatTranslationKeys.CALLS_RINGING),
                    reconnectingLabel: t(ChatTranslationKeys.CALLS_RECONNECTING)
                ))
                    .padding(.horizontal, 8)
                    .padding(.top, safeAreaInsets.top + 56)
                    .padding(.bottom, safeAreaInsets.bottom + (chrome.isVisible ? 190 : 24))
            } else if isLocalPrimary {
                localFeed(isCompact: false)
                    .ignoresSafeArea()
            } else if let remoteTrack {
                CallVideoTrackView(track: remoteTrack, fillsBounds: true)
                    .id(remoteTrack.trackId)
                    .ignoresSafeArea()
            } else if isConnected {
                CallRemoteParticipantStage(
                    // The peer actually on the call, not the name the call was
                    // placed under — they differ once a group shrinks to two.
                    name: voip.oneToOneTitle(
                        unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN)
                    ),
                    avatarURL: callerImage,
                    isMuted: voip.isOneToOneRemoteMuted,
                    isCompact: false,
                    audioLevel: voip.oneToOneAudioLevel,
                    color: voip.oneToOneColor,
                    isReconnecting: voip.isOneToOneRemoteReconnecting
                )
                .ignoresSafeArea()
            } else {
                remotePlaceholder
            }
        }
    }

    private var floatingPiP: some View {
        CallSelfPreviewPiP(
            isCompact: !chrome.isVisible,
            showsInlineControls: chrome.isVisible && isLocalFeedInPiP && hasLiveLocalCamera,
            onTap: {
                // Swap only from the PiP tile — never from the main stage.
                chrome.registerInteraction()
                withAnimation(CallTheme.Motion.pipSnap) {
                    userPinnedLocalAsPrimary = !isLocalPrimary
                }
            },
            onFlipCamera: flipLocalCamera,
            onToggleEffects: {
                chrome.registerInteraction()
                onToggleEffects()
            }
        ) {
            pipFeedContent
        }
        .padding(.top, safeAreaInsets.top + 60)
        .padding(.bottom, safeAreaInsets.bottom + (chrome.isVisible ? 130 : 20))
    }

    private func flipLocalCamera() {
        chrome.registerInteraction()
        if voip.localVideoTrack != nil {
            voip.switchCamera()
        } else {
            camera.flip()
        }
        onFlipCamera()
    }

    /// Flip / effects only make sense when the floating tile shows the local camera.
    private var isLocalFeedInPiP: Bool {
        !isLocalPrimary
    }

    @ViewBuilder
    private var pipFeedContent: some View {
        if isLocalPrimary {
            // Local is on the main stage → PiP shows remote (or their avatar).
            if let remoteTrack {
                CallVideoTrackView(track: remoteTrack, fillsBounds: true)
                    .id("pip-\(remoteTrack.trackId)")
            } else {
                CallRemoteParticipantStage(
                    // The peer actually on the call, not the name the call was
                    // placed under — they differ once a group shrinks to two.
                    name: voip.oneToOneTitle(
                        unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN)
                    ),
                    avatarURL: callerImage,
                    isMuted: voip.isOneToOneRemoteMuted,
                    isCompact: true,
                    audioLevel: voip.oneToOneAudioLevel,
                    color: voip.oneToOneColor,
                    isReconnecting: voip.isOneToOneRemoteReconnecting
                )
            }
        } else {
            localFeed(isCompact: true)
        }
    }

    @ViewBuilder
    private func localFeed(isCompact: Bool) -> some View {
        if voip.hasVideo, let localTrack = voip.localVideoTrack {
            CallVideoTrackView(track: localTrack, isMirrored: true, fillsBounds: true)
                .id(localTrack.trackId)
        } else if voip.hasVideo, camera.status == .running {
            CallCameraPreview(
                session: camera.session,
                isMirrored: camera.position == .front
            )
        } else if voip.hasVideo, camera.status == .idle {
            localCameraStartingPlaceholder
        } else {
            let profile = CurrentSessionInfo.shared.userProfile
            CallLocalParticipantStage(
                name: CurrentSessionInfo.shared.userName,
                avatarURL: profile.isEmpty ? nil : profile,
                isMuted: voip.isMuted,
                isCompact: isCompact,
                audioLevel: voip.localAudioLevel,
                color: voip.localColor
            )
        }
    }

    private var localCameraStartingPlaceholder: some View {
        ZStack {
            CallTheme.Palette.canvasElevated
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white.opacity(0.7))
        }
    }

    private func screenShareStage(_ sharer: CallParticipantGridItem) -> some View {
        VStack(spacing: 10) {
            Spacer().frame(height: safeAreaInsets.top + 56)

            CallParticipantTile(
                name: sharer.name,
                avatarURL: sharer.avatarURL,
                track: sharer.track,
                isMuted: sharer.isMuted,
                isSharingScreen: true,
                showsName: true,
                hasRaisedHand: sharer.hasRaisedHand,
                reaction: sharer.reaction
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            filmstrip

            Spacer().frame(height: safeAreaInsets.bottom + (chrome.isVisible ? 130 : 16))
        }
        .padding(.horizontal, 8)
    }

    private var filmstrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(voip.callGridItems(
                    youLabel: t(ChatTranslationKeys.CALLS_YOU),
                    waitingLabel: t(ChatTranslationKeys.CALLS_CALLING),
                    unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN),
                    ringingLabel: t(ChatTranslationKeys.CALLS_RINGING),
                    reconnectingLabel: t(ChatTranslationKeys.CALLS_RECONNECTING)
                ).filter { !$0.isSharingScreen }) { item in
                    CallParticipantTile(
                        name: item.name,
                        avatarURL: item.avatarURL,
                        track: item.track,
                        isMuted: item.isMuted,
                        isMirrored: item.isLocal,
                        isWaiting: item.isWaiting,
                        waitingLabel: item.waitingLabel,
                        isRinging: item.isRinging,
                        isReconnecting: item.isReconnecting,
                        reconnectingLabel: item.reconnectingLabel,
                        showsName: true,
                        hasRaisedHand: item.hasRaisedHand,
                        reaction: item.reaction
                    )
                    .frame(width: 96, height: 128)
                }
            }
            .padding(.horizontal, 2)
        }
        .frame(height: 128)
    }

    private var remotePlaceholder: some View {
        VStack(spacing: 14) {
            CircularProfileImageView(callerImage, size: .custom(chrome.isVisible ? 190 : 150))

            CallConnectingDots()
                .opacity(chrome.isVisible ? 0 : 1)

            Text(callerName)
                .font(CallTheme.TextStyle.remoteNameLarge)
                .foregroundStyle(CallTheme.Palette.remoteName)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 32)
        }
        .animation(CallTheme.Motion.controlsFade, value: chrome.isVisible)
    }

    // MARK: - Chrome

    private var chromeOverlay: some View {
        VStack(spacing: 0) {
            CallTopBar(
                title: groupAwareTitle,
                subtitle: topSubtitle,
                onMinimize: { voip.minimize() },
                onAddParticipant: {
                    chrome.registerInteraction()
                    onAddParticipant()
                },
                onOpenChat: {
                    chrome.registerInteraction()
                    onOpenChat()
                },
                showsFlipCamera: showsLocalPrimaryFlipButton,
                onFlipCamera: flipLocalCamera
            )
            .padding(.top, safeAreaInsets.top + 8)

            Spacer()

            controlPill
                .padding(.horizontal, 14)
                .padding(.bottom, safeAreaInsets.bottom + 14)
        }
        // Only the bar / pill capture taps; empty space passes through to PiP / chrome toggle.
        // (Spacer itself is already non-interactive; this documents the intent.)
    }

    private var controlPill: some View {
        HStack(spacing: 0) {
            CallControlButton(
                icon: "ellipsis",
                style: .pill,
                action: {
                    chrome.registerInteraction()
                    onMore()
                }
            )
            .frame(maxWidth: .infinity)

            CallControlButton(
                icon: voip.hasVideo ? "video.fill" : "video.slash.fill",
                style: .pill,
                isActive: voip.hasVideo,
                action: {
                    chrome.registerInteraction()
                    voip.toggleVideo()
                }
            )
            .frame(maxWidth: .infinity)

            // Opens the system output picker rather than toggling — on a video
            // call the speaker route is forced, so the old toggle could not
            // change anything. The picker reaches earpiece, Bluetooth and
            // AirPlay, and must receive the tap itself.
            CallControlButton(
                icon: voip.isOnSpeaker ? "speaker.wave.2.fill" : "speaker.slash.fill",
                style: .pill,
                isActive: voip.isOnSpeaker,
                action: { chrome.registerInteraction() }
            )
            .overlay(CallAudioRoutePicker())
            .frame(maxWidth: .infinity)

            CallControlButton(
                icon: voip.isMuted ? "mic.slash.fill" : "mic.fill",
                style: .pill,
                isActive: voip.isMuted,
                action: {
                    chrome.registerInteraction()
                    voip.toggleMute()
                }
            )
            .frame(maxWidth: .infinity)

            CallControlButton(
                icon: "phone.down.fill",
                style: .pill,
                role: .destructive,
                action: { voip.endCall() }
            )
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 12)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .environment(\.colorScheme, .dark)
        )
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        )
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// `CallConnectingDots` lives in CallViews/Components — the waiting tiles in the
// participant grid show the same indicator.
