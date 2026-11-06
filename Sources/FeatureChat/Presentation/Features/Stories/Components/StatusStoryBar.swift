import UIKit
import SwiftUI

// MARK: - Delegate

protocol StatusStoryBarDelegate: AnyObject {
    func statusStoryBarChangedIndex(index: Int)
    func statusStoryBarReachEnd()
    func statusStoryBarReachPrevious()
}

// MARK: - Segment

private final class StatusStorySegment {
    let track = UIView()
    let fill = UIView()
}

// MARK: - StoryBar (matches WhatsAppStories StoryBar)

/// Segmented timeline driven by `UIViewPropertyAnimator` on fill width.
final class StatusStoryBar: UIView {
    weak var delegate: StatusStoryBarDelegate?

    var animatingBarColor: UIColor = .white {
        didSet { updateColors() }
    }
    var nonAnimatingBarColor: UIColor = UIColor.white.withAlphaComponent(0.28) {
        didSet { updateColors() }
    }
    var padding: CGFloat = 2
    var defaultDuration: TimeInterval = 5

    private var segments: [StatusStorySegment] = []
    private(set) var currentAnimationIndex = 0
    private var barAnimation: UIViewPropertyAnimator?
    private var segmentDurations: [TimeInterval] = []
    private var lastLayoutWidth: CGFloat = 0
    /// When `animate` runs before layout has width, retry after the next layout.
    private var pendingStartIndex: Int?

    var segmentCount: Int { segments.count }
    var isRunning: Bool { barAnimation?.isRunning == true }
    var hasActiveAnimator: Bool { barAnimation != nil }

    init(numberOfSegments: Int) {
        super.init(frame: .zero)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        rebuildSegments(count: max(numberOfSegments, 1))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit { stop() }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }

        let widthChanged = abs(bounds.width - lastLayoutWidth) > 0.5
        if widthChanged {
            let fraction = barAnimation?.fractionComplete ?? 0
            let wasRunning = barAnimation?.isRunning == true
            let wasPaused = barAnimation?.state == .active && barAnimation?.isRunning == false

            resetSegmentFrames()
            restoreFillStates(fraction: fraction, wasRunning: wasRunning || wasPaused)
            lastLayoutWidth = bounds.width

            if wasRunning {
                restartAnimator(fromFraction: fraction, paused: false)
            } else if wasPaused {
                restartAnimator(fromFraction: fraction, paused: true)
            }
        }

