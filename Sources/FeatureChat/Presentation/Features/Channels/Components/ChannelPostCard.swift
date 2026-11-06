//
//  ChannelPostCard.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// One broadcast post.
///
/// Drawn with `applyCommonModifiers` — the chat bubble's own chrome: the sent and
/// received colours, the stroke, the tail, the shadow, the width cap and the
/// directional padding. A post is a message, so it is a bubble, and nothing here
/// re-implements what the bubbles already agree on. Only the footer differs:
/// a channel counts views.
@available(iOS 16.0, *)
struct ChannelPostCard: View {

    let post: MessageDataItem
    /// How many followers have opened this post, counted from read receipts.
    let views: Int
    let translationService: (any TranslationServiceProtocol)?
    let onReact: (Reaction) -> Void
    let onForward: () -> Void

    /// The reactions a channel offers — the app's own values, so a channel
    /// reaction is the same thing as a chat one.
    private static let quickReactions: [Reaction] = [.like, .heart, .laugh, .shocked, .sad, .pray]

    private var isMine: Bool { post.isSentByMe }

    var body: some View {
        VStack(alignment: post.horizontalAlignment, spacing: 8) {
            if !post.message.text.isEmpty {
                Text(post.message.text)
                    .font(.body)
                    .foregroundStyle(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            footer()
        }
        .applyCommonModifiers(message: post)
        .frame(maxWidth: .infinity, alignment: post.alignment)
        .contextMenu {
            ForEach(Self.quickReactions, id: \.rawValue) { reaction in
                Button(reaction.emoji) { onReact(reaction) }
            }

            Button {
                onForward()
            } label: {
                Label(t(ChatTranslationKeys.CHANNELS_FORWARD_POST), systemImage: "arrowshape.turn.up.right")
            }
        }
    }

    /// Reactions, then time, then — on your own posts — how many have seen it
    /// and whether it left the device.
    @ViewBuilder
    private func footer() -> some View {
        HStack(spacing: 8) {
            reactionSummary()

            Spacer(minLength: 4)

            if post.isEdited {
                Text(t(ChatTranslationKeys.CHANNELS_POST_EDITED))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if isMine {
                // Always shown on your own posts, zero included: a channel's
                // author is watching this number, and hiding it at zero looks
                // like the counter is broken rather than like nobody has read it.
                Label("\(views)", systemImage: "eye")
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(.secondary)
            }

            Text(Self.time(post.createdAt))
                .font(.caption2)
                .foregroundStyle(.secondary)

            if isMine {
                MessageStatusIcon(messageStatus: post.status)
                    .frame(width: 16, height: 16)
            }
        }
    }

    /// Existing reactions, grouped by emoji. Nothing is shown when a post has
    /// none — an empty bar reads as a control the reader failed to use.
    @ViewBuilder
    private func reactionSummary() -> some View {
        let grouped = Dictionary(grouping: post.reactions ?? [], by: \.reaction)

        if !grouped.isEmpty {
            HStack(spacing: 6) {
                ForEach(grouped.keys.sorted(), id: \.self) { emoji in
                    HStack(spacing: 3) {
                        Text(emoji)
                            .font(.caption)
                        Text("\(grouped[emoji]?.count ?? 0)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(AppColors.primary.opacity(0.10)))
                }
            }
        }
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: date)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
