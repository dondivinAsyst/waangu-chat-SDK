import SwiftUI
import UIKit

/// Full-screen paging media viewer.
///
/// Owns the pager, the chrome and the current index. The transition animators ask
/// it for `currentAnchorID` so dismiss targets the page on screen rather than the
/// one that was originally opened.
final class MediaViewerController: UIViewController {

    private var items: [MediaViewerItem]
    private var currentIndex: Int

    private let registry: MediaHeroAnchorRegistry
    private let translate: (String, [String]) -> String
    private let userName: String

    private lazy var collectionView: UICollectionView = {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumLineSpacing = 0
        layout.minimumInteritemSpacing = 0
        layout.sectionInset = .zero

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.isPagingEnabled = true
        view.showsHorizontalScrollIndicator = false
        view.backgroundColor = .clear
        view.contentInsetAdjustmentBehavior = .never
        view.dataSource = self
        view.delegate = self
        view.register(MediaViewerPageCell.self, forCellWithReuseIdentifier: MediaViewerPageCell.reuseID)
        return view
    }()

    /// Exposed so the animators can fade it independently of the pager content.
    let backdrop = UIView()

    private let chrome = MediaViewerChrome()
    private var chromeVisible = true

    /// Fades the chrome and the video controls out after a quiet spell so the
    /// video is not watched through a header and a footer.
    private var chromeIdleTimer: Timer?
    private static let chromeIdleDelay: TimeInterval = 3

    private lazy var interactiveDismiss = MediaViewerInteractiveDismiss(registry: registry)
    private var dismissPan: UIPanGestureRecognizer?

    /// `onlyMe` mirrors the existing `deleteMessages(onlyMe:message:)` contract.
    var onRequestDelete: ((MediaViewerItem, Bool) -> Void)?

    /// Supplies the transfer control for a page whose file is not here. Passed
    /// straight to the cell — the viewer never builds transfer UI of its own.
    var transferOverlayProvider: ((MediaViewerItem, @escaping () -> Void) -> AnyView?)?

    /// Rebuilds an item once its file has arrived, so the page can resolve the
    /// URLs it could not resolve when the viewer opened.
    var itemRefresher: ((String) -> MediaViewerItem?)?

    var onFinished: (() -> Void)?

    var currentAnchorID: String { items[safe: currentIndex]?.id ?? "" }
    var currentItem: MediaViewerItem? { items[safe: currentIndex] }

    var currentPageCell: MediaViewerPageCell? {
        collectionView.cellForItem(at: IndexPath(item: currentIndex, section: 0)) as? MediaViewerPageCell
    }

    override var prefersStatusBarHidden: Bool { !chromeVisible }
    override var preferredStatusBarUpdateAnimation: UIStatusBarAnimation { .fade }

    /// Guards `onFinished` against firing twice when a path both passes a
    /// dismissal completion and reaches `viewDidDisappear`.
    private var didFinish = false

    /// `registry` has no default: a default argument is evaluated in the
    /// caller's context, and `MediaHeroAnchorRegistry.shared` is main-actor
    /// isolated, so defaulting it warns under Swift 6 isolation checking.
    init(
        request: MediaViewerRequest,
        registry: MediaHeroAnchorRegistry,
        userName: String = "",
        translate: @escaping (String, [String]) -> String = { key, _ in key }
    ) {
        self.items = request.items
        self.currentIndex = min(max(request.startIndex, 0), max(request.items.count - 1, 0))
        self.registry = registry
        self.userName = userName
        self.translate = translate
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .custom
        modalPresentationCapturesStatusBarAppearance = true
        transitioningDelegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MediaViewerController is created in code only")
    }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear

        backdrop.backgroundColor = .black
        backdrop.frame = view.bounds
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(backdrop)

        collectionView.frame = view.bounds
        collectionView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(collectionView)

        chrome.frame = view.bounds
        chrome.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(chrome)

