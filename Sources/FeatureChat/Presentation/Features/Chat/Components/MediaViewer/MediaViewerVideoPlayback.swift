import AVFoundation
import WaanguCoreKit
import UIKit

/// `AVPlayerLayer` host for a video page: play/pause control, scrubber and
/// elapsed/total time.
///
/// Deliberately not `AVPlayerViewController`: its own chrome and gesture handling
/// fight the pager and the drag-to-dismiss recognizer.
final class MediaViewerVideoPlayback: UIView {

    private enum Layout {
        static let controlPointSize: CGFloat = 64
        /// Clearance under the scrubber before the controller reports the real
        /// chrome footer height — roughly a caption-less footer.
        static let defaultBottomInset: CGFloat = 76
        /// Breathing room between the scrubber and whatever sits below it.
        static let bottomGap: CGFloat = 12
        static let sideInset: CGFloat = 16
        static let progressTickInterval: TimeInterval = 0.2
        static let fadeDuration: TimeInterval = 0.2
        static let unavailableAlpha: CGFloat = 0.4
    }

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    private var playerLayer: AVPlayerLayer? { layer as? AVPlayerLayer }
    private var player: AVPlayer?
    private var url: URL?
    private var configuredDuration: TimeInterval?

    private let playButton = UIButton(type: .system)
    private let scrubberRow = UIView()
    private let slider = UISlider()
    private let elapsedLabel = UILabel()
    private let totalLabel = UILabel()

    private var timeControlObservation: NSKeyValueObservation?
    private var periodicObserver: Any?
    private var endObserver: NSObjectProtocol?

    private var isScrubbing = false
    private var controlsVisible = true

    /// Set when the item reaches its end. `play()` on a finished item is a no-op,
    /// so without rewinding first the control looks dead on the second tap.
    private var hasReachedEnd = false

    private var bottomInsetConstraint: NSLayoutConstraint?

    /// Fires when playback actually starts or stops, driven by KVO on
    /// `timeControlStatus` rather than by the call that requested it: `AVPlayer`
    /// sits in `.waitingToPlayAtSpecifiedRate` for a runloop turn or more after
    /// `play()`, so reading the status straight after the call always answers
    /// "not playing" and the control never flips.
    var onPlaybackStateChanged: ((Bool) -> Void)?

    /// Fires on any touch of the controls so the owner can restart its auto-hide
    /// countdown.
    var onInteraction: (() -> Void)?

    /// `.waitingToPlayAtSpecifiedRate` counts as playing: the user asked for
    /// playback, so the pause affordance belongs on screen while the first
    /// frames buffer.
    var isPlaying: Bool {
        guard let player else { return false }
        return player.timeControlStatus != .paused
    }

    /// Distance the scrubber keeps above the bottom safe area, so it clears the
    /// viewer footer instead of sitting under the share and delete buttons.
    var controlsBottomInset: CGFloat = Layout.defaultBottomInset {
        didSet {
            guard controlsBottomInset != oldValue else { return }
            bottomInsetConstraint?.constant = -(controlsBottomInset + Layout.bottomGap)
        }
    }

