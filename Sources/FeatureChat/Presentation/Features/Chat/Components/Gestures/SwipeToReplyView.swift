//
//  SwipeToReplyView.swift
//  Pods
//
//  Created by Don divin on 2/9/26.
//

import SwiftUI
import UIKit

// MARK: - UIKit Gesture Overlay (ScrollView-friendly)

/// A transparent UIKit overlay that hosts both a `UIPanGestureRecognizer`
/// (for swipe-to-reply) and a `UILongPressGestureRecognizer` (for context menu)
/// on the **same** UIView so they don't block each other.
/// Vertical pans are cancelled immediately, letting the parent `UIScrollView` scroll.
private struct MessageGestureOverlay: UIViewRepresentable {
    var onPanChanged: (CGFloat) -> Void
    var onPanEnded: (CGFloat, CGFloat) -> Void   // (translation.x, velocity.x)
    var onPanCancelled: () -> Void
    var onLongPress: (() -> Void)?
    var longPressDuration: TimeInterval

    func makeUIView(context: Context) -> GesturePassthroughView {
        let view = GesturePassthroughView()
        view.backgroundColor = .clear

        // Pan gesture for swipe-to-reply
        let pan = UIPanGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePan(_:))
        )
        pan.delegate = context.coordinator
        view.addGestureRecognizer(pan)

        // Long press gesture for context menu
        if onLongPress != nil {
            let lp = UILongPressGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.handleLongPress(_:))
            )
            lp.minimumPressDuration = longPressDuration
            lp.cancelsTouchesInView = false
            lp.delaysTouchesBegan = false
            lp.delegate = context.coordinator
            view.addGestureRecognizer(lp)
        }

        return view
    }

    func updateUIView(_ uiView: GesturePassthroughView, context: Context) {
        context.coordinator.onPanChanged = onPanChanged
        context.coordinator.onPanEnded = onPanEnded
        context.coordinator.onPanCancelled = onPanCancelled
        context.coordinator.onLongPress = onLongPress
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onPanChanged: (CGFloat) -> Void
        var onPanEnded: (CGFloat, CGFloat) -> Void
        var onPanCancelled: () -> Void
        var onLongPress: (() -> Void)?

        private var isDirectionLocked = false
        private var isHorizontal = false

        init(_ parent: MessageGestureOverlay) {
            self.onPanChanged = parent.onPanChanged
            self.onPanEnded = parent.onPanEnded
            self.onPanCancelled = parent.onPanCancelled
            self.onLongPress = parent.onLongPress
        }

        // Allow all gestures (scroll, pan, long press) to work simultaneously
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            return true
        }

        @objc func handlePan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)

            switch gesture.state {
            case .changed:
                let dx = abs(translation.x)
                let dy = abs(translation.y)

                if !isDirectionLocked {
                    let total = dx + dy
                    guard total > 10 else { return }

                    if dx > dy * 1.5 {
                        isDirectionLocked = true
                        isHorizontal = true
                    } else {
                        // Vertical — cancel so the ScrollView handles it
                        isDirectionLocked = true
                        isHorizontal = false
                        gesture.state = .cancelled
                        return
                    }
                }

                guard isHorizontal else { return }
                onPanChanged(translation.x)

            case .ended:
                if isHorizontal {
                    let velocity = gesture.velocity(in: view).x
                    onPanEnded(translation.x, velocity)
                } else {
                    onPanCancelled()
                }
                resetState()

            case .cancelled, .failed:
                if isHorizontal {
                    onPanCancelled()
                }
                resetState()

            default:
                break
            }
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            if gesture.state == .began {
                onLongPress?()
            }
        }

        private func resetState() {
            isDirectionLocked = false
            isHorizontal = false
        }
    }
}

