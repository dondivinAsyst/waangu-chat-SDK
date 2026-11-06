import ImageIO
import SwiftUI
import UIKit

/// One full-screen page: a zoomable image, or a video handed to
/// `MediaViewerVideoPlayback`.
final class MediaViewerPageCell: UICollectionViewCell {

    static let reuseID = "MediaViewerPageCell"

    private let scrollView = UIScrollView()
    private(set) var imageView = UIImageView()
    private let videoPlayback = MediaViewerVideoPlayback()

    private var item: MediaViewerItem?
    private var fullResTask: Task<Void, Never>?

    var onSingleTap: (() -> Void)?

    /// Supplies the transfer control for a page whose file is not here yet.
    ///
    /// A closure rather than a control of the cell's own: the room already owns
    /// this UI, and the viewer has no business growing a second implementation of
    /// progress, retry and cancel. The callback it is handed fires when the file
    /// lands, which is the cell's cue to re-resolve and load it.
    var transferOverlayProvider: ((MediaViewerItem, @escaping () -> Void) -> AnyView?)?

    /// This page's file arrived; its URLs need resolving again.
    var onRequestRefresh: ((String) -> Void)?

    private var overlayHost: UIHostingController<AnyView>?

    /// Forwarded from the player so the viewer can arm or cancel its auto-hide
    /// countdown when playback actually starts or stops.
    var onPlaybackStateChanged: ((Bool) -> Void)?

    /// Forwarded from the player controls so the viewer can restart its
    /// auto-hide countdown on any touch that never reaches the page.
    var onPlaybackInteraction: (() -> Void)?

    var zoomScale: CGFloat { scrollView.zoomScale }

    var isPlayingVideo: Bool { isVideoPage && videoPlayback.isPlaying }

    /// Clearance the scrubber keeps above the bottom safe area, so it never sits
    /// under the viewer's footer controls.
    var playbackControlsBottomInset: CGFloat {
        get { videoPlayback.controlsBottomInset }
        set { videoPlayback.controlsBottomInset = newValue }
    }

