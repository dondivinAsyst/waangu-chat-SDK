//
//  SwipeToReplyRow.swift
//  FeatureChat
//

import SwiftUI

/// Wraps one message bubble with swipe-to-reply and long-press-to-open-menu.
///
/// The drag offset lives here, on the row, rather than on the message list. It
/// used to be a pair of `@State` values on the list itself — the swiped row's id
/// and its offset — which meant every frame of a swipe re-evaluated the list body
/// and rebuilt every visible bubble, at touch rate. Keeping the offset local means
/// a swipe redraws exactly the row being swiped.
///
/// The iOS 17 and iOS 18 variants this replaces differed only in a coordinate
/// space, a spring curve and how they scheduled a reset, so they are one path now.
@available(iOS 17.0, *)
struct SwipeToReplyRow<Content: View>: View {
    let direction: MessageDirection
    let onReply: () -> Void
    let onLongPress: () -> Void
    @ViewBuilder let content: Content

    @State private var offset: CGFloat = 0

    /// How far the bubble travels at most, and how far it must travel to reply.
    private static var maxOffset: CGFloat { 80 }
    private static var replyThreshold: CGFloat { 50 }
    /// A drag counts as horizontal only if it clearly outruns its vertical
    /// component — otherwise the scroll view should have it.
    private static var horizontalDominance: CGFloat { 1.5 }

    var body: some View {
        content
            .offset(x: offset)
            .gesture(swipeAndLongPress)
    }

    private var swipeAndLongPress: some Gesture {
        let longPress = LongPressGesture(minimumDuration: 0.5)
            .onEnded { _ in onLongPress() }

        let swipe = DragGesture(minimumDistance: 20, coordinateSpace: .local)
            .onChanged { value in
                guard let allowed = allowedOffset(for: value.translation) else { return }
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8, blendDuration: 0.1)) {
                    offset = allowed
                }
            }
            .onEnded { value in
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    offset = 0
                }

                guard let allowed = allowedOffset(for: value.translation),
                      abs(allowed) > Self.replyThreshold else { return }
                onReply()
            }

        return swipe.simultaneously(with: longPress)
    }

    /// The offset this row may take for a given drag, or nil if the drag is not a
    /// swipe-to-reply at all — too vertical, or pulling the wrong way for a bubble
    /// on this side of the thread.
    private func allowedOffset(for translation: CGSize) -> CGFloat? {
        let horizontal = translation.width
        let vertical = translation.height

        guard abs(horizontal) > abs(vertical) * Self.horizontalDominance else { return nil }

        switch direction {
        case .sent:
            guard horizontal < 0 else { return nil }
            return max(horizontal, -Self.maxOffset)
        case .received:
            guard horizontal > 0 else { return nil }
            return min(horizontal, Self.maxOffset)
        }
    }
}