    private var isAvailable: Bool { url != nil }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaViewerVideoPlayback is created in code only")
    }

    /// Only the controls consume touches; everything else falls through to the
    /// page's scroll view so tap-to-toggle-chrome still works over a video.
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        if hit === self || hit === scrubberRow { return nil }
        return hit
    }

    // MARK: - Setup

    private func setUpViews() {
        playerLayer?.videoGravity = .resizeAspect

        playButton.tintColor = UIColor.white.withAlphaComponent(0.9)
        playButton.addTarget(self, action: #selector(togglePlayback), for: .touchUpInside)
        playButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(playButton)

        scrubberRow.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrubberRow)

        configureTimeLabel(elapsedLabel)
        configureTimeLabel(totalLabel)

        slider.minimumValue = 0
        slider.maximumValue = 1
        slider.minimumTrackTintColor = .white
        slider.maximumTrackTintColor = UIColor.white.withAlphaComponent(0.3)
        slider.thumbTintColor = .white
        slider.translatesAutoresizingMaskIntoConstraints = false
        slider.addTarget(self, action: #selector(scrubbingBegan), for: .touchDown)
        slider.addTarget(self, action: #selector(scrubbingChanged), for: .valueChanged)
        slider.addTarget(self, action: #selector(scrubbingEnded), for: [.touchUpInside, .touchUpOutside, .touchCancel])

        scrubberRow.addSubview(elapsedLabel)
        scrubberRow.addSubview(slider)
        scrubberRow.addSubview(totalLabel)

        let bottom = scrubberRow.bottomAnchor.constraint(
            equalTo: safeAreaLayoutGuide.bottomAnchor,
            constant: -(controlsBottomInset + Layout.bottomGap)
        )
        bottomInsetConstraint = bottom

        NSLayoutConstraint.activate([
            playButton.centerXAnchor.constraint(equalTo: centerXAnchor),
            playButton.centerYAnchor.constraint(equalTo: centerYAnchor),

            scrubberRow.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Layout.sideInset),
            scrubberRow.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Layout.sideInset),
            scrubberRow.heightAnchor.constraint(equalToConstant: 32),
            bottom,

            elapsedLabel.leadingAnchor.constraint(equalTo: scrubberRow.leadingAnchor),
            elapsedLabel.centerYAnchor.constraint(equalTo: scrubberRow.centerYAnchor),

            totalLabel.trailingAnchor.constraint(equalTo: scrubberRow.trailingAnchor),
            totalLabel.centerYAnchor.constraint(equalTo: scrubberRow.centerYAnchor),

            slider.leadingAnchor.constraint(equalTo: elapsedLabel.trailingAnchor, constant: 8),
            slider.trailingAnchor.constraint(equalTo: totalLabel.leadingAnchor, constant: -8),
            slider.centerYAnchor.constraint(equalTo: scrubberRow.centerYAnchor)
        ])

        resetProgressDisplay()
        updatePlayButton()
        applyControlAlpha()
    }

    private func configureTimeLabel(_ label: UILabel) {
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        label.textColor = .white
        label.shadowColor = UIColor.black.withAlphaComponent(0.5)
        label.shadowOffset = CGSize(width: 0, height: 1)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.setContentCompressionResistancePriority(.required, for: .horizontal)
    }

    // MARK: - Configuration

    func configure(url: URL?, duration: TimeInterval?) {
        teardown()
        self.url = url
        self.configuredDuration = duration

        // A video whose local file never downloaded shows a disabled control
        // rather than constructing an AVPlayer against a missing URL.
        playButton.isEnabled = url != nil
        slider.isEnabled = url != nil

        resetProgressDisplay()
        updatePlayButton()
        applyControlAlpha()
    }

    /// Owner-driven visibility: the control fades with the viewer chrome instead
    /// of hiding itself during playback, which previously left no touch target
    /// and made pausing impossible.
    func setControlsVisible(_ visible: Bool, animated: Bool) {
        guard controlsVisible != visible else { return }
        controlsVisible = visible

        guard animated else { return applyControlAlpha() }
        UIView.animate(withDuration: Layout.fadeDuration) { self.applyControlAlpha() }
    }

    // MARK: - Playback

    func play() {
        activatePlaybackAudioSession()
        guard let player = ensurePlayer() else { return }

        if hasReachedEnd {
            hasReachedEnd = false
            player.seek(to: .zero)
        }
        player.play()
    }

    func pause() {
        player?.pause()
    }

    /// Called from `prepareForReuse` and when a page scrolls out of sight, so
    /// swiping away stops playback and releases the decoder rather than leaving
    /// audio running off-screen.
    func teardown() {
        timeControlObservation?.invalidate()
        timeControlObservation = nil

        // Must come off the player before the reference goes: `AVPlayer`
        // traps on dealloc with a periodic observer still attached.
        if let periodicObserver {
            player?.removeTimeObserver(periodicObserver)
        }
        periodicObserver = nil

        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil

        player?.pause()
        player = nil
        playerLayer?.player = nil
        hasReachedEnd = false
        isScrubbing = false

        resetProgressDisplay()
        updatePlayButton()
    }

    // MARK: - Private — player construction

    /// Single place that builds the player, binds it to the layer and installs
    /// the observers. Creating it without binding leaves an audio-only playback
    /// with a blank frame.
    @discardableResult
    private func ensurePlayer() -> AVPlayer? {
        if let player { return player }
        guard let url else { return nil }

        let newPlayer = AVPlayer(url: url)
        player = newPlayer
        playerLayer?.player = newPlayer
        installObservers(on: newPlayer)
        return newPlayer
    }

    private func installObservers(on player: AVPlayer) {
        timeControlObservation = player.observe(
            \.timeControlStatus,
            options: [.new]
        ) { [weak self] _, _ in
            self?.notifyPlaybackStateChanged()
        }

        periodicObserver = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: Layout.progressTickInterval, preferredTimescale: 600),
            queue: .main
        ) { [weak self] time in
            self?.updateProgress(currentTime: time.seconds)
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification,
            object: player.currentItem,
            queue: .main
        ) { [weak self] _ in
            self?.handlePlaybackEnded()
        }
    }

    /// Promotes the session so video is audible with the ringer switch off.
    ///
    /// Skipped while something already holds `.playAndRecord` — a call in
    /// picture-in-picture owns the session, and taking the category from it
    /// drops the call's audio route.
    private func activatePlaybackAudioSession() {
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord else { return }

        do {
            try session.setCategory(.playback, mode: .moviePlayback)
            try session.setActive(true)
        } catch {
            debugLog("MediaViewer: audio session activation failed — \(error)", category: "media-viewer")
        }
    }

    // MARK: - Private — state

    private func handlePlaybackEnded() {
        // The player pauses itself at the end, which KVO already reports; this
        // only rewinds so the next tap starts from the top.
        hasReachedEnd = true
        player?.seek(to: .zero)
        updateProgress(currentTime: 0)
    }

    /// `timeControlStatus` KVO has no documented delivery queue, and everything
    /// it drives is UIKit. Hops only when it has to, so the control still flips
    /// within the same runloop turn in the common case.
    private func notifyPlaybackStateChanged() {
        guard Thread.isMainThread else {
            DispatchQueue.main.async { [weak self] in self?.notifyPlaybackStateChanged() }
            return
        }
        updatePlayButton()
        onPlaybackStateChanged?(isPlaying)
    }

    @objc private func togglePlayback() {
        onInteraction?()
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    private func updatePlayButton() {
        let name = isPlaying ? "pause.circle.fill" : "play.circle.fill"
        let symbol = UIImage(systemName: name)?
            .withConfiguration(UIImage.SymbolConfiguration(pointSize: Layout.controlPointSize))
        playButton.setImage(symbol, for: .normal)
    }

    private func applyControlAlpha() {
        // A view at alpha 0 is skipped by hit testing, so fading the controls out
        // also removes them as touch targets without extra bookkeeping.
        let base: CGFloat = isAvailable ? 1 : Layout.unavailableAlpha
        let alpha = controlsVisible ? base : 0
        playButton.alpha = alpha
        scrubberRow.alpha = alpha
    }

    // MARK: - Private — progress

    /// Prefers the item's own duration and falls back to the value the message
    /// carried, which is all that exists before the asset finishes loading.
    private var totalDuration: TimeInterval {
        if let itemDuration = player?.currentItem?.duration,
           itemDuration.isNumeric,
           itemDuration.seconds > 0 {
            return itemDuration.seconds
        }
        return configuredDuration ?? 0
    }

    private func resetProgressDisplay() {
        slider.value = 0
        elapsedLabel.text = Self.timeText(0)
        totalLabel.text = Self.timeText(configuredDuration ?? 0)
    }

    private func updateProgress(currentTime: TimeInterval) {
        let total = totalDuration
        totalLabel.text = Self.timeText(total)

        guard !isScrubbing else { return }
        elapsedLabel.text = Self.timeText(currentTime)
        slider.value = total > 0 ? Float(min(currentTime / total, 1)) : 0
    }

    @objc private func scrubbingBegan() {
        isScrubbing = true
        onInteraction?()
    }

    @objc private func scrubbingChanged() {
        // Labels track the thumb live; the seek itself waits for touch-up so a
        // drag does not issue one request per pixel.
        elapsedLabel.text = Self.timeText(TimeInterval(slider.value) * totalDuration)
        // Reported per movement so a drag longer than the auto-hide delay does
        // not fade the scrubber out from under the finger holding it.
        onInteraction?()
    }

    @objc private func scrubbingEnded() {
        defer {
            isScrubbing = false
            onInteraction?()
        }

        let total = totalDuration
        guard total > 0, let player = ensurePlayer() else { return }

        hasReachedEnd = false
        player.seek(
            to: CMTime(seconds: TimeInterval(slider.value) * total, preferredTimescale: 600),
            toleranceBefore: .zero,
            toleranceAfter: .zero
        )
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let whole = Int(seconds.rounded(.down))
        let hours = whole / 3600
        let minutes = (whole % 3600) / 60
        let secs = whole % 60

        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