    /// The dismiss gesture reads this: video pages never zoom, so a vertical drag
    /// there always means dismiss.
    private(set) var isVideoPage = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        setUpViews()
        setUpGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaViewerPageCell is created in code only")
    }

    // MARK: - Setup

    private func setUpViews() {
        scrollView.delegate = self
        scrollView.minimumZoomScale = 1
        scrollView.maximumZoomScale = 4
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.bouncesZoom = true
        scrollView.backgroundColor = .clear
        scrollView.frame = contentView.bounds
        scrollView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(scrollView)

        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.clipsToBounds = true
        scrollView.addSubview(imageView)

        videoPlayback.isHidden = true
        videoPlayback.frame = contentView.bounds
        videoPlayback.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        videoPlayback.onPlaybackStateChanged = { [weak self] isPlaying in
            self?.onPlaybackStateChanged?(isPlaying)
        }
        videoPlayback.onInteraction = { [weak self] in
            self?.onPlaybackInteraction?()
        }
        contentView.addSubview(videoPlayback)
    }

    private func setUpGestures() {
        let single = UITapGestureRecognizer(target: self, action: #selector(handleSingleTap))
        let double = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        double.numberOfTapsRequired = 2
        single.require(toFail: double)
        scrollView.addGestureRecognizer(single)
        scrollView.addGestureRecognizer(double)
    }

    // MARK: - Configuration

    func configure(with item: MediaViewerItem) {
        self.item = item
        isVideoPage = item.kind == .video

        // The thumbnail is already in memory, so a page is never blank while
        // full resolution decodes. This is what removes the mid-transition flash.
        imageView.image = item.thumbnail
        resetZoom(animated: false)
        layoutImageView()

        scrollView.maximumZoomScale = isVideoPage ? 1 : 4

        installTransferOverlay(for: item)

        // Both of these already degrade correctly on a missing file: the player
        // disables its button on a nil URL, and the decode is guarded on one. The
        // overlay covers the gap in the meantime.
        videoPlayback.isHidden = !isVideoPage
        if isVideoPage {
            videoPlayback.configure(url: item.videoURL, duration: item.videoDuration)
        } else {
            loadFullResolution(for: item)
        }
    }

    /// Hosts the room's own transfer control over this page.
    private func installTransferOverlay(for item: MediaViewerItem) {
        overlayHost?.view.removeFromSuperview()
        overlayHost = nil

        guard let overlay = transferOverlayProvider?(item, { [weak self] in
            // The page may have been recycled to a different item by the time the
            // transfer lands.
            guard let self, self.item?.id == item.id else { return }
            self.onRequestRefresh?(item.id)
        }) else { return }

        let host = UIHostingController(rootView: overlay)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            host.view.centerYAnchor.constraint(equalTo: contentView.centerYAnchor)
        ])

        overlayHost = host
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        fullResTask?.cancel()
        fullResTask = nil
        videoPlayback.teardown()
        videoPlayback.isHidden = true
        isVideoPage = false
        imageView.image = nil
        imageView.isHidden = false
        item = nil
        overlayHost?.view.removeFromSuperview()
        overlayHost = nil
        onPlaybackStateChanged = nil
        onPlaybackInteraction = nil
        resetZoom(animated: false)
    }

    /// Releases the decoder without waiting for the cell to be dequeued again.
    /// `prepareForReuse` fires on the *next* dequeue, not when a page scrolls
    /// off, so relying on it alone left audio playing off-screen.
    func stopPlayback() {
        guard isVideoPage else { return }
        videoPlayback.teardown()
    }

    func setPlaybackControlsVisible(_ visible: Bool, animated: Bool) {
        guard isVideoPage else { return }
        videoPlayback.setControlsVisible(visible, animated: animated)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if scrollView.zoomScale == 1 {
            layoutImageView()
        }
    }

    /// Sizes the image to the same rect the hero animator targets, so the handoff
    /// between snapshot and page is identical by construction.
    ///
    /// The frame origin must be `.zero`: `targetRect` is centered within the
    /// container, but inside a scroll view centering is the `contentInset`'s job.
    /// Applying both offsets the image by the centering distance twice and pins
    /// it to the bottom of the screen.
    private func layoutImageView() {
        guard let image = imageView.image else {
            imageView.frame = contentView.bounds
            scrollView.contentSize = contentView.bounds.size
            scrollView.contentInset = .zero
            return
        }

        let fitted = HeroGeometry.targetRect(for: image.size, in: contentView.bounds).size
        imageView.frame = CGRect(origin: .zero, size: fitted)
        scrollView.contentSize = fitted
        scrollView.contentInset = ZoomMath.centeringInset(
            contentSize: fitted,
            boundsSize: contentView.bounds.size
        )
    }

    func resetZoom(animated: Bool) {
        scrollView.setZoomScale(1, animated: animated)
    }

    // MARK: - Full-resolution decode

    /// Decodes off the main thread and cross-fades in only if the result is
    /// genuinely larger than what is already displayed. A full-size `CGImage` is
    /// never handed straight to a layer.
    private func loadFullResolution(for item: MediaViewerItem) {
        guard item.kind == .image, let url = item.fullResURL else { return }

        if let cached = ChatImageMemoryCache.shared.image(forKey: item.id),
           cached.size.width > (imageView.image?.size.width ?? 0) {
            apply(cached, for: item)
            return
        }

        let targetPixels = max(contentView.bounds.width, contentView.bounds.height) * UIScreen.main.scale

        fullResTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let decoded = Self.decodeDownsampled(url: url, maxPixelSize: targetPixels) else { return }
            guard !Task.isCancelled else { return }
            await MainActor.run { [weak self] in
                ChatImageMemoryCache.shared.store(decoded, forKey: item.id)
                self?.apply(decoded, for: item)
            }
        }
    }

    private func apply(_ image: UIImage, for item: MediaViewerItem) {
        // The page may have been recycled to a different item mid-decode.
        guard self.item?.id == item.id else { return }
        guard image.size.width > (imageView.image?.size.width ?? 0) else { return }

        UIView.transition(with: imageView, duration: 0.15, options: .transitionCrossDissolve) {
            self.imageView.image = image
        }
        layoutImageView()
    }

    /// `nonisolated` so the detached decode task can call it: the cell inherits
    /// `@MainActor` from `UICollectionViewCell`, and decoding must not run there.
    private nonisolated static func decodeDownsampled(url: URL, maxPixelSize: CGFloat) -> UIImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }

        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    // MARK: - Gestures

    @objc private func handleSingleTap() {
        onSingleTap?()
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard !isVideoPage else { return }

        if scrollView.zoomScale > scrollView.minimumZoomScale {
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
        } else {
            let point = gesture.location(in: imageView)
            scrollView.zoom(
                to: ZoomMath.zoomRect(scale: 2.5, center: point, in: contentView.bounds.size),
                animated: true
            )
        }
    }
}

// MARK: - UIScrollViewDelegate

extension MediaViewerPageCell: UIScrollViewDelegate {

    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        imageView
    }

    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        scrollView.contentInset = ZoomMath.centeringInset(
            contentSize: imageView.frame.size,
            boundsSize: contentView.bounds.size
        )
    }
}