        if let pending = pendingStartIndex, barAnimation == nil {
            pendingStartIndex = nil
            animate(animationIndex: pending)
        }
    }

    // MARK: - Public API

    func configure(segmentCount: Int, durations: [TimeInterval], startIndex: Int) {
        stop()
        pendingStartIndex = nil
        if segments.count != segmentCount {
            rebuildSegments(count: max(segmentCount, 1))
            lastLayoutWidth = 0
        }
        segmentDurations = durations
        while segmentDurations.count < segments.count {
            segmentDurations.append(defaultDuration)
        }
        resetSegmentsTill(index: startIndex)
    }

    func startAnimation() {
        layoutIfNeeded()
        animate(animationIndex: currentAnimationIndex)
    }

    func pause(hideBar: Bool = true) {
        guard let barAnimation, barAnimation.isRunning else { return }
        if hideBar { hideStoryBar() }
        barAnimation.pauseAnimation()
    }

    func resume() {
        guard let barAnimation, barAnimation.state == .active, !barAnimation.isRunning else { return }
        showStoryBar()
        barAnimation.startAnimation()
    }

    func stop() {
        pendingStartIndex = nil
        guard let barAnimation else { return }
        barAnimation.stopAnimation(true)
        if barAnimation.state == .stopped {
            barAnimation.finishAnimation(at: .current)
        }
        self.barAnimation = nil
    }

    func previous() {
        removeOldAnimation()
        let newIndex = currentAnimationIndex - 1
        if newIndex < 0 {
            delegate?.statusStoryBarReachPrevious()
        } else {
            currentAnimationIndex = newIndex
            removeOldAnimation()
            delegate?.statusStoryBarChangedIndex(index: newIndex)
            animate(animationIndex: newIndex)
        }
    }

    func next() {
        let newIndex = currentAnimationIndex + 1
        if newIndex < segments.count {
            let old = segments[currentAnimationIndex]
            removeOldAnimation(newWidth: old.track.frame.width)
            delegate?.statusStoryBarChangedIndex(index: newIndex)
            animate(animationIndex: newIndex)
        } else {
            delegate?.statusStoryBarReachEnd()
        }
    }

    func jump(to index: Int) {
        stop()
        resetSegmentsTill(index: clamped(index))
        animate(animationIndex: currentAnimationIndex)
    }

    func restartCurrent(duration: TimeInterval) {
        guard segments.indices.contains(currentAnimationIndex) else { return }
        if segmentDurations.indices.contains(currentAnimationIndex) {
            segmentDurations[currentAnimationIndex] = max(0.5, duration)
        }
        removeOldAnimation()
        animate(animationIndex: currentAnimationIndex)
    }

    // MARK: - Private — structure

    private func rebuildSegments(count: Int) {
        segments.forEach {
            $0.track.removeFromSuperview()
            $0.fill.removeFromSuperview()
        }
        segments = (0..<count).map { _ in
            let segment = StatusStorySegment()
            segment.track.clipsToBounds = true
            segment.fill.clipsToBounds = true
            addSubview(segment.track)
            addSubview(segment.fill)
            return segment
        }
        updateColors()
        currentAnimationIndex = 0
    }

    private func updateColors() {
        for segment in segments {
            segment.fill.backgroundColor = animatingBarColor
            segment.track.backgroundColor = nonAnimatingBarColor
        }
    }

    private func resetSegmentFrames() {
        guard bounds.width > 0, !segments.isEmpty else { return }
        let count = CGFloat(segments.count)
        let width = (bounds.width - (padding * (count - 1))) / count
        let height = max(bounds.height, 2)
        let radius = height / 2

        for (index, segment) in segments.enumerated() {
            let x = CGFloat(index) * (width + padding)
            let trackFrame = CGRect(x: x, y: 0, width: width, height: height)
            let fillWidth = min(segment.fill.frame.width, width)
            segment.track.frame = trackFrame
            segment.track.layer.cornerRadius = radius
            segment.fill.frame = CGRect(
                x: trackFrame.minX,
                y: trackFrame.minY,
                width: fillWidth,
                height: height
            )
            segment.fill.layer.cornerRadius = radius
        }
    }

    private func restoreFillStates(fraction: CGFloat, wasRunning: Bool) {
        for index in 0..<segments.count {
            if index < currentAnimationIndex {
                segments[index].fill.frame.size.width = segments[index].track.frame.width
            } else if index > currentAnimationIndex {
                segments[index].fill.frame.size.width = 0
            } else if wasRunning {
                let trackWidth = segments[index].track.frame.width
                segments[index].fill.frame.size.width = trackWidth * CGFloat(fraction)
            }
        }
    }

    private func resetSegmentsTill(index: Int) {
        stop()
        let till = clamped(index)
        currentAnimationIndex = till
        resetSegmentFrames()
        for segmentIdx in 0..<till {
            segments[segmentIdx].fill.frame.size.width = segments[segmentIdx].track.frame.width
        }
        for segmentIdx in till..<segments.count {
            segments[segmentIdx].fill.frame.size.width = 0
        }
    }

    private func removeOldAnimation(newWidth: CGFloat = 0) {
        stop()
        guard segments.indices.contains(currentAnimationIndex) else { return }
        segments[currentAnimationIndex].fill.frame.size.width = newWidth
    }

    private func clamped(_ index: Int) -> Int {
        min(max(index, 0), max(segments.count - 1, 0))
    }

    private func duration(for index: Int) -> TimeInterval {
        guard segmentDurations.indices.contains(index) else { return defaultDuration }
        return max(0.5, segmentDurations[index])
    }

    // MARK: - Private — animation

    private func animate(animationIndex: Int) {
        guard segments.indices.contains(animationIndex) else { return }
        let current = segments[animationIndex]
        currentAnimationIndex = animationIndex
        barAnimation = nil

        layoutIfNeeded()
        var trackWidth = current.track.frame.width
        if trackWidth <= 0, bounds.width > 0 {
            resetSegmentFrames()
            trackWidth = current.track.frame.width
        }
        guard trackWidth > 0 else {
            // Bar not laid out yet — start on next layout pass.
            pendingStartIndex = animationIndex
            setNeedsLayout()
            return
        }

        pendingStartIndex = nil
        showStoryBar()
        current.fill.frame.size.width = 0

        let animDuration = duration(for: animationIndex)
        let animator = UIViewPropertyAnimator(duration: animDuration, curve: .linear) {
            current.fill.frame.size.width = trackWidth
        }
        animator.addCompletion { [weak self] position in
            if position == .end {
                self?.next()
            }
        }
        animator.isUserInteractionEnabled = false
        barAnimation = animator
        animator.startAnimation()
    }

    private func restartAnimator(fromFraction fraction: CGFloat, paused: Bool) {
        guard segments.indices.contains(currentAnimationIndex) else { return }
        stop()

        let current = segments[currentAnimationIndex]
        let trackWidth = current.track.frame.width
        guard trackWidth > 0 else {
            pendingStartIndex = currentAnimationIndex
            return
        }

        let clampedFraction = max(0, min(1, fraction))
        let currentWidth = trackWidth * CGFloat(clampedFraction)
        current.fill.frame.size.width = currentWidth

        let remaining = duration(for: currentAnimationIndex) * TimeInterval(1 - clampedFraction)
        guard remaining > 0.02 else {
            next()
            return
        }

        let animator = UIViewPropertyAnimator(duration: remaining, curve: .linear) {
            current.fill.frame.size.width = trackWidth
        }
        animator.addCompletion { [weak self] position in
            if position == .end {
                self?.next()
            }
        }
        animator.isUserInteractionEnabled = false
        barAnimation = animator
        if paused {
            animator.pauseAnimation()
        } else {
            animator.startAnimation()
        }
    }

    private func showStoryBar() {
        guard alpha < 1 else { return }
        UIView.animate(withDuration: 0.15) { self.alpha = 1 }
    }

    private func hideStoryBar() {
        guard alpha > 0 else { return }
        UIView.animate(withDuration: 0.15) { self.alpha = 0 }
    }
}