/// A UIView subclass that passes through taps to SwiftUI views underneath
/// (e.g. buttons, onTapGesture) while still receiving pan and long-press events
/// via its own gesture recognizers.
private class GesturePassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Only claim the touch if one of our gesture recognizers is active
        // (state == .began or .changed). Otherwise return nil so taps pass through.
        let hasActiveGesture = gestureRecognizers?.contains { gr in
            gr.state == .began || gr.state == .changed
        } ?? false

        if hasActiveGesture {
            return super.hitTest(point, with: event)
        }

        // Still return self so our gesture recognizers get a chance to start,
        // but mark the view as "transparent" to the responder chain for taps.
        return super.hitTest(point, with: event)
    }

    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        return bounds.contains(point)
    }
}

// MARK: - SwipeToReplyView

struct SwipeToReplyView<Content: View>: View {
    let content: Content
    let onReply: () -> Void
    let direction: MessageDirection
    var onLongPress: (() -> Void)?

    @State private var offset: CGFloat = 0
    @State private var didTrigger = false

    private let replyThreshold: CGFloat = 60
    private let maxSwipeDistance: CGFloat = 100

    private var swipeProgress: CGFloat {
        min(abs(offset) / replyThreshold, 1.0)
    }

    init(
        direction: MessageDirection,
        onReply: @escaping () -> Void,
        onLongPress: (() -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.direction = direction
        self.onReply = onReply
        self.onLongPress = onLongPress
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: direction == .received ? .leading : .trailing) {
            // Background indicator
            if offset != 0 {
                HStack {
                    if direction == .received {
                        Image(systemName: "arrowshape.turn.up.left.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.black.opacity(0.5))
                            .opacity(swipeProgress)
                            .padding(.leading, 16)
                            .offset(x: offset - 100)
                        Spacer()
                    } else {
                        Spacer()
                        Image(systemName: "arrowshape.turn.up.right.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.black.opacity(0.5))
                            .opacity(swipeProgress)
                            .padding(.trailing, 16)
                            .offset(x: offset + 100)
                    }
                }
            }

            content
                .offset(x: offset)
                .animation(
                    .interactiveSpring(response: 0.3, dampingFraction: 0.7, blendDuration: 0.3),
                    value: offset
                )
                .overlay {
                    MessageGestureOverlay(
                        onPanChanged: { translationX in
                            handleDragChanged(translationX)
                        },
                        onPanEnded: { translationX, velocityX in
                            handleDragEnded(translationX: translationX, velocityX: velocityX)
                        },
                        onPanCancelled: {
                            resetOffset()
                        },
                        onLongPress: onLongPress,
                        longPressDuration: 0.5
                    )
                }
        }
    }

    // MARK: - Gesture Handling

    private func handleDragChanged(_ translationX: CGFloat) {
        let calculatedOffset: CGFloat
        switch direction {
        case .received:
            calculatedOffset = min(max(0, translationX), maxSwipeDistance)
        case .sent:
            calculatedOffset = max(min(0, translationX), -maxSwipeDistance)
        }

        let easedOffset = applyEasing(to: calculatedOffset, maxDistance: maxSwipeDistance)
        offset = easedOffset

        let crossedThreshold = abs(offset) > replyThreshold
        if crossedThreshold && !didTrigger {
            didTrigger = true
            Haptic.impact(.medium)
        } else if !crossedThreshold {
            didTrigger = false
        }
    }

    private func handleDragEnded(translationX: CGFloat, velocityX: CGFloat) {
        let shouldTrigger = abs(offset) > replyThreshold || abs(velocityX) > 800

        if shouldTrigger && didTrigger {
            withAnimation(.spring(response: 0.2, dampingFraction: 0.6)) {
                offset = direction == .received ? maxSwipeDistance * 1.1 : -maxSwipeDistance * 1.1
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                onReply()
                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                    offset = 0
                }
            }
        } else {
            resetOffset()
        }

        didTrigger = false
    }

    private func resetOffset() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            offset = 0
        }
        didTrigger = false
    }

    private func applyEasing(to offset: CGFloat, maxDistance: CGFloat) -> CGFloat {
        let normalized = abs(offset) / maxDistance
        let eased = normalized * normalized * (3 - 2 * normalized)
        return offset > 0 ? eased * maxDistance : -eased * maxDistance
    }
}
