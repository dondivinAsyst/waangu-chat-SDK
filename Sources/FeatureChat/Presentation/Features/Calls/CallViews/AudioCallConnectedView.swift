//
//  AudioCallConnectedView.swift
//  FeatureChat
//
//  Connected audio call.
//
//  Doodle-textured canvas, caller identity and live duration in the header,
//  the participant's avatar centred, and a control panel pinned to the bottom.
//
//  The panel comes in two shapes. One-to-one keeps the 2x3 grid: video /
//  speaker / mute on the first row, more / share / end on the second. A group
//  call gets a single row — more / video / speaker / mute / end. The grid of
//  participants above divides whatever height is left between its rows, so a
//  second row of controls would come out of every tile; widening the one row
//  does not. Share moves into the more sheet for those calls.
//
//  Speaker is the same button in both shapes but not the same control: one-to-one
//  it toggles earpiece/loudspeaker directly, and in a group — where the route is
//  forced to loudspeaker anyway — it opens the system output picker.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct AudioCallConnectedView: View {

    @ObservedObject private var voip = VoipManager.shared

    let callerName: String
    let callerImage: String?
    let translationService: (any TranslationServiceProtocol)?

    var onAddParticipant: () -> Void = {}
    var onOpenChat: () -> Void = {}
    var onMore: () -> Void = {}
    var onShare: () -> Void = {}

    init(
        callerName: String,
        callerImage: String?,
        translationService: (any TranslationServiceProtocol)? = nil,
        onAddParticipant: @escaping () -> Void = {},
        onOpenChat: @escaping () -> Void = {},
        onMore: @escaping () -> Void = {},
        onShare: @escaping () -> Void = {}
    ) {
        self.callerName = callerName
        self.callerImage = callerImage
        self.translationService = translationService
        self.onAddParticipant = onAddParticipant
        self.onOpenChat = onOpenChat
        self.onMore = onMore
        self.onShare = onShare
    }

    /// The duration, unless something is wrong — then say what.
    ///
    /// This view previously showed `formattedDuration` unconditionally and never
    /// read `callStatus` at all, so a call that lost its media carried on
    /// counting as though nothing had happened.
    ///
    /// With a single remote there is no tile to carry *their* state either, so
    /// their reconnect takes the timer's place: a duration ticking up beside a
    /// dimmed avatar is the same lie as the one above, told about the other end.
    /// A group keeps the timer — there, the state belongs to its own card.
    private var topSubtitle: String {
        guard voip.callStatus == .connected else {
            return t(voip.callStatus.translationKey)
        }
        if !voip.isGroupCall, voip.isOneToOneRemoteReconnecting {
            return t(ChatTranslationKeys.CALLS_RECONNECTING)
        }
        return voip.formattedDuration
    }

    var body: some View {
        ZStack {
            CallDoodleBackground()

            VStack(spacing: 0) {
                Spacer().frame(height: safeAreaInsets.top + 8)

                CallTopBar(
                    title: groupAwareTitle,
                    subtitle: topSubtitle,
                    onMinimize: { voip.minimize() },
                    onAddParticipant: onAddParticipant,
                    onOpenChat: onOpenChat
                )

                Spacer()

                // A screen share turns an audio call into a video stage. Only this
                // middle section swaps, so the top bar and controls stay put.
                //
                // Otherwise: the same grid as a video call, with avatars where
                // the camera feeds would be — so upgrading an audio call to
                // video does not rearrange the screen under the user.
                if let sharer = voip.screenSharingParticipant(
                    unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN)
                ) {
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
                    .padding(.horizontal, 8)
                } else if voip.isGroupCall {
                    CallParticipantGrid(participants: voip.callGridItems(
                        youLabel: t(ChatTranslationKeys.CALLS_YOU),
                        waitingLabel: t(ChatTranslationKeys.CALLS_CALLING),
                        unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN),
                        ringingLabel: t(ChatTranslationKeys.CALLS_RINGING),
                        reconnectingLabel: t(ChatTranslationKeys.CALLS_RECONNECTING)
                    ))
                        .padding(.horizontal, 12)
                } else {
                    avatar
                }

                Spacer()

                controlPanel
                    .padding(.horizontal, 16)
                    .padding(.bottom, safeAreaInsets.bottom + 16)
            }
            // No PiP anchor here — `CallPictureInPictureHost` owns the window
            // above the call screen, so it survives this view being unmounted.
        }
        .statusBar(hidden: false)
        .alert(
            t(ChatTranslationKeys.CALLS_SHARE),
            isPresented: Binding(
                get: { voip.screenShareErrorKey != nil },
                set: { if !$0 { voip.screenShareErrorKey = nil } }
            )
        ) {
            Button(tCommon("ok"), role: .cancel) { voip.screenShareErrorKey = nil }
        } message: {
            Text(t(voip.screenShareErrorKey ?? ""))
        }
        .animation(.easeInOut(duration: 0.2), value: voip.isOneToOneRemoteReconnecting)
    }

    /// The other person's name one-to-one; how many people, in a group.
    ///
    /// A group lists nobody: every name is already on its own tile, and
    /// repeating them here only competed with the grid for space.
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

    // MARK: - Avatar

    /// The dimming is the whole indicator here — the wording lives in the header,
    /// where it replaces the duration (`topSubtitle`). Saying it in both places
    /// only competed with itself.
    private var avatar: some View {
        CircularProfileImageView(callerImage, size: .custom(210))
            .overlay(
                Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .opacity(voip.isOneToOneRemoteReconnecting ? 0.55 : 1)
            .accessibilityHidden(true)
    }

    // MARK: - Controls

    /// One row in a group, the full 2x3 grid one-to-one — see the file header
    /// for why the group call cannot afford the second row.
    ///
    /// The row keeps the order every other call panel uses: more at the start,
    /// end at the finish, the toggles between them — exactly the video pill's
    /// `more · video · speaker · mic · end`. Speaker used to be dropped here and
    /// left only in the more sheet, which is the one output control a group call
    /// most needs: the route is forced to loudspeaker, so choosing a headset or
    /// AirPlay receiver was two taps away behind a sheet. Five slots in one row
    /// is what the pill already carries, so it costs no second row.
    @ViewBuilder
    private var controlPanel: some View {
        if voip.isGroupCall {
            panelSurface {
                HStack(spacing: 0) {
                    moreButton
                    videoButton
                    speakerButton
                    muteButton
                    endCallButton
                }
            }
        } else {
            panelSurface {
                Grid(horizontalSpacing: 0, verticalSpacing: 22) {
                    GridRow {
                        videoButton
                        speakerButton
                        muteButton
                    }

                    GridRow {
                        moreButton
                        shareButton
                        endCallButton
                    }
                }
            }
        }
    }

    /// The panel's own surface, so both layouts sit on the same material.
    private func panelSurface<Content: View>(
        @ViewBuilder _ content: () -> Content
    ) -> some View {
        content()
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: CallTheme.Metric.panelCornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .environment(\.colorScheme, .dark)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CallTheme.Metric.panelCornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
            )
    }

    // MARK: - Individual controls
    //
    // Declared once each and placed by whichever layout is on screen, so the two
    // panels cannot drift apart in behaviour.

    private var videoButton: some View {
        CallControlButton(
            icon: "video.fill",
            label: t(ChatTranslationKeys.CALLS_VIDEO),
            isActive: voip.hasVideo,
            // Turning video *on* asks first — it puts the user on
            // camera, which is worth confirming. Turning it off is
            // immediate; nobody needs a dialog to stop being seen.
            action: {
                if voip.hasVideo {
                    voip.toggleVideo()
                } else {
                    voip.pendingVideoSwitch = .videoCall
                }
            }
        )
        .frame(maxWidth: .infinity)
    }

    /// Two behaviours, because the two calls have two different questions.
    ///
    /// One-to-one audio is the classic phone case: earpiece or loudspeaker, and
    /// the answer is one tap. `toggleSpeaker` flips it on the spot — routing that
    /// through the system picker made the commonest action on the screen cost a
    /// sheet and a second tap.
    ///
    /// A group call has its route forced to loudspeaker, so a binary toggle there
    /// can change nothing; the real question is *which* output, and only
    /// `AVRoutePickerView` enumerates Bluetooth and AirPlay. Like the broadcast
    /// picker it has to receive the tap itself, so it sits invisibly on top.
    @ViewBuilder
    private var speakerButton: some View {
        if voip.isGroupCall {
            CallControlButton(
                icon: voip.isOnSpeaker ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: t(ChatTranslationKeys.CALLS_SPEAKER),
                isActive: voip.isOnSpeaker,
                action: {}
            )
            .overlay(
                CallAudioRoutePicker()
                    .accessibilityLabel(Text(t(ChatTranslationKeys.CALLS_AUDIO_OUTPUT)))
            )
            .frame(maxWidth: .infinity)
        } else {
            CallControlButton(
                icon: voip.isOnSpeaker ? "speaker.wave.2.fill" : "speaker.slash.fill",
                label: t(ChatTranslationKeys.CALLS_SPEAKER),
                isActive: voip.isOnSpeaker,
                action: { voip.toggleSpeaker() }
            )
            .frame(maxWidth: .infinity)
        }
    }

    private var muteButton: some View {
        CallControlButton(
            icon: voip.isMuted ? "mic.slash.fill" : "mic.fill",
            label: t(ChatTranslationKeys.CALLS_MUTE),
            isActive: voip.isMuted,
            action: { voip.toggleMute() }
        )
        .frame(maxWidth: .infinity)
    }

    private var moreButton: some View {
        CallControlButton(
            icon: "ellipsis",
            label: t(ChatTranslationKeys.CALLS_MORE),
            action: onMore
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var shareButton: some View {
        Group {
            if voip.isSharingScreen {
                // Stopping is programmatic; only starting needs the
                // system picker.
                CallControlButton(
                    icon: "rectangle.on.rectangle.slash.fill",
                    label: t(ChatTranslationKeys.CALLS_SHARE),
                    isActive: true,
                    action: { Task { await voip.endScreenShare() } }
                )
            } else if let reason = voip.screenShareUnavailableReason {
                // The relay never started, so the picker would run a
                // broadcast with nothing listening: the user would sit
                // through the countdown and see no result and no reason.
                // Say why instead of opening it.
                CallControlButton(
                    icon: "rectangle.inset.filled.and.person.filled",
                    label: t(ChatTranslationKeys.CALLS_SHARE),
                    action: { voip.screenShareErrorKey = reason }
                )
            } else {
                // On an audio call the picker is not opened directly:
                // sharing needs the video stage to render into, so the
                // confirmation comes first and hosts the picker itself.
                // On a call that is already video, go straight there.
                CallControlButton(
                    icon: "rectangle.inset.filled.and.person.filled",
                    label: t(ChatTranslationKeys.CALLS_SHARE),
                    // Switches to video first and asks about
                    // broadcasting once the camera is producing.
                    action: { voip.requestScreenShareSwitch() }
                )
                .overlay {
                    // Only the already-video path may open the picker on
                    // this button; otherwise the dialog's own confirm
                    // control carries it.
                    if voip.hasVideo {
                        BroadcastPickerButton()
                            .opacity(0.02)
                            .allowsHitTesting(true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var endCallButton: some View {
        CallControlButton(
            icon: "phone.down.fill",
            label: t(ChatTranslationKeys.CALLS_END),
            role: .destructive,
            action: { voip.endCall() }
        )
        .frame(maxWidth: .infinity)
    }

    // MARK: - Localisation

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    /// Shared strings live in the `common` module, not `chat` — same pattern
    /// as `CallsTabScreen` and `NewCallSheet`.
    private func tCommon(_ key: String) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? key
    }
}