        chrome.onClose = { [weak self] in self?.dismissViewer() }
        chrome.onShare = { [weak self] in self?.shareCurrentItem() }
        chrome.onDelete = { [weak self] in self?.confirmDeleteCurrentItem() }

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleDismissPan))
        pan.delegate = self
        view.addGestureRecognizer(pan)
        dismissPan = pan

        updateChromeForCurrentItem()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout,
           layout.itemSize != view.bounds.size {
            layout.itemSize = view.bounds.size
            layout.invalidateLayout()
        }
        // The scrubber lives inside the video page, which knows nothing about the
        // chrome; feeding it the measured footer height keeps the two from
        // overlapping without hard-coding a clearance that a long caption breaks.
        let footerHeight = chrome.footerHeight
        for cell in collectionView.visibleCells.compactMap({ $0 as? MediaViewerPageCell }) {
            cell.playbackControlsBottomInset = footerHeight
        }

        // Keep the pager pinned to the current page across rotation.
        guard view.bounds.width > 0 else { return }
        let expected = CGPoint(x: CGFloat(currentIndex) * view.bounds.width, y: 0)
        if collectionView.contentOffset != expected {
            collectionView.setContentOffset(expected, animated: false)
        }
    }

    /// Fires `onFinished` for **every** dismissal route, not just the close
    /// button. The interactive drag calls `dismiss(animated:)` with no
    /// completion, so a completion-only notification left the presenter's
    /// binding non-nil and the viewer could never be reopened.
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard isBeingDismissed || presentingViewController == nil else { return }

        // `didEndDisplaying` is not called for the visible page on dismissal, so
        // without this the viewer closes while its video keeps playing audio.
        cancelChromeIdleTimer()
        for cell in collectionView.visibleCells.compactMap({ $0 as? MediaViewerPageCell }) {
            cell.stopPlayback()
        }

        notifyFinished()
    }

    private func notifyFinished() {
        guard !didFinish else { return }
        didFinish = true
        onFinished?()
    }

    // MARK: - Page refresh

    /// Re-resolves a page whose file has just arrived.
    ///
    /// Guarded on the URLs actually changing. Reconfiguring rebuilds the overlay,
    /// and it is the overlay's ready branch that calls this — without the guard
    /// the two would call each other for as long as the page stayed on screen.
    private func refreshItem(_ id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }),
              let refreshed = itemRefresher?(id) else { return }

        let current = items[index]
        guard refreshed.fullResURL != current.fullResURL
                || refreshed.videoURL != current.videoURL else { return }

        items[index] = refreshed

        let path = IndexPath(item: index, section: 0)
        (collectionView.cellForItem(at: path) as? MediaViewerPageCell)?.configure(with: refreshed)
    }

    // MARK: - Actions

    private func dismissViewer() {
        dismiss(animated: true) { [weak self] in self?.notifyFinished() }
    }

    private func shareCurrentItem() {
        guard let item = currentItem else { return }
        let shareURL = item.kind == .video ? item.videoURL : item.fullResURL
        guard let shareURL else { return }

        let activity = UIActivityViewController(activityItems: [shareURL], applicationActivities: nil)
        activity.popoverPresentationController?.sourceView = view
        activity.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0
        )
        present(activity, animated: true)
    }

    /// Mirrors the `t(_:args:)` helper the SwiftUI screens use, so translated
    /// call sites read the same across UIKit and SwiftUI.
    private func t(_ key: String, args: [String] = []) -> String {
        translate(key, args)
    }

    private func confirmDeleteCurrentItem() {
        guard let item = currentItem else { return }

        let sheet = UIAlertController(
            title: t(ChatTranslationKeys.GALLERY_CHOOSE_ACTION),
            message: nil,
            preferredStyle: .actionSheet
        )
        sheet.addAction(UIAlertAction(
            title: t(ChatTranslationKeys.GALLERY_DELETE_FOR_ME),
            style: .destructive
        ) { [weak self] _ in
            self?.onRequestDelete?(item, true)
        })

        // Received messages can only be deleted for me — same rule the previous
        // carousel applied.
        if item.isSentByMe {
            sheet.addAction(UIAlertAction(
                title: t(ChatTranslationKeys.GALLERY_DELETE_FOR_ME_AND_USER, args: [userName]),
                style: .destructive
            ) { [weak self] _ in
                self?.onRequestDelete?(item, false)
            })
        }

        sheet.addAction(UIAlertAction(title: t("cancel"), style: .cancel))
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: view.bounds.midX, y: view.bounds.maxY, width: 0, height: 0
        )
        present(sheet, animated: true)
    }

    /// Called after a delete succeeds. Dismisses when the last item goes,
    /// otherwise advances to the neighbouring page.
    func removeItem(id: String) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items.remove(at: index)

        guard !items.isEmpty else { return dismissViewer() }

        currentIndex = min(index, items.count - 1)
        collectionView.reloadData()
        if view.bounds.width > 0 {
            collectionView.setContentOffset(
                CGPoint(x: CGFloat(currentIndex) * view.bounds.width, y: 0),
                animated: false
            )
        }
        updateChromeForCurrentItem()
    }

    private func toggleChrome() {
        setChromeVisible(!chromeVisible)
    }

    /// Single place that moves the chrome, because the video controls fade with
    /// it: hiding one without the other either strands a pause button over the
    /// footer or leaves a playing video with no touch target at all.
    private func setChromeVisible(_ visible: Bool) {
        chromeVisible = visible
        chrome.setVisible(visible, animated: true)
        currentPageCell?.setPlaybackControlsVisible(visible, animated: true)
        setNeedsStatusBarAppearanceUpdate()

        if visible {
            armChromeIdleTimer()
        } else {
            cancelChromeIdleTimer()
        }
    }

    /// Restarts the countdown that fades the chrome away. Only a playing video
    /// arms it — a still image and a paused video keep their controls until the
    /// user taps them away.
    private func armChromeIdleTimer() {
        cancelChromeIdleTimer()
        guard chromeVisible, currentPageCell?.isPlayingVideo == true else { return }

        chromeIdleTimer = Timer.scheduledTimer(
            withTimeInterval: Self.chromeIdleDelay,
            repeats: false
        ) { [weak self] _ in
            // Timer callbacks land on the main runloop that scheduled them.
            self?.setChromeVisible(false)
        }
    }

    private func cancelChromeIdleTimer() {
        chromeIdleTimer?.invalidate()
        chromeIdleTimer = nil
    }

    private func handlePlaybackStateChanged(_ isPlaying: Bool) {
        guard isPlaying else {
            // Pausing or reaching the end must bring the controls back, or the
            // user is left with a stopped video and nothing to tap.
            cancelChromeIdleTimer()
            setChromeVisible(true)
            return
        }
        armChromeIdleTimer()
    }

    private func updateChromeForCurrentItem() {
        guard let item = currentItem else { return }
        chrome.configure(item: item, index: currentIndex, total: items.count)
    }

    // MARK: - Drag to dismiss

    @objc private func handleDismissPan(_ gesture: UIPanGestureRecognizer) {
        let translation = gesture.translation(in: view)
        let size = CGSize(width: translation.x, height: translation.y)

        switch gesture.state {
        case .began:
            interactiveDismiss.begin(in: self)
        case .changed:
            interactiveDismiss.update(translation: size, in: view.bounds)
        case .ended, .cancelled, .failed:
            let velocity = gesture.velocity(in: view)
            interactiveDismiss.end(
                translation: size,
                velocity: CGSize(width: velocity.x, height: velocity.y)
            )
        default:
            break
        }
    }
}

