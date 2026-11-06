import SwiftUI
import WaanguCoreKit

struct CallScreen: View {
    @ObservedObject private var voip = VoipManager.shared
    @StateObject private var sheets = CallSheetPresentationViewModel()

    /// Needed for the in-call sheets: the add-participant picker reuses the
    /// feature's shared contact picker view model rather than loading its own.
    let feature: ChatFeature
    let translationService: (any TranslationServiceProtocol)?

    init(feature: ChatFeature) {
        self.feature = feature
        self.translationService = feature.translationService
    }

    private var name: String { voip.displayName }
    private var image: String? { voip.callerProfileImage }

    var body: some View {
        callPhaseContent
            // The switch-to-video / start-sharing confirmation lives here rather
            // than inside a call view, because the share flow deliberately
            // switches to video *before* asking — which swaps
            // `AudioCallConnectedView` out for `VideoCallView` underneath it.
            // Owned by either view, the dialog would be destroyed by the very
            // transition it is waiting on.
            .overlay {
                if let intent = voip.pendingVideoSwitch {
                    SwitchToVideoDialog(
                        intent: intent,
                        translationService: translationService,
                        onConfirm: {
                            voip.pendingVideoSwitch = nil
                            // Video is already on by this point for the share
                            // flow; this only matters for a plain upgrade.
                            if !voip.hasVideo { voip.toggleVideo() }
                        },
                        onCancel: { voip.pendingVideoSwitch = nil }
                    )
                }
            }
            // Call sheets follow the call chrome, not the chat appearance
            // preference — see `callAppearanceSheet`.
            .callAppearanceSheet(item: $sheets.activeSheet) { sheet in
                sheetContent(for: sheet)
            }
            // A call can end while a sheet is up — from the remote party hanging
            // up or from CallKit — and the sheet would outlive the call screen.
            .onChange(of: voip.callPhase) { _, phase in
                if !phase.isActive { sheets.dismiss() }
            }
    }

    /// One `VideoCallView` for the whole video session — phase changes only
    /// update subtitle/layout inside the view, they do not recreate it.
    private var showsVideoCallLayout: Bool {
        switch voip.callPhase {
        case .outgoingRinging, .connecting:
            return voip.isVideoCall
        case .connected(let isVideo):
            return isVideo || voip.isVideoCall
        default:
            return false
        }
    }

    /// Animate entering/leaving the call shell, not every status tick mid-call.
    private var callShellTransition: Int {
        switch voip.callPhase {
        case .idle: return 0
        case .incomingRinging: return 1
        case .ended: return 3
        default: return 2
        }
    }

    @ViewBuilder
    private var callPhaseContent: some View {
        ZStack {
            if showsVideoCallLayout {
                videoCallView
                    .id(voip.activeCallUUID)
            }

            switch voip.callPhase {
            case .incomingRinging(_, let isVideo):
                IncomingCallView(
                    callerName: name,
                    callerImage: image,
                    isVideo: isVideo,
                    translationService: translationService
                )
                .transition(.opacity)

            case .outgoingRinging, .connecting, .connected:
                if !showsVideoCallLayout {
                    if case .connected = voip.callPhase {
                        AudioCallConnectedView(
                            callerName: name,
                            callerImage: image,
                            translationService: translationService,
                            onAddParticipant: { sheets.present(.addParticipant) },
                            onMore: { sheets.present(.moreOptions) }
                        )
                        .transition(.opacity)
                    } else {
                        OutgoingRingingView(
                            callerName: name,
                            callerImage: image,
                            isVideo: voip.hasVideo,
                            translationService: translationService,
                            onAddParticipant: { sheets.present(.addParticipant) },
                            onMore: { sheets.present(.moreOptions) }
                        )
                        .transition(.opacity)
                    }
                }

            case .ended:
                CallEndedView(
                    callerName: name,
                    callerImage: image,
                    translationService: translationService
                )
                .transition(.opacity)

            case .idle:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: callShellTransition)
    }

    private var videoCallView: some View {
        VideoCallView(
            callerName: name,
            callerImage: image,
            translationService: translationService,
            onAddParticipant: { sheets.present(.addParticipant) },
            onMore: { sheets.present(.moreOptions) }
        )
    }

    // MARK: - Sheets

    @ViewBuilder
    private func sheetContent(for sheet: CallSheet) -> some View {
        switch sheet {
        case .moreOptions:
            CallMoreOptionsSheet(
                isVideoCall: voip.isVideoCall,
                isSharingScreen: voip.isSharingScreen,
                translationService: translationService,
                onScreenShare: {
                    sheets.dismiss()
                    if voip.isSharingScreen {
                        Task { await voip.endScreenShare() }
                    } else {
                        // Audio call: sharing needs the video stage, so the
                        // confirmation comes first. The sheet has to close before
                        // the dialog can appear over the call.
                        voip.requestScreenShareSwitch()
                    }
                },
                isGroupCall: voip.isGroupCall,
                isHandRaised: voip.isHandRaised,
                onReaction: { emoji in
                    // Closed first: the reaction animates on the tiles behind
                    // the sheet, and it lasts 2.5s.
                    sheets.dismiss()
                    voip.sendReaction(emoji)
                },
                onToggleHand: {
                    sheets.dismiss()
                    voip.toggleHandRaise()
                },
                // The one-to-one audio panel is the only one whose speaker button
                // is a plain earpiece/loudspeaker toggle, so it is the only one
                // that cannot reach a headset or AirPlay receiver on its own. The
                // video pill and the group row both carry the system picker.
                showsAudioOutput: !showsVideoCallLayout && !voip.isGroupCall,
                isCallHost: voip.isCallHost,
                raisedHands: voip.raisedHands.map { peerKey in
                    CallRaisedHandsEntry(
                        peerId: peerKey,
                        name: voip.displayNameForRaisedHand(
                            peerKey,
                            youLabel: t(ChatTranslationKeys.CALLS_YOU),
                            unknownLabel: t(ChatTranslationKeys.CALLS_UNKNOWN)
                        )
                    )
                },
                onAcknowledgeHand: { voip.acknowledgeHand(peerId: $0) }
            )

        case .addParticipant:
            CallAddParticipantSheet(
                pickerViewModel: feature.makeChatPartnerPickerViewModel(),
                alreadyInCall: voip.activeParticipantPhones,
                occupiedSlots: voip.participantCount,
                maxParticipants: VoipManager.maxParticipants,
                translationService: translationService,
                onConfirm: { contacts in
                    voip.invitePeers(
                        contacts.map {
                            CallInvitee(userId: $0.userId, name: $0.name, phone: $0.phone)
                        }
                    )
                }
            )
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

struct CircleButtonView: View {
    var isDeleted: Bool = false
    var systemName: String
    var color: Color = Color(.systemGray2)
    var isActive: Bool = false
    var action: () -> Void = {}
    
    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isDeleted ? Color.red : (isActive ? Color.white.opacity(0.3) : Color.gray.opacity(0.45)))
                    .frame(
                        width: UIScreen.main.bounds.width * 0.12,
                        height: UIScreen.main.bounds.width * 0.12
                    )
                Image(systemName: systemName)
                    .foregroundColor(color)
                    .font(.system(size: 22))
            }
        }
    }
}