// MARK: - Driver

@MainActor
final class StatusStoryTimelineDriver: ObservableObject {
    weak var bar: StatusStoryBar? {
        didSet {
            guard let bar, bar !== oldValue else { return }
            flushPending(to: bar)
        }
    }

    private var pendingConfigure: (segmentCount: Int, durations: [TimeInterval], startIndex: Int)?
    private var pendingStart = false

    func pause(hideBar: Bool = true) { bar?.pause(hideBar: hideBar) }
    func resume() { bar?.resume() }
    func stop() {
        pendingStart = false
        bar?.stop()
    }
    func next() { bar?.next() }
    func previous() { bar?.previous() }
    func jump(to index: Int) { bar?.jump(to: index) }
    func restartCurrent(duration: TimeInterval) { bar?.restartCurrent(duration: duration) }

    func configure(segmentCount: Int, durations: [TimeInterval], startIndex: Int) {
        pendingConfigure = (segmentCount, durations, startIndex)
        if let bar {
            bar.configure(segmentCount: segmentCount, durations: durations, startIndex: startIndex)
            pendingConfigure = nil
        }
    }

    func start() {
        pendingStart = true
        if let bar {
            bar.startAnimation()
            pendingStart = false
        }
    }

    private func flushPending(to bar: StatusStoryBar) {
        if let config = pendingConfigure {
            bar.configure(
                segmentCount: config.segmentCount,
                durations: config.durations,
                startIndex: config.startIndex
            )
            pendingConfigure = nil
        }
        if pendingStart {
            pendingStart = false
            // Defer so the representable has a real frame.
            DispatchQueue.main.async {
                bar.startAnimation()
            }
        }
    }
}

// MARK: - SwiftUI bridge

struct StatusStoryTimelineView: UIViewRepresentable {
    let segmentCount: Int
    let durations: [TimeInterval]
    let startIndex: Int
    let driver: StatusStoryTimelineDriver
    var onIndexChanged: (Int) -> Void
    var onReachEnd: () -> Void
    var onReachPrevious: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onIndexChanged: onIndexChanged,
            onReachEnd: onReachEnd,
            onReachPrevious: onReachPrevious
        )
    }

    func makeUIView(context: Context) -> StatusStoryBar {
        let bar = StatusStoryBar(numberOfSegments: max(segmentCount, 1))
        bar.delegate = context.coordinator
        bar.padding = 2
        bar.animatingBarColor = .white
        bar.nonAnimatingBarColor = UIColor.white.withAlphaComponent(0.28)
        bar.configure(
            segmentCount: max(segmentCount, 1),
            durations: durations.isEmpty ? [5] : durations,
            startIndex: startIndex
        )
        context.coordinator.configuredCount = max(segmentCount, 1)
        // Assign last so pending configure/start from onAppear flushes cleanly.
        driver.bar = bar
        return bar
    }

    func updateUIView(_ uiView: StatusStoryBar, context: Context) {
        context.coordinator.onIndexChanged = onIndexChanged
        context.coordinator.onReachEnd = onReachEnd
        context.coordinator.onReachPrevious = onReachPrevious
        uiView.delegate = context.coordinator
        if driver.bar !== uiView {
            driver.bar = uiView
        }

        let count = max(segmentCount, 1)
        if context.coordinator.configuredCount != count {
            context.coordinator.configuredCount = count
            uiView.configure(
                segmentCount: count,
                durations: durations.isEmpty ? [5] : durations,
                startIndex: startIndex
            )
        }
    }

    final class Coordinator: StatusStoryBarDelegate {
        var onIndexChanged: (Int) -> Void
        var onReachEnd: () -> Void
        var onReachPrevious: () -> Void
        var configuredCount: Int = 0

        init(
            onIndexChanged: @escaping (Int) -> Void,
            onReachEnd: @escaping () -> Void,
            onReachPrevious: @escaping () -> Void
        ) {
            self.onIndexChanged = onIndexChanged
            self.onReachEnd = onReachEnd
            self.onReachPrevious = onReachPrevious
        }

        func statusStoryBarChangedIndex(index: Int) {
            onIndexChanged(index)
        }

        func statusStoryBarReachEnd() {
            onReachEnd()
        }

        func statusStoryBarReachPrevious() {
            onReachPrevious()
        }
    }
}
