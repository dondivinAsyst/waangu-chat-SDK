//
//  MessageReactionView.swift
//

import SwiftUI

struct MessageReactionView: View {
    let message: MessageDataItem

    @State private var pulse = false

    private var me: String { CurrentSessionInfo.shared.currentUid }

    /// Groups by emoji. Others' reactions first (priority for the person who didn't react), then yours.
    private var groupedReactions: [(emoji: String, count: Int, hasOthers: Bool)] {
        guard let reactions = message.reactions, !reactions.isEmpty else { return [] }

        var counts: [String: (total: Int, others: Int)] = [:]
        for item in reactions {
            var entry = counts[item.reaction] ?? (0, 0)
            entry.total += 1
            if item.userId != me {
                entry.others += 1
            }
            counts[item.reaction] = entry
        }

        return counts
            .map { (emoji: $0.key, count: $0.value.total, hasOthers: $0.value.others > 0) }
            .sorted { lhs, rhs in
                // Priority: emojis that include someone else's reaction first.
                if lhs.hasOthers != rhs.hasOthers { return lhs.hasOthers && !rhs.hasOthers }
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs.emoji < rhs.emoji
            }
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(groupedReactions, id: \.emoji) { item in
                HStack(spacing: 2) {
                    Text(item.emoji)
                    if item.count > 1 {
                        Text("\(item.count)")
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .font(.footnote)
        .padding(4)
        .padding(.horizontal, 2)
        .background(Capsule().fill(.thinMaterial))
        .overlay(
            Capsule().stroke(message.backgroundColor, lineWidth: 2)
        )
        .shadow(
            color: message.backgroundColor.opacity(0.3),
            radius: 5, x: 0, y: 5
        )
        .scaleEffect(pulse ? 1.04 : 1.0)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}
