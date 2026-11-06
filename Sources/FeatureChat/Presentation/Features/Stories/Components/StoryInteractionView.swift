import SwiftUI
import UIKit

/// Single UIKit gesture surface for status viewing.
/// Owns hold/pause, tap left/right, double-tap react, and drag-up reply.
/// Drag-down dismiss lives on `InteractiveStoryDismissHost` (WhatsAppStories-style).
struct StatusStoryGestureOverlay: UIViewRepresentable {
    var onTapLeft: () -> Void
    var onTapRight: () -> Void
    var onDoubleTap: () -> Void
    var onPressBegan: () -> Void
    var onPressEnded: () -> Void
    var onDragUp: () -> Void
    /// Called when a horizontal page-swipe takes over the touch (TabView).
    var onHorizontalSwipeBegan: () -> Void = {}

    var tapMaxDuration: TimeInterval = 0.5
    var dragUpThreshold: CGFloat = 30
    var directionLockDistance: CGFloat = 8

    func makeUIView(context: Context) -> StatusStoryGestureView {
        let view = StatusStoryGestureView()
        view.backgroundColor = .clear
        view.isMultipleTouchEnabled = false
        view.coordinator = context.coordinator
        view.configureGestures()
        return view
    }

    func updateUIView(_ uiView: StatusStoryGestureView, context: Context) {
        context.coordinator.parent = self
        uiView.coordinator = context.coordinator
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator {
        var parent: StatusStoryGestureOverlay
        var touchStartedAt: Date?
        var touchStartPoint: CGPoint = .zero
        var isPressActive = false
        var didFireDragUp = false
        var lockedAxis: Axis?
        var suppressTap = false
        var lastPressDuration: TimeInterval = 0
        var didTriggerHoldPause = false
        var didNotifyHorizontalSwipe = false
        private var holdPauseWorkItem: DispatchWorkItem?

        /// Only pause after a short hold — quick taps must not pause the timeline.
        private let holdPauseDelay: TimeInterval = 0.14

        enum Axis { case horizontal, vertical }

        init(parent: StatusStoryGestureOverlay) {
            self.parent = parent
        }

        func beginPress() {
            guard !isPressActive else { return }
            isPressActive = true
            touchStartedAt = Date()
            didFireDragUp = false
            lockedAxis = nil
            suppressTap = false
            lastPressDuration = 0
            didTriggerHoldPause = false
            didNotifyHorizontalSwipe = false
            holdPauseWorkItem?.cancel()

            let work = DispatchWorkItem { [weak self] in
                guard let self, self.isPressActive else { return }
                self.didTriggerHoldPause = true
                self.parent.onPressBegan()
            }
            holdPauseWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + holdPauseDelay, execute: work)
        }

        func endPress(resumeIfNeeded: Bool) {
            guard isPressActive else { return }
            holdPauseWorkItem?.cancel()
            holdPauseWorkItem = nil
            lastPressDuration = touchStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            isPressActive = false
            touchStartedAt = nil
            lockedAxis = nil
            if resumeIfNeeded, didTriggerHoldPause {
                parent.onPressEnded()
            }
            didTriggerHoldPause = false
        }

        func noteHorizontalSwipe() {
            guard !didNotifyHorizontalSwipe else { return }
            didNotifyHorizontalSwipe = true
            suppressTap = true
            // Cancel pending hold / clear hold without resuming — paging owns pause.
            holdPauseWorkItem?.cancel()
            holdPauseWorkItem = nil
            if isPressActive {
                isPressActive = false
                touchStartedAt = nil
                if didTriggerHoldPause {
                    parent.onHorizontalSwipeBegan()
                } else {
                    // Hold delay hadn't fired yet — still pause for the swipe.
                    parent.onHorizontalSwipeBegan()
                }
                didTriggerHoldPause = false
            } else {
                parent.onHorizontalSwipeBegan()
            }
        }
    }
}

final class StatusStoryGestureView: UIView, UIGestureRecognizerDelegate {
    weak var coordinator: StatusStoryGestureOverlay.Coordinator?

    private var pan: UIPanGestureRecognizer?
    private var tap: UITapGestureRecognizer?
    private var doubleTap: UITapGestureRecognizer?

