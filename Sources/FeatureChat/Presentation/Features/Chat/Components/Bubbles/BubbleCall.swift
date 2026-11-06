import SwiftUI
import WaanguCoreKit

enum BubbleCallTone: Equatable {
    case neutral
    case danger

    static func forOutcome(_ outcome: CallOutcome?, isMissedFallback: Bool) -> Self {
        switch outcome {
        case .missed, .failed:
            return .danger
        case .none:
            return isMissedFallback ? .danger : .neutral
        default:
            return .neutral
        }
    }
}

struct BubbleCallView: View {
    let message: MessageDataItem
    let isSelectionMode: Bool
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @Environment(\.colorScheme) private var systemColorScheme
    /// Without the calls module a call bubble is history only: it cannot be redialled.
    @Environment(\.chatEnabledModules) private var enabledModules
    @State private var timeFormatToken = 0
    @State private var showsRedialSheet = false

    /// Prefer the chat appearance setting over ambient environment — message
    /// list wallpaper / UIKit hosts can leave `\ColorScheme` stuck on light.
    private var colorScheme: ColorScheme {
        appearanceStore.defaultAppearance.resolvedColorScheme(system: systemColorScheme)
    }

    /// Who was on that call, taken from the message itself so it reflects the
    /// call as it happened rather than the conversation as it is now.
    ///
    /// Falls back to the other party when the message predates participants
    /// being recorded — those older logs have an empty roster.
    private var redialParticipants: [CallInvitee] {
        let recorded = (message.message.call?.participants ?? [])
            .filter { !$0.phone.isEmpty }
            .map {
                CallInvitee(
                    // Older messages recorded no account id; the phone is the
                    // only identity they have.
                    userId: $0.userId ?? $0.phone,
                    name: displayName(name: $0.name, phone: $0.phone, userId: $0.userId),
                    phone: $0.phone
                )
            }

        guard recorded.isEmpty else { return recorded }
        guard let peer = otherParty else { return [] }
        return [peer]
    }

    /// The person on the other end of a one-to-one call.
    ///
    /// An incoming call names its caller on the message. An outgoing one names
    /// nobody — a message has a `senderName` and no receiver name — so this used
    /// to fall back to printing the number, which is why a cancelled call showed
    /// a phone where a missed call showed a name. The room already knows who it
    /// is with, and for a one-to-one call that is the same person.
    private var otherParty: CallInvitee? {
        if isOutgoing {
            let receiver = chatVM.currentReceiverUser
            // `receiverId` is an account id, never a phone — passing it as one
            // is what put an identifier in the number line.
            let phone = receiver?.phone ?? ""
            let userId = nonEmpty(receiver?.userId) ?? nonEmpty(message.receiverId) ?? phone
            guard !phone.isEmpty || !userId.isEmpty else { return nil }
            return CallInvitee(
                userId: userId,
                name: displayName(name: receiver?.name, phone: phone, userId: userId),
                phone: phone
            )
        }

        let phone = message.senderPhone
        guard !phone.isEmpty else { return nil }
        return CallInvitee(
            userId: nonEmpty(message.senderId) ?? phone,
            name: displayName(name: message.senderName, phone: phone, userId: message.senderId),
            phone: phone
        )
    }

