//
//  BubblePollView.swift
//  FeatureChat
//
//  A poll in the thread: the question, one row per option with its share of the
//  vote, and a way into the full voter list. Tapping an option votes; tapping
//  one you already hold takes the vote back.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

struct BubblePollView: View {
    let message: MessageDataItem
    let isSelectionMode: Bool
    /// Held, not observed: the room view model is a service locator here, and
    /// subscribing every bubble to it re-rendered the whole timeline on any change.
    let chatVM: ChatRoomViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var showVotes = false

    private var poll: PollContent? { message.message.poll }

    private var currentUserId: String { CurrentSessionInfo.shared.currentUid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            messageView()
        }
        .frame(maxWidth: .infinity, alignment: message.alignment)
        .padding(.leading, message.direction == .received ? 5 : 55)
        .padding(.trailing, message.direction == .received ? 55 : 5)
        .id(message.id)
        .chatAppearanceFullScreenCover(isPresented: $showVotes) {
            if let poll {
                PollVotesView(
                    poll: poll,
                    voterDisplay: { chatVM.pollVoterDisplay(for: $0) },
                    translationService: chatVM.translationService
                )
            }
        }
    }

    @ViewBuilder
    private func messageView() -> some View {
        if let poll {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    forwardedIndicator(
                        for: message,
                        forwardedLabel: t(ChatTranslationKeys.FORWARDED)
                    )

                    Text(poll.question)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)

                    if poll.isMultipleChoice {
                        Label(
                            t(ChatTranslationKeys.POLL_SELECT_ONE_OR_MORE),
                            systemImage: "checkmark.circle"
                        )
                        .font(.system(size: 13))
                        .foregroundColor(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                    }

                    VStack(spacing: 10) {
                        ForEach(poll.options) { option in
                            optionRow(option, in: poll)
                        }
                    }

                    Text("\(poll.voterCount) \(t(ChatTranslationKeys.POLL_VOTES_COUNT))")
                        .font(.system(size: 12))
                        .foregroundColor(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                        .padding(.trailing, 72)
                }
                .padding(10)
                .overlay(alignment: .bottomTrailing) {
                    BubbleMetaOverlay(
                        message: message,
                        style: .bubble(colorScheme: colorScheme),
                        translationService: chatVM.translationService
                    )
                    .padding(8)
                }

                if poll.voterCount > 0 {
                    Divider()
                        .background(ChatBubbleStyle.foreground(for: colorScheme).opacity(0.15))

                    Button {
                        guard !isSelectionMode else { return }
                        showVotes = true
                    } label: {
                        Text(t(ChatTranslationKeys.POLL_VIEW_VOTES))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(ChatBubbleStyle.accent(for: colorScheme))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .allowsHitTesting(!isSelectionMode)
                }
            }
            .frame(maxWidth: 280, alignment: .leading)
            .background(message.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .applyTailView(message.direction)
            .applyStrokeOnBubbleView()
            .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
        }
    }

    /// One option. The bar is a share of `voterCount`, not of the vote total:
    /// when everyone picks everything in a multiple-choice poll, every bar
    /// should be full, and dividing by votes would draw them all at half.
    @ViewBuilder
    private func optionRow(_ option: PollOption, in poll: PollContent) -> some View {
        let hasVoted = option.hasVoted(currentUserId)
        let share = poll.voterCount == 0
            ? 0
            : Double(option.voterIds.count) / Double(poll.voterCount)
        let isVotable = !poll.isClosed && !isSelectionMode

        Button {
            guard isVotable else { return }
            chatVM.voteOnPoll(messageId: message.codeMessage, optionId: option.id)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: hasVoted ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundColor(hasVoted
                            ? ChatBubbleStyle.accent(for: colorScheme)
                            : ChatBubbleStyle.foreground(for: colorScheme).opacity(0.4))

                    Text(option.text)
                        .font(.system(size: 15))
                        .foregroundColor(ChatBubbleStyle.foreground(for: colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)

                    Spacer(minLength: 8)

                    PollVoterAvatars(
                        voterIds: option.voterIds,
                        voterDisplay: { chatVM.pollVoterDisplay(for: $0) }
                    )

                    Text("\(option.voterIds.count)")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(ChatBubbleStyle.secondaryForeground(for: colorScheme))
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(ChatBubbleStyle.foreground(for: colorScheme).opacity(0.15))
                        // The option you picked reads at full brand strength;
                        // the others stay legible but recede.
                        Capsule()
                            .fill(ChatBubbleStyle.accent(for: colorScheme).opacity(hasVoted ? 1 : 0.55))
                            .frame(width: max(0, geo.size.width * share))
                    }
                }
                .frame(height: 5)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isVotable)
        .allowsHitTesting(isVotable)
        .animation(.easeOut(duration: 0.2), value: option.voterIds.count)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

/// The overlapping voter faces beside an option.
///
/// Caps at three: the row also carries the option text and the count, and a
/// popular option would otherwise push both off the bubble.
struct PollVoterAvatars: View {
    let voterIds: [String]
    let voterDisplay: (String) -> (name: String, avatar: String?)

    private let maxShown = 3
    private let size: CGFloat = 18

    var body: some View {
        HStack(spacing: -6) {
            ForEach(voterIds.prefix(maxShown), id: \.self) { voterId in
                let display = voterDisplay(voterId)
                PollVoterAvatar(name: display.name, avatar: display.avatar, size: size)
            }
        }
    }
}

/// A voter's face, drawn by the app's shared avatar view so a poll gets the same
/// caching, timeout and placeholder behaviour as every other avatar in the app.
struct PollVoterAvatar: View {
    let name: String
    let avatar: String?
    var size: CGFloat = 18

    var body: some View {
        CircularProfileImageView(avatar, size: .custom(size))
            .overlay(Circle().stroke(Color(.systemBackground).opacity(0.6), lineWidth: 1))
    }
}