    func configureGestures() {
        gestureRecognizers?.forEach { removeGestureRecognizer($0) }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.cancelsTouchesInView = false
        pan.delaysTouchesBegan = false
        pan.delaysTouchesEnded = false
        pan.delegate = self
        addGestureRecognizer(pan)
        self.pan = pan

        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.cancelsTouchesInView = false
        doubleTap.delegate = self
        addGestureRecognizer(doubleTap)
        self.doubleTap = doubleTap

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        tap.delaysTouchesBegan = false
        tap.delegate = self
        tap.require(toFail: doubleTap)
        addGestureRecognizer(tap)
        self.tap = tap
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        isUserInteractionEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        guard let touch = touches.first, let coordinator else { return }
        coordinator.touchStartPoint = touch.location(in: self)
        coordinator.beginPress()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesEnded(touches, with: event)
        if pan?.state == .began || pan?.state == .changed { return }
        // If a horizontal swipe already took over, don't resume here.
        if coordinator?.didNotifyHorizontalSwipe == true {
            coordinator?.endPress(resumeIfNeeded: false)
            return
        }
        coordinator?.endPress(resumeIfNeeded: true)
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesCancelled(touches, with: event)
        // Scroll/TabView stole the touch — keep paused, clear hold, never resume.
        coordinator?.noteHorizontalSwipe()
        coordinator?.endPress(resumeIfNeeded: false)
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard let coordinator, gesture.state == .ended else { return }
        coordinator.suppressTap = true
        coordinator.parent.onDoubleTap()
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard let coordinator, gesture.state == .ended else { return }
        if coordinator.suppressTap {
            coordinator.suppressTap = false
            return
        }
        guard coordinator.lastPressDuration < coordinator.parent.tapMaxDuration else { return }

        let point = gesture.location(in: self)
        if point.x < bounds.midX {
            coordinator.parent.onTapLeft()
        } else {
            coordinator.parent.onTapRight()
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let coordinator else { return }
        let translation = gesture.translation(in: self)

        switch gesture.state {
        case .began, .changed:
            let distance = hypot(translation.x, translation.y)
            if coordinator.lockedAxis == nil, distance >= coordinator.parent.directionLockDistance {
                coordinator.lockedAxis = abs(translation.y) > abs(translation.x) ? .vertical : .horizontal
            }

            if coordinator.lockedAxis == .horizontal {
                coordinator.noteHorizontalSwipe()
                return
            }

            // Only swipe-up reply is handled here.
            guard coordinator.lockedAxis == .vertical else { return }
            guard translation.y < -coordinator.parent.dragUpThreshold else { return }
            guard !coordinator.didFireDragUp else { return }
            coordinator.didFireDragUp = true
            coordinator.parent.onDragUp()

        case .ended, .cancelled, .failed:
            if coordinator.lockedAxis == .horizontal || coordinator.didNotifyHorizontalSwipe {
                // Paging owns pause/resume via isPagingContacts.
                coordinator.endPress(resumeIfNeeded: false)
            } else if coordinator.lockedAxis == .vertical, coordinator.didFireDragUp {
                coordinator.suppressTap = true
                coordinator.endPress(resumeIfNeeded: false)
            } else {
                coordinator.endPress(resumeIfNeeded: true)
            }
            coordinator.didFireDragUp = false
            coordinator.lockedAxis = nil
            coordinator.didNotifyHorizontalSwipe = false
            gesture.setTranslation(.zero, in: self)

        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === pan else { return true }
        let velocity = pan?.velocity(in: self) ?? .zero
        // Only begin for upward intent — downward dismiss is owned by the host.
        if velocity.y > 20 { return false }
        if abs(velocity.x) > abs(velocity.y) * 1.2 { return false }
        return true
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        true
    }
}

/// Legacy left/right hold helper — kept for any remaining call sites.
struct HoldGestureRecognizer: UIViewRepresentable {
    var onTap: () -> Void
    var onPressBegan: () -> Void
    var onPressEnded: () -> Void
    var minimumDuration: TimeInterval = 0.5
    var horizontalDragThreshold: CGFloat = 10.0

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.0
        longPress.allowableMovement = 40
        longPress.cancelsTouchesInView = false
        longPress.delegate = context.coordinator
        view.addGestureRecognizer(longPress)

        context.coordinator.minimumDuration = minimumDuration
        context.coordinator.horizontalDragThreshold = horizontalDragThreshold
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onPressBegan = onPressBegan
        context.coordinator.onPressEnded = onPressEnded
        context.coordinator.minimumDuration = minimumDuration
        context.coordinator.horizontalDragThreshold = horizontalDragThreshold
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, onPressBegan: onPressBegan, onPressEnded: onPressEnded)
    }

    class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onTap: () -> Void
        var onPressBegan: () -> Void
        var onPressEnded: () -> Void
        var minimumDuration: TimeInterval = 0.5
        var horizontalDragThreshold: CGFloat = 10.0
        var pressStartTime: Date?
        var initialLocation: CGPoint?
        var isHorizontalDragging = false
        var didBeginPress = false

        init(onTap: @escaping () -> Void, onPressBegan: @escaping () -> Void, onPressEnded: @escaping () -> Void) {
            self.onTap = onTap
            self.onPressBegan = onPressBegan
            self.onPressEnded = onPressEnded
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            let currentLocation = gesture.location(in: gesture.view)
            switch gesture.state {
            case .began:
                pressStartTime = Date()
                initialLocation = currentLocation
                isHorizontalDragging = false
                didBeginPress = true
                onPressBegan()
            case .changed:
                if let startLocation = initialLocation,
                   abs(currentLocation.x - startLocation.x) > horizontalDragThreshold {
                    isHorizontalDragging = true
                }
            case .ended, .cancelled, .failed:
                if didBeginPress {
                    if !isHorizontalDragging, let startTime = pressStartTime,
                       Date().timeIntervalSince(startTime) < minimumDuration {
                        onTap()
                    }
                    onPressEnded()
                }
                pressStartTime = nil
                initialLocation = nil
                isHorizontalDragging = false
                didBeginPress = false
            default:
                break
            }
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }
}