    /// Name, else number, else a translated "Unknown user" — never an id.
    private func displayName(name: String?, phone: String?, userId: String?) -> String {
        ChatDisplayName.text(
            name: name,
            phone: phone,
            identifiers: [userId ?? "", chatVM.conversationId],
            translator: chatVM.translationService
        )
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private var redialAvatars: [String?] {
        guard redialParticipants.count == 1 else {
            return redialParticipants.map { _ in nil }
        }
        // The outgoing side has a face too — it is the person whose room this is.
        return [isOutgoing ? chatVM.currentReceiverUser?.avatar : message.senderAvatar]
    }

    private var isMissed: Bool {
        message.typeMessage == .MISSING_CALL_AUDIO || message.typeMessage == .MISSING_CALL_VIDEO
    }

    private var isVideo: Bool {
        message.typeMessage == .CALL_VIDEO || message.typeMessage == .MISSING_CALL_VIDEO
    }

    private var isOutgoing: Bool {
        message.senderId == CurrentSessionInfo.shared.currentUid
    }

    private var iconName: String {
        if isMissed {
            return isVideo ? "video.slash.fill" : "phone.down.fill"
        }
        return isVideo ? "video.fill" : "phone.fill"
    }

    private var tone: BubbleCallTone {
        BubbleCallTone.forOutcome(outcome, isMissedFallback: outcome == nil && isMissed)
    }

    private var accentColor: Color {
        tone == .danger ? .red : ChatBubbleStyle.foreground(for: colorScheme)
    }

    private var secondaryColor: Color {
        ChatBubbleStyle.secondaryForeground(for: colorScheme)
    }

    private var innerCardBackground: Color {
        ChatBubbleStyle.mutedOverlay(for: colorScheme)
    }

    private var innerCardBorder: Color {
        tone == .danger
            ? Color.red.opacity(colorScheme == .dark ? 0.35 : 0.22)
            : Color.white.opacity(colorScheme == .dark ? 0.12 : 0)
    }

    /// What actually happened, when the message recorded it.
    ///
    /// The message type only says connected or not, so on its own an outgoing
    /// unconnected call is indistinguishable from a cancelled one — which is why
    /// a server failure used to read as "Cancelled".
    private var outcome: CallOutcome? {
        guard let raw = message.message.call?.outcome else { return nil }
        return CallOutcome(rawValue: raw)
    }

    private var title: String {
        let kind = isVideo
            ? t(ChatTranslationKeys.CALLS_VIDEO_CALL)
            : t(ChatTranslationKeys.CALLS_AUDIO_CALL)

        switch outcome {
        case .answered:
            return kind
        case .failed:
            return t(ChatTranslationKeys.CALLS_BUBBLE_FAILED, args: [kind])
        case .declined:
            return t(ChatTranslationKeys.CALLS_BUBBLE_DECLINED, args: [kind])
        case .busy:
            return t(ChatTranslationKeys.CALLS_BUBBLE_BUSY, args: [kind])
        case .noAnswer:
            return t(ChatTranslationKeys.CALLS_BUBBLE_NO_ANSWER, args: [kind])
        case .cancelled:
            return t(ChatTranslationKeys.CALLS_BUBBLE_CANCELLED, args: [kind])
        case .missed:
            return t(ChatTranslationKeys.CALLS_BUBBLE_MISSED, args: [kind])
        case .none:
            // Older messages carry no outcome — fall back to the one bit the
            // message type does provide.
            if isMissed {
                return isOutgoing
                    ? t(ChatTranslationKeys.CALLS_BUBBLE_CANCELLED, args: [kind])
                    : t(ChatTranslationKeys.CALLS_BUBBLE_MISSED, args: [kind])
            }
            return kind
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args)
            .value ?? key
    }

    private var subtitle: String {
        let direction = isOutgoing ? "Outgoing" : "Incoming"

        if let call = message.message.call,
           let start = call.participants?.first?.startedAt,
           let end = call.participants?.first?.endAt {
            let seconds = Int(end.timeIntervalSince(start))
            return "\(direction) · \(formattedDuration(seconds))"
        }

        if isMissed {
            return message.bubbleTime
        }

        let durationText = extractDuration(from: message.message.text)
        if let dur = durationText {
            return "\(direction) · \(dur)"
        }
        return "\(direction) · \(message.bubbleTime)"
    }

    var body: some View {
        HStack {
            if message.direction == .sent {
                Spacer()
            }

            // Bubble content — background/clip applied here only, not to the outer HStack
            VStack(alignment: .leading, spacing: 0) {
                // Forwarded indicator inside the bubble
                forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")

                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(tone == .danger ? 0.16 : 0.10))
                            .frame(width: 38, height: 38)

                        Image(systemName: iconName)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(accentColor)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(tone == .danger ? .red : ChatBubbleStyle.foreground(for: colorScheme))

                        HStack(spacing: 4) {
                            Image(systemName: isOutgoing ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(tone == .danger ? .red : secondaryColor)

                            Text(subtitle)
                                .font(.caption)
                                .foregroundColor(secondaryColor)
                        }
                    }

                    Spacer()

                    if enabledModules.contains(.calls) {
                        Button {
                            openRedial()
                        } label: {
                            Image(systemName: isVideo ? "video.fill" : "phone.fill")
                                .font(.system(size: 16))
                                .foregroundColor(accentColor)
                        }
                        .allowsHitTesting(!isSelectionMode)
                    } else {
                        Image(systemName: isVideo ? "video.fill" : "phone.fill")
                            .font(.system(size: 16))
                            .foregroundColor(secondaryColor)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.top, message.forwarded == true ? 2 : 7)
                .padding(.bottom, 7)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(innerCardBackground)
                )
                // .overlay(
                //     RoundedRectangle(cornerRadius: 14, style: .continuous)
                //         .stroke(innerCardBorder, lineWidth: 1)
                // )
                // .shadow(
                //     color: Color.black.opacity(colorScheme == .dark ? 0.10 : 0.05),
                //     radius: 6,
                //     x: 0,
                //     y: 2
                // )
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
            }
            .background(message.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .applyStrokeOnBubbleView()
            .applyTailView(message.direction)
            .shadow(
                color: Color.black.opacity(colorScheme == .dark ? 0.12 : 0.06),
                radius: 10,
                x: 0,
                y: 6
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            // The whole bubble redials, not just the icon at its edge. The icon
            // stays as the affordance; it is a Button, so it keeps handling its
            // own taps and this gesture never sees them.
            .onTapGesture { openRedial() }
            .allowsHitTesting(!isSelectionMode)
            .frame(maxWidth: UIScreen.main.bounds.width * 0.55, alignment: message.alignment)

            if message.direction == .received {
                // No forward button for call bubbles
            }
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .padding(.leading, message.direction == .received ? 10 : 60)
        .padding(.trailing, message.direction == .received ? 60 : 10)
        .id("\(message.id)-\(timeFormatToken)")
        .onReceive(
            NotificationCenter.default.publisher(for: ChatTimeFormatting.didChangeNotification)
        ) { _ in
            timeFormatToken += 1
        }
        .chatAppearanceSheet(isPresented: $showsRedialSheet) {
            CallRedialSheet(
                participants: redialParticipants,
                avatars: redialAvatars,
                translationService: chatVM.translationService,
                onCall: { hasVideo in
                    ChatKeyboard.hide()
                    VoipManager.shared.startGroupCall(
                        redialParticipants,
                        hasVideo: hasVideo,
                        // Redialling from inside a thread stays in that thread.
                        conversationId: chatVM.conversationId
                    )
                }
            )
        }
    }

    /// Opens the roster sheet. A group call cannot be repeated from a single
    /// handle, so the participants are shown first and the user picks voice or
    /// video — the same flow for a one-to-one call.
    private func openRedial() {
        guard !isSelectionMode, enabledModules.contains(.calls) else { return }
        hideKeyboard()
        showsRedialSheet = true
    }

    private func formattedDuration(_ totalSeconds: Int) -> String {
        if totalSeconds < 60 {
            return "\(totalSeconds)s"
        }
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return s > 0 ? "\(m)m \(s)s" : "\(m)m"
    }

    private func extractDuration(from text: String) -> String? {
        if let range = text.range(of: "·") {
            let after = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return after.isEmpty ? nil : after
        }
        return nil
    }
}
