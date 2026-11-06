//
//  ReactionPickerView.swift
//

import SwiftUI
import WaanguSharedUI

struct EmojiReaction: Identifiable {
    let id: Int
    let reaction: Reaction
}

struct ReactionPickerView: View {
    let message: MessageDataItem
    let onTapHandler: ((_ selectedEmoji: Reaction) -> Void)

    @State private var animateBackgroundView = false

    private let emojiReactions: [EmojiReaction] = [
        EmojiReaction(id: 0, reaction: .like),
        EmojiReaction(id: 1, reaction: .heart),
        EmojiReaction(id: 2, reaction: .laugh),
        EmojiReaction(id: 3, reaction: .shocked),
        EmojiReaction(id: 4, reaction: .sad),
        EmojiReaction(id: 5, reaction: .pray),
        EmojiReaction(id: 6, reaction: .more),
    ]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(emojiReactions) { item in
                if item.reaction == .more {
                    ReactionMoreButton(entranceIndex: item.reaction.entranceDelayIndex(for: message.direction)) {
                        onTapHandler(.more)
                    }
                } else {
                    ReactionTapEmojiButton(
                        reaction: item.reaction,
                        entranceIndex: item.reaction.entranceDelayIndex(for: message.direction),
                        isSelected: isSelected(item.reaction)
                    ) {
                        onTapHandler(item.reaction)
                    }
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(backgroundView())
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                animateBackgroundView = true
            }
        }
    }

    private func isSelected(_ reaction: Reaction) -> Bool {
        message.currentUserHasReacted
            && message.currentUserReaction == reaction.emoji
    }

    private func backgroundView() -> some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .scaleEffect(animateBackgroundView ? 1 : 0.2, anchor: message.menuAnchor)
            .opacity(animateBackgroundView ? 1 : 0)
    }
}

/// Plain tap target for quick reactions (no Lottie — reliable hit testing in the overlay).
private struct ReactionTapEmojiButton: View {
    let reaction: Reaction
    let entranceIndex: Int
    let isSelected: Bool
    let onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        Button {
            Haptic.impact(.medium)
            onTap()
        } label: {
            Text(reaction.emoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
                .background {
                    if isSelected {
                        Circle()
                            .fill(Color(.systemGray5))
                            .overlay {
                                Circle()
                                    .stroke(AppColors.primary.opacity(0.55), lineWidth: 2)
                            }
                    }
                }
                .scaleEffect(appeared ? 1 : 0.01)
                .opacity(appeared ? 1 : 0)
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(
                .spring(response: 0.38, dampingFraction: 0.62)
                    .delay(0.035 * Double(entranceIndex))
            ) {
                appeared = true
            }
        }
    }
}