// MARK: - Data source

extension MediaViewerController: UICollectionViewDataSource {

    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        items.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: MediaViewerPageCell.reuseID,
            for: indexPath
        )
        guard let pageCell = cell as? MediaViewerPageCell, let item = items[safe: indexPath.item] else {
            return cell
        }
        // Both are read during `configure`, so they have to be in place first.
        pageCell.transferOverlayProvider = transferOverlayProvider
        pageCell.onRequestRefresh = { [weak self] id in self?.refreshItem(id) }
        pageCell.configure(with: item)
        pageCell.playbackControlsBottomInset = chrome.footerHeight
        pageCell.setPlaybackControlsVisible(chromeVisible, animated: false)
        pageCell.onSingleTap = { [weak self] in self?.toggleChrome() }
        pageCell.onPlaybackInteraction = { [weak self] in self?.armChromeIdleTimer() }
        pageCell.onPlaybackStateChanged = { [weak self] isPlaying in
            self?.handlePlaybackStateChanged(isPlaying)
        }
        return pageCell
    }
}

// MARK: - Paging

extension MediaViewerController: UICollectionViewDelegateFlowLayout {

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        updateCurrentIndex()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        updateCurrentIndex()
    }

    /// Releases a page's decoder as soon as it leaves the screen. Without this
    /// the only teardown is `prepareForReuse`, which fires on the next dequeue
    /// and left a swiped-away video playing audio off-screen.
    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        // Layout passes re-display the current page; only a genuine page change
        // should stop playback.
        guard indexPath.item != currentIndex else { return }
        (cell as? MediaViewerPageCell)?.stopPlayback()
    }

    private func updateCurrentIndex() {
        guard view.bounds.width > 0 else { return }
        let index = Int(round(collectionView.contentOffset.x / view.bounds.width))
        guard index != currentIndex, items.indices.contains(index) else { return }
        currentIndex = index
        updateChromeForCurrentItem()
        // A new page is never mid-playback, so the chrome comes back and stays.
        setChromeVisible(true)
    }
}

// MARK: - Transitioning

extension MediaViewerController: UIViewControllerTransitioningDelegate {

    func animationController(
        forPresented presented: UIViewController,
        presenting: UIViewController,
        source: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaViewerPresentAnimator(registry: registry, anchorID: currentAnchorID)
    }

    func animationController(
        forDismissed dismissed: UIViewController
    ) -> UIViewControllerAnimatedTransitioning? {
        MediaViewerDismissAnimator(registry: registry)
    }

    func interactionControllerForDismissal(
        using animator: UIViewControllerAnimatedTransitioning
    ) -> UIViewControllerInteractiveTransitioning? {
        interactiveDismiss.isActive ? interactiveDismiss : nil
    }
}

// MARK: - Gesture gating

extension MediaViewerController: UIGestureRecognizerDelegate {

    /// Dismiss only from an unzoomed page, and only when the drag is more
    /// vertical than horizontal — horizontal belongs to the pager.
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer, pan === dismissPan else {
            return true
        }
        guard (currentPageCell?.zoomScale ?? 1) <= 1 else { return false }

        let velocity = pan.velocity(in: view)
        return abs(velocity.y) > abs(velocity.x)
    }

    /// A drag that starts on a control belongs to that control. Without this the
    /// dismiss pan steals a slightly-vertical scrubber drag and closes the viewer
    /// mid-seek.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldReceive touch: UITouch
    ) -> Bool {
        !(touch.view is UIControl)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
