//
//  CallMoreOptionsSheet.swift
//  FeatureChat
//
//  The sheet behind the ellipsis control on the connected call screens.
//
//  Screen sharing always lives here. Video and mute never do: they have a
//  dedicated control in every call panel, and duplicating them in a sheet put a
//  second control for the same thing somewhere harder to reach.
//
//  Audio output is the one control that comes and goes. The group audio panel
//  is a single row of four and has no slot for it, so that call — and only that
//  call — hands the route picker to this sheet.
//
//  Sharing earns the slot because it cannot go in the pill on a video call: the
//  system picker has no programmatic trigger, so the control has to *host* an
//  `RPSystemBroadcastPickerView`, and the pill's compact icon buttons are too
//  small to overlay one reliably.
//
//  The view emits intent only — the caller decides what each action opens.
//

import SwiftUI
import WaanguCoreKit

struct CallMoreOptionsSheet: View {

    let isVideoCall: Bool
    /// Drives the row between start and stop; sharing is a mode, not an action.
    let isSharingScreen: Bool
    let translationService: (any TranslationServiceProtocol)?

    /// Called to stop an active share, or to start one from an audio call —
    /// that path needs the switch-to-video confirmation first, which the caller
    /// owns. Starting from a call already in video goes through the hosted
    /// picker instead, which reports nothing back.
    var onScreenShare: () -> Void

    /// Reactions and raising a hand are group-call features: they exist to let
    /// somebody signal without talking over a room. A one-to-one has neither
    /// problem, so the sheet does not offer them there.
    var isGroupCall: Bool = false
    var isHandRaised: Bool = false
    var onReaction: (String) -> Void = { _ in }
    var onToggleHand: () -> Void = {}

    /// Set by the caller when the panel behind this sheet has no speaker
    /// control of its own — the group audio call, whose row of four had to give
    /// the slot up. Off everywhere else, so nobody gets two of the same control.
    var showsAudioOutput: Bool = false

    /// Only the host can act on the speaking queue (§16.0 rule 3).
    var isCallHost: Bool = false
    /// The queue, already named and in server order.
    var raisedHands: [CallRaisedHandsEntry] = []
    var onAcknowledgeHand: (String) -> Void = { _ in }

    /// Grabber and title plus one row, so the sheet hugs its content — plus the
    /// group-call rows and one row per raised hand when the host has any.
    private var detentHeight: CGFloat {
        var height: CGFloat = 96 + 72
        if isGroupCall { height += 52 + 72 }
        if showsAudioOutput { height += 72 }
        if showsRaisedHands { height += 44 + CGFloat(raisedHands.count) * 44 }
        return height
    }

    private var showsRaisedHands: Bool {
        isGroupCall && isCallHost && !raisedHands.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            reactionsSection
            handRow
            raisedHandsSection
            audioOutputRow
            screenShareRow
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CallTheme.Palette.canvasElevated)
        .presentationDetents([.height(detentHeight)])
        .presentationDragIndicator(.visible)
    }

    /// The emoji strip, tapped straight from the sheet (§16.2).
    @ViewBuilder
    private var reactionsSection: some View {
        if isGroupCall {
            Text(t(ChatTranslationKeys.CALLS_REACTIONS))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(CallTheme.Palette.secondaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.bottom, 2)

            CallReactionsPicker(onReaction: onReaction)
        }
    }

    /// Raise or lower this device's own hand (§16.1).
    @ViewBuilder
    private var handRow: some View {
        if isGroupCall {
            CallSheetRow(
                icon: isHandRaised ? "hand.raised.slash.fill" : "hand.raised.fill",
                title: isHandRaised
                    ? t(ChatTranslationKeys.CALLS_LOWER_HAND)
                    : t(ChatTranslationKeys.CALLS_RAISE_HAND),
                action: onToggleHand
            )
        }
    }

    /// Hidden for everyone but the host, and hidden entirely when no hand is up
    /// — an empty queue is not worth a row.
    @ViewBuilder
    private var raisedHandsSection: some View {
        if showsRaisedHands {
            CallSheetRow(
                icon: "hand.raised.fill",
                title: "\(t(ChatTranslationKeys.CALLS_RAISED_HANDS)) (\(raisedHands.count))",
                action: {}
            )
            CallRaisedHandsList(
                entries: raisedHands,
                acknowledgeTitle: t(ChatTranslationKeys.CALLS_ACKNOWLEDGE),
                onAcknowledge: onAcknowledgeHand
            )
        }
    }

    /// The system output picker, for the panel that cannot host it itself.
    ///
    /// That is the one-to-one audio panel, whose speaker button answers the
    /// question it is usually asked — earpiece or loudspeaker — in one tap, and
    /// so cannot also be the thing that enumerates Bluetooth and AirPlay.
    @ViewBuilder
    private var audioOutputRow: some View {
        if showsAudioOutput {
            CallAudioRouteRow(
                title: t(ChatTranslationKeys.CALLS_AUDIO_OUTPUT),
                subtitle: t(ChatTranslationKeys.CALLS_AUDIO_OUTPUT_DESC)
            )
        }
    }

    @ViewBuilder
    private var screenShareRow: some View {
        if isSharingScreen {
            CallSheetRow(
                icon: "rectangle.on.rectangle.slash",
                title: t(ChatTranslationKeys.CALLS_STOP_SHARING),
                isDestructive: true,
                action: onScreenShare
            )
        } else if isVideoCall {
            // Already in video, so the picker can open directly. The row is the
            // picker's host rather than a button with an action.
            CallSheetRow(
                icon: "rectangle.inset.filled.and.person.filled",
                title: t(ChatTranslationKeys.CALLS_SHARE_SCREEN),
                subtitle: t(ChatTranslationKeys.CALLS_SHARE_SCREEN_DESC),
                action: {}
            )
            .overlay {
                BroadcastPickerButton()
                    .opacity(0.02)
                    .allowsHitTesting(true)
            }
        } else {
            CallSheetRow(
                icon: "rectangle.inset.filled.and.person.filled",
                title: t(ChatTranslationKeys.CALLS_SHARE_SCREEN),
                subtitle: t(ChatTranslationKeys.CALLS_SHARE_SCREEN_DESC),
                action: onScreenShare
            )
        }
    }

    private var header: some View {
        Text(t(ChatTranslationKeys.CALLS_MORE_TITLE))
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(CallTheme.Palette.primaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 10)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
