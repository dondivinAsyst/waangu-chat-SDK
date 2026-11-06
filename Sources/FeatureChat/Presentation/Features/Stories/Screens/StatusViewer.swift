import SwiftUI
import AVKit
import Combine
import WaanguSharedUI
import WaanguCoreKit

// MARK: - Contact pager (drives 3D tilt for swipe + auto-advance)

@MainActor
final class StoryPagerController: ObservableObject {
    weak var scrollView: UIScrollView?
    var onPagingChanged: ((Bool) -> Void)?

    /// Returns `false` when the scroll view isn't ready (caller should fall back).
    @discardableResult
    func scrollToPage(at index: Int, animated: Bool, completion: (() -> Void)? = nil) -> Bool {
        guard let scrollView, scrollView.bounds.width > 1 else {
            return false
        }

        let pageWidth = scrollView.bounds.width
        let targetX = pageWidth * CGFloat(max(0, index))
        // Prefer the ideal page offset — TabView contentSize can lag and over-clamp.
        let maxX = max(0, scrollView.contentSize.width - pageWidth)
        let clampedX: CGFloat
        if maxX > pageWidth * 0.5 {
            clampedX = min(max(0, targetX), maxX)
        } else {
            clampedX = targetX
        }
        let clamped = CGPoint(x: clampedX, y: scrollView.contentOffset.y)

        guard abs(scrollView.contentOffset.x - clamped.x) > 0.5 else {
            return false
        }

        guard animated else {
            scrollView.setContentOffset(clamped, animated: false)
            completion?()
            return true
        }

        onPagingChanged?(true)
        // Native scroll animation updates page frames every tick → 3D tilt works.
        scrollView.setContentOffset(clamped, animated: true)

        // TabView doesn't expose scroll completion; settle after a short beat.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.onPagingChanged?(false)
            completion?()
        }
        return true
    }
}

private struct StoryPagerControllerKey: EnvironmentKey {
    static let defaultValue: StoryPagerController? = nil
}

extension EnvironmentValues {
    var storyPager: StoryPagerController? {
        get { self[StoryPagerControllerKey.self] }
        set { self[StoryPagerControllerKey.self] = newValue }
    }
}

@available(iOS 16.0, *)
struct StatusViewer: View {
    @ObservedObject var statusStore: StoriesViewModel
    @State var story: Status
    @StateObject private var loader = ImageDownloader()
    @StateObject private var controller : VideoPlayerController
    let navigationCoord:UpdatesTabCoordinator
    @Environment(\.storyPager) private var storyPager
    
    @State private var progress: CGFloat = 0.0
//    @Environment(\.dismiss) var dismiss
    
    @State private var inputText: String = ""
    @State private var showSheet = false
    @FocusState private var isFocused: Bool
    @State private var dynamicHeight: CGFloat = 50
    @State private var text: String = ""
    @State private var height: CGFloat = 30
    @State private var isPaused: Bool = false
    /// True while finger is holding to pause — must not resume on swipe cancel.
    @State private var isHoldingPause: Bool = false
    @State private var keyboardHeight: CGFloat = 0
    @State private var IsSwipped: Bool = false
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var ShowViewerSheet: Bool = false
    @State private var readMore: Bool = false
    @State private var currentOwnImage: UIImage? = nil
    @State private var keyboardCancellables = Set<AnyCancellable>()
    @State private var showReactionPicker = false
    @State private var floatingReactionEmoji: String? = nil
    @State private var floatingReactionScale: CGFloat = 0.2
    @State private var floatingReactionOpacity: Double = 0
    @State private var replySendFeedback: ReplySendFeedback?
    /// Bumped to remount `CustomVideoPlayer` after a failed download retry.
    @State private var videoReloadNonce: Int = 0
    @StateObject private var timeline = StatusStoryTimelineDriver()
    private let quickReactions = ["❤️", "😂", "😮", "😢", "🙏", "👍"]
    /// Shown inline in the reply bar — tap sends a DM reply, not a story reaction.
    private let quickReplyEmojis = ["😀", "😂", "😍", "🥰", "😮"]
    private let fontData = ConstantFont.shared.AllFonts
    let translationService: (any TranslationServiceProtocol)?
    var isCurrentUser: Bool
    let isSingleSegmentPresentation: Bool

    private var isViewerActive: Bool {
        isSingleSegmentPresentation || isCurrentUser || statusStore.currentStory == story.id
    }
    
    init(
        storyId: String,
        viewModel: StoriesViewModel,
        updateTabCoordinator: UpdatesTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.statusStore = viewModel
        _controller = StateObject(wrappedValue: VideoPlayerController(storieVM: viewModel))
        self.translationService = translationService
        self.isSingleSegmentPresentation = false
        
        self.isCurrentUser = viewModel.isOwnStatus(userId: storyId)

        if isCurrentUser {
            self._story = State(initialValue: viewModel.ownStatus ?? Status(userId: UUID().uuidString))
        } else {
            var contact = viewModel.contactStatus.first { $0.id == storyId } ?? Status(userId: UUID().uuidString)
            contact.applyResumeIndex()
            self._story = State(initialValue: contact)
        }
        self.navigationCoord = updateTabCoordinator
    }

    /// Chat reply-preview entry: one segment, same viewer chrome, auto-dismiss when progress ends.
    init(
        pinnedStory: Status,
        viewModel: StoriesViewModel,
        updateTabCoordinator: UpdatesTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.statusStore = viewModel
        _story = State(initialValue: pinnedStory)
        _controller = StateObject(wrappedValue: VideoPlayerController(storieVM: viewModel))
        self.translationService = translationService
        self.isSingleSegmentPresentation = true
        self.isCurrentUser = viewModel.isOwnStatus(userId: pinnedStory.userId)
        self.navigationCoord = updateTabCoordinator
    }

    
 
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            mainStatusContent

            // Soft scrims so chrome stays readable over any media
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.black.opacity(0.72), Color.black.opacity(0.28), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 170)
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [.clear, Color.black.opacity(0.35), Color.black.opacity(0.78)],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 240)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            gestureOverlay
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())

            VStack(spacing: 0) {
                topChrome
                Spacer(minLength: 0)
                    .allowsHitTesting(false)
                bottomChrome
            }
            .padding(.top, safeAreaTop)
            .padding(.bottom, max(safeAreaBottom, 10))
            .zIndex(1)

            failedStatusOverlay
            // Above gestures; button-sized only so left/right next/previous still work when media failed.
            downloadRetryOverlay
                .zIndex(2)
            floatingReactionOverlay
            viewersSheet
            statusReplyFeedbackBanner
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .statusBar(hidden: true)
        .onAppear {
            loader.onDiskCached = { codeStatus in
                statusStore.notifyStatusMediaCached(codeStatus: codeStatus)
            }
            syncStoryFromStore()
            loadCurrentImageIfNeeded()
            // Only the active contact page should run its timeline.
            if isViewerActive {
                configureAndStartTimeline()
                if currentStatusItem?.syncStatus == .failed {
                    pauseTimer()
                }
            }
            statusStore.isFirstPageStory = false
        }
        .onDisappear {
            timeline.stop()
        }
        .onChange(of: statusStore.currentStory) { newValue in
            guard !isCurrentUser else { return }
            if newValue == story.id {
                // Landing on this contact: sync segments and open at first unviewed.
                applyContactResumeFromStore()
                loadCurrentImageIfNeeded()
                configureAndStartTimeline()
                if currentStatusItem?.syncStatus == .failed {
                    pauseTimer()
                }
            } else {
                timeline.stop()
                isPaused = true
                controller.pause()
            }
        }
        .onChange(of: story.currentIndex) { _ in
            loadCurrentImageIfNeeded()
            if currentStatusItem?.syncStatus == .failed {
                pauseTimer()
            }
        }
        .onChange(of: statusStore.ownStatus) { _ in
            syncStoryFromStore()
            loadCurrentImageIfNeeded()
        }
        .onChange(of: statusStore.isSlidingToBottom) { sliding in
            sliding ? pauseTimer() : resumeTimerIfNeeded()
        }
        .onChange(of: statusStore.isPagingContacts) { paging in
            if paging {
                pauseTimer(hideBar: false)
            } else {
                resumeTimerIfNeeded()
            }
        }
    }

    private var safeAreaTop: CGFloat {
        keyWindowSafeArea.top
    }

    private var safeAreaBottom: CGFloat {
        keyWindowSafeArea.bottom
    }

    private var keyWindowSafeArea: UIEdgeInsets {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)?
            .safeAreaInsets ?? .zero
    }

    private var topChrome: some View {
        VStack(alignment: .leading, spacing: 10) {
            StatusStoryTimelineView(
                segmentCount: max(story.status.count, 1),
                durations: story.status.map { max(0.5, $0.duration) },
                startIndex: story.currentIndex,
                driver: timeline,
                onIndexChanged: { index in
                    guard story.status.indices.contains(index) else { return }
                    let item = story.status[index]
                    let previousType = story.status[story.currentIndex].type

                    // Clear stale download errors so the next segment isn't stuck behind failure UI.
                    if loader.hasError {
                        loader.reset()
                    }
                    if item.type == .video || previousType == .video {
                        controller.resetPlayer()
                    } else if controller.hasError {
                        controller.hasError = false
                    }

                    story.currentIndex = index
                    loadCurrentImageIfNeeded()
                    progress = 0

                    if item.type == .video {
                        // Wait for OnStartPlaying.
                        isPaused = true
                        timeline.pause(hideBar: false)
                        controller.pause()
                    } else if item.type == .image, Self.needsRemoteImageLoad(item) {
                        // Wait until DownloadableImageView finishes — do not burn duration on spinner.
                        isPaused = true
                        timeline.pause(hideBar: false)
                    } else if item.syncStatus == .failed {
                        pauseTimer()
                    } else {
                        isPaused = false
                    }
                },
                onReachEnd: {
                    updateToNextStory()
                },
                onReachPrevious: {
                    goToPreviousUserOrRestart()
                }
            )
            .frame(height: 3)
            .padding(.horizontal, 12)
            .padding(.top, 8)

            headerView
                .padding(.horizontal, 12)
        }
    }

    private var dismissBackButton: some View {
        Button {
            dismissViewer()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Color.white.opacity(0.14))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var headerView: some View {
        HStack(spacing: 12) {
            dismissBackButton

            ImageViewComponent(url: URL(string: story.userImage ?? ""), width: 40, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(isCurrentUser ? t(ChatTranslationKeys.STORIES_MY_STATUS) : story.userName ?? "Waangu User")
                    .foregroundStyle(.white)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)

                let index = story.currentIndex
                if index < story.status.count {
                    let item = story.status[index]
                    let syncText: String = {
                        switch item.syncStatus {
                        case .synced:
                            return ""
                        case .pending, .retrying, .syncing:
                            return t(ChatTranslationKeys.STORIES_SYNCING)
                        case .failed:
                            return t(ChatTranslationKeys.STORIES_FAILED)
                        }
                    }()
                    Text(syncText.isEmpty ? formatDate(item.createdAt) : "\(syncText) · \(formatDate(item.createdAt))")
                        .foregroundStyle(.white.opacity(0.78))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)

            if isCurrentUser, let item = currentStatusItem, item.syncStatus == .failed {
                Button {
                    Task { await retryCurrentStatus(item) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .disabled(statusStore.syncInProgress)
                .accessibilityLabel(t(ChatTranslationKeys.STORIES_TAP_RETRY))
            }
        }
    }

    private var mainStatusContent: some View {
        Group {
            let index = story.currentIndex
            if index < story.status.count {
                currentStatusView(ownImage: currentOwnImage, loader: loader, currentIndex: index)
                    .scaleEffect(scale)
                    .animation(.easeInOut, value: scale)
            } else {
                Color.black
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var bottomChrome: some View {
        VStack(spacing: 10) {
            if !isSingleSegmentPresentation, showReactionPicker && !isCurrentUser {
                StatusQuickReactionPicker(emojis: quickReactions) { emoji in
                    sendStatusReaction(emoji, animated: true)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) {
                        showReactionPicker = false
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.2, anchor: .bottomTrailing).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .bottomTrailing).combined(with: .opacity)
                    )
                )
            }
            captionBlock
            if showsBottomControlsInPresentation {
                bottomControlsContent
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 4)
        .animation(.spring(response: 0.35, dampingFraction: 0.72), value: showReactionPicker)
    }

    private var showsBottomControlsInPresentation: Bool {
        if !isSingleSegmentPresentation { return true }
        return isCurrentUser
    }

    @ViewBuilder
    private var captionBlock: some View {
        let index = story.currentIndex
        if index < story.status.count {
            let caption = story.status[index].caption ?? ""
            if !caption.isEmpty {
                Text(caption)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(readMore ? 8 : 2)
                    .truncationMode(.tail)
                    .shadow(color: .black.opacity(0.45), radius: 4, y: 1)
                    .frame(maxWidth: .infinity)
                    .onTapGesture {
                        withAnimation(.easeInOut) {
                            readMore.toggle()
                            if readMore {
                                pauseTimer()
                            } else {
                                resumeTimer()
                            }
                        }
                    }
            }
        }
    }

    private var bottomControlsContent: some View {
        Group {
            if showSheet && !isCurrentUser {
                replyField
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .padding(.bottom, keyboardHeight)
            } else {
                actionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: showSheet)
        .animation(.easeOut(duration: 0.25), value: keyboardHeight)
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onChange(of: showSheet) { newValue in
            guard !isCurrentUser else { return }
            newValue ? addKeyboardObservers() : removeKeyboardObservers()
        }
    }
    
    private var gestureOverlay: some View {
        StatusStoryGestureOverlay(
            onTapLeft: {
                if showReactionPicker {
                    withAnimation { showReactionPicker = false }
                    return
                }
                if showSheet && !isCurrentUser {
                    withAnimation(.easeInOut) {
                        showSheet = false
                        controller.resume()
                        resumeTimer()
                    }
                    return
                }
                if !statusStore.isSlidingToBottom {
                    previousStatus()
                }
            },
            onTapRight: {
                if showReactionPicker {
                    withAnimation { showReactionPicker = false }
                    return
                }
                if showSheet && !isCurrentUser {
                    withAnimation(.easeInOut) {
                        showSheet = false
                        controller.resume()
                        resumeTimer()
                    }
                    return
                }
                if !statusStore.isSlidingToBottom {
                    nextStatus()
                }
            },
            onDoubleTap: {
                guard !isSingleSegmentPresentation, !isCurrentUser else { return }
                sendStatusReaction("❤️", animated: true)
            },
            onPressBegan: {
                isHoldingPause = true
                pauseTimer()
            },
            onPressEnded: {
                isHoldingPause = false
                if !showSheet && !ShowViewerSheet
                    && !showReactionPicker
                    && !statusStore.isSlidingToBottom
                    && !statusStore.isPagingContacts {
                    resumeTimer()
                }
            },
            onDragUp: {
                if isSingleSegmentPresentation {
                    guard isCurrentUser, !ShowViewerSheet else { return }
                    withAnimation(.easeInOut) {
                        ShowViewerSheet = true
                        pauseTimer()
                        pauseVideoIfNeeded()
                    }
                    return
                }
                if isCurrentUser {
                    guard !ShowViewerSheet else { return }
                    withAnimation(.easeInOut) {
                        ShowViewerSheet = true
                        pauseTimer()
                        pauseVideoIfNeeded()
                    }
                } else {
                    guard !showSheet else { return }
                    withAnimation(.easeInOut) {
                        showSheet = true
                        pauseTimer()
                        pauseVideoIfNeeded()
                    }
                }
            },
            onHorizontalSwipeBegan: {
                // TabView stole the touch — keep paused, do not resume.
                isHoldingPause = false
                pauseTimer(hideBar: false)
            }
        )
        .simultaneousGesture(
            MagnificationGesture()
                .onChanged { value in
                    let delta = value / lastScale
                    lastScale = value
                    scale *= delta
                }
                .onEnded { _ in
                    lastScale = 1.0
                    withAnimation {
                        scale = min(max(scale, 1.0), 3.0)
                    }
                }
        )
    }

    /// Centered retry only — does not cover the full screen, so next/previous taps still reach gestures.
    @ViewBuilder
    private var downloadRetryOverlay: some View {
        // Own sync failures use the header retry — this overlay is for contact media download only.
        if !isCurrentUser, let item = currentStatusItem {
            if loader.hasError, item.type == .image {
                Button {
                    pauseTimer()
                    loader.retry(item.content ?? "", codeStatus: item.codeStatus)
                } label: {
                    retryDownloadLabel
                }
                .buttonStyle(.plain)
            } else if controller.hasError, item.type == .video {
                Button {
                    pauseTimer()
                    controller.resetPlayer()
                    controller.hasError = false
                    controller.isLoading = true
                    videoReloadNonce &+= 1
                } label: {
                    retryDownloadLabel
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var retryDownloadLabel: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.white)
            Text(t(ChatTranslationKeys.STORIES_DOWNLOAD))
                .foregroundColor(.white.opacity(0.85))
                .font(.caption.weight(.semibold))
        }
        .padding(28)
        .contentShape(Rectangle())
    }

    private var floatingReactionOverlay: some View {
        Group {
            if let emoji = floatingReactionEmoji {
                Text(emoji)
                    .font(.system(size: 96))
                    .scaleEffect(floatingReactionScale)
                    .opacity(floatingReactionOpacity)
                    .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
                    .allowsHitTesting(false)
                    .zIndex(20)
            }
        }
    }
    
    private var replyField: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ResizableTextEditor(
                text: $text,
                height: $height,
                textColor: .white,
                placeholder: t(ChatTranslationKeys.STORIES_TYPE_HERE),
                autoFocus: true
            )
            .frame(height: min(max(height, 40), 150))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
            )

            Button {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                Task { await sendReplyMessage(trimmed) }
            } label: {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(AppColors.primary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private var actionBar: some View {
        Group {
            if isCurrentUser {
                HStack(spacing: 12) {
                    if let item = currentStatusItem, item.syncStatus == .failed {
                        Button {
                            Task { await retryCurrentStatus(item) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text(t(ChatTranslationKeys.STORIES_TAP_RETRY))
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 16)
                            .frame(height: 44)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .disabled(statusStore.syncInProgress)
                    }

                    Spacer(minLength: 0)

                    Button {
                        withAnimation(.easeInOut) {
                            ShowViewerSheet = true
                            pauseTimer()
                            pauseVideoIfNeeded()
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "eye.fill")
                            Text("\(safeViewCount)")
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(Color.white.opacity(0.16))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            } else {
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Button {
                            withAnimation(.easeInOut) {
                                showSheet = true
                                showReactionPicker = false
                                pauseTimer()
                                pauseVideoIfNeeded()
                            }
                        } label: {
                            Text(t(ChatTranslationKeys.STORIES_REPLY_HERE))
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.white.opacity(0.92))
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)

                        ForEach(quickReplyEmojis, id: \.self) { emoji in
                            Button {
                                Task { await sendReplyMessage(emoji) }
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 22))
                                    .frame(width: 32, height: 32)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.leading, 16)
                    .padding(.trailing, 8)
                    .frame(height: 48)
                    .background(Color.white.opacity(0.16))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )

                    Button {
                        let opening = !showReactionPicker
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                            showReactionPicker = opening
                        }
                        if opening {
                            pauseTimer()
                            pauseVideoIfNeeded()
                        } else if !showSheet && !ShowViewerSheet {
                            resumeTimer()
                        }
                    } label: {
                        Image(systemName: "face.smiling")
                            .font(.system(size: 22, weight: .regular))
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Color.white.opacity(showReactionPicker ? 0.28 : 0.16))
                            .clipShape(Circle())
                            .overlay(
                                Circle()
                                    .stroke(Color.white.opacity(0.18), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("React")
                }
            }
        }
    }

    private func sendStatusReaction(_ emoji: String, animated: Bool) {
        guard !isCurrentUser, let item = currentStatusItem else { return }
        statusStore.reactToStatus(storyId: item.codeStatus, reaction: emoji)
        guard animated else { return }
        playFloatingReaction(emoji)
    }

    private func sendReplyMessage(_ replyText: String) async {
        guard let item = currentStatusItem else { return }
        let trimmed = replyText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let previousText = text
        let shouldRestoreTypedText = trimmed != previousText

        text = ""
        showSheet = false

        let sent = await statusStore.sendStatusReply(
            text: trimmed,
            statusOwner: story,
            statusItem: item
        )
        if sent {
            isFocused = false
            presentReplySendFeedback(.sent)
            resumeTimer()
        } else {
            if shouldRestoreTypedText {
                text = previousText.isEmpty ? trimmed : previousText
            } else {
                text = trimmed
            }
            showSheet = true
            presentReplySendFeedback(.failed)
        }
    }

    private func playFloatingReaction(_ emoji: String) {
        floatingReactionEmoji = emoji
        floatingReactionScale = 0.25
        floatingReactionOpacity = 0
        withAnimation(.spring(response: 0.32, dampingFraction: 0.55)) {
            floatingReactionScale = 1.15
            floatingReactionOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) {
            withAnimation(.easeOut(duration: 0.28)) {
                floatingReactionScale = 1.4
                floatingReactionOpacity = 0
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) {
            floatingReactionEmoji = nil
            floatingReactionScale = 0.2
            if !showSheet && !ShowViewerSheet && !showReactionPicker
                && !statusStore.isSlidingToBottom {
                resumeTimer()
            }
        }
        pauseTimer()
    }

    private var safeViewCount: Int {
        let index = story.currentIndex
        guard story.status.indices.contains(index) else { return 0 }
        return story.status[index].viewCount
    }

    private var currentStatusItem: StatusItem? {
        let index = story.currentIndex
        guard story.status.indices.contains(index) else { return nil }
        return story.status[index]
    }

    @ViewBuilder
    private var failedStatusOverlay: some View {
        if isCurrentUser, let item = currentStatusItem, item.syncStatus == .failed {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.white)
                Text(t(ChatTranslationKeys.STORIES_FAILED_SEND))
                    .font(.headline)
                    .foregroundStyle(.white)
                Text(t(ChatTranslationKeys.STORIES_TAP_RETRY))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(24)
            .background(Color.black.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .allowsHitTesting(false)
            .zIndex(2)
        }
    }

    private func syncStoryFromStore() {
        guard !isSingleSegmentPresentation else { return }
        guard isCurrentUser, let latest = statusStore.ownStatus else { return }
        let preservedIndex = min(story.currentIndex, max(latest.status.count - 1, 0))
        story = latest
        story.currentIndex = preservedIndex
    }

    /// Refresh contact segments from the store and jump to the first unviewed item.
    private func applyContactResumeFromStore() {
        guard !isSingleSegmentPresentation, !isCurrentUser else { return }
        guard var latest = statusStore.contactStatus.first(where: { $0.id == story.id }) else { return }
        latest.applyResumeIndex()
        story = latest
        if let idx = statusStore.contactStatus.firstIndex(where: { $0.id == story.id }) {
            statusStore.contactStatus[idx].currentIndex = latest.currentIndex
        }
    }

    /// Mark local `viewed` + MQTT `view-story` only once media is ready on device.
    /// Call sites: text `onAppear`, image disk/`onReady`, video `OnStartPlaying` — never while loading/failed.
    private func markCurrentSegmentViewedIfNeeded(at index: Int) {
        guard !isCurrentUser, story.status.indices.contains(index) else { return }
        let status = story.status[index]
        guard !status.viewed else { return }

        statusStore.markAsSeen(
            contactUserId: status.userId,
            statusId: status.codeStatus,
            isStatusItem: true
        )
        story.status[index].viewed = true
        story.viewed = story.status.allSatisfy(\.viewed)
    }

    private func retryCurrentStatus(_ item: StatusItem) async {
        pauseTimer()
        if item.type != .text && !item.uploaded {
            await statusStore.RetryUploadAndPostStatus(statusId: item.codeStatus)
        } else {
            await statusStore.retryFailedSyncs(statusId: item.codeStatus)
        }
        syncStoryFromStore()
        loadCurrentImageIfNeeded()
        if currentStatusItem?.syncStatus != .failed {
            resumeTimer()
        }
    }

    private func pauseVideoIfNeeded() {
        let index = story.currentIndex
        guard story.status.indices.contains(index),
              story.status[index].type == .video else { return }
        controller.pause()
    }
    private var currentViewers: [SeenUser] {
        guard story.status.indices.contains(story.currentIndex) else { return [] }
        return story.status[story.currentIndex].seenUsers
    }

    private var viewersSheet: some View {
        Color.clear // Invisible overlay to allow attaching .sheet
            .sheet(isPresented: $ShowViewerSheet, onDismiss: {
                resumeTimer()
            }) {
                BottomSheetView(
                    viewers: currentViewers,
                    translationService: translationService
                )
                .presentationDragIndicator(.visible)
                .presentationDetents([.height(viewersSheetHeight(for: currentViewers.count))])
                // Status viewer is always black — keep seen-users sheet dark regardless of chat theme.
                .preferredColorScheme(.dark)
            }
    }

    /// Adaptive sheet height from viewer count — small when empty / few, capped when many.
    private func viewersSheetHeight(for count: Int) -> CGFloat {
        let headerHeight: CGFloat = 72
        let rowHeight: CGFloat = 72
        let emptyStatePadding: CGFloat = 24
        let minHeight: CGFloat = 180
        let maxHeight = UIScreen.main.bounds.height * 0.7

        if count == 0 {
            return max(minHeight, headerHeight + emptyStatePadding)
        }
        return min(max(minHeight, headerHeight + CGFloat(count) * rowHeight), maxHeight)
    }
    
    private func loadCurrentImageIfNeeded() {
        let index = story.currentIndex
        guard story.status.indices.contains(index), story.status[index].type == .image else { return }
        let item = story.status[index]
        DispatchQueue.global(qos: .userInitiated).async {
            let image = StatusLocalMediaResolver.diskImage(for: item)
            DispatchQueue.main.async {
                currentOwnImage = image
            }
        }
    }
    
    private func resumeTimerIfNeeded() {
        guard !statusStore.isSlidingToBottom,
              !statusStore.isPagingContacts,
              !isHoldingPause,
              !showSheet,
              !ShowViewerSheet,
              !showReactionPicker else { return }
        // Only the active page may resume.
        guard isViewerActive else { return }
        resumeTimer()
    }

    /// Gestures must not start the bar while image/video is still loading or failed.
    private var isCurrentMediaReadyForTimeline: Bool {
        guard let item = currentStatusItem else { return false }
        if item.syncStatus == .failed { return false }
        switch item.type {
        case .image:
            if loader.hasError { return false }
            if StatusLocalMediaResolver.diskImage(for: item) != nil { return true }
            if loader.image != nil { return true }
            return !Self.needsRemoteImageLoad(item)
        case .video:
            return !controller.isLoading && !controller.hasError
        case .text, .audio:
            return true
        }
    }
    
    // MARK: - Timeline (WhatsAppStories StoryBar)
    
    private func configureAndStartTimeline() {
        let durations = story.status.map { max(0.5, $0.duration) }
        timeline.configure(
            segmentCount: max(story.status.count, 1),
            durations: durations.isEmpty ? [5] : durations,
            startIndex: story.currentIndex
        )
        progress = 0

        if currentStatusItem?.syncStatus == .failed {
            isPaused = true
            return
        }
        if currentStatusItem?.type == .video {
            // Wait for player ready — OnStartPlaying restarts with real duration.
            isPaused = true
            return
        }
        if let item = currentStatusItem, item.type == .image, Self.needsRemoteImageLoad(item) {
            // Wait until the image is on screen — DownloadableImageView resumes via onResume.
            // Keep isPaused=true the whole time so a sync cache-hit onResume can't no-op.
            isPaused = true
            return
        }
        isPaused = false
        // Driver queues start if the UIKit bar isn't attached yet.
        timeline.start()
    }

    /// Remote image not yet on disk — timeline must wait for download.
    private static func needsRemoteImageLoad(_ item: StatusItem) -> Bool {
        guard item.type == .image else { return false }
        if StatusLocalMediaResolver.diskImage(for: item) != nil { return false }
        let content = item.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !content.isEmpty
    }

    private func pauseTimer(hideBar: Bool = true) {
        guard !isPaused else {
            timeline.pause(hideBar: hideBar)
            controller.pause()
            return
        }
        isPaused = true
        timeline.pause(hideBar: hideBar)
        controller.pause()
    }
    
    private func resumeTimer() {
        // Hold / slide / sheet dismiss must not burn duration on a spinner.
        guard isCurrentMediaReadyForTimeline else {
            isPaused = true
            timeline.pause(hideBar: false)
            return
        }
        guard !isHoldingPause,
              !showSheet,
              !ShowViewerSheet,
              !showReactionPicker,
              !statusStore.isSlidingToBottom,
              !statusStore.isPagingContacts else { return }

        isPaused = false
        controller.resume()
        if timeline.bar?.hasActiveAnimator == true {
            timeline.resume()
        } else if currentStatusItem?.type != .video,
                  currentStatusItem?.syncStatus != .failed {
            // Start even if isPaused was already false — avoids missing a one-shot onResume
            // that raced with configureAndStartTimeline.
            timeline.start()
        }
    }

    private func stopTimer() {
        timeline.stop()
    }
    
    // MARK: - Navigation
    private func nextStatus() {
        timeline.next()
    }
    
    private func previousStatus() {
        timeline.previous()
    }

    private func goToPreviousUserOrRestart() {
        guard isViewerActive else { return }

        if isSingleSegmentPresentation {
            controller.resetPlayer()
            story.currentIndex = 0
            configureAndStartTimeline()
            return
        }

        if isCurrentUser {
            controller.resetPlayer()
            story.currentIndex = 0
            configureAndStartTimeline()
            return
        }

        if let storyIndex = statusStore.contactStatus.firstIndex(where: { $0.id == story.id }), storyIndex > 0 {
            let previousIdx = storyIndex - 1
            statusStore.contactStatus[previousIdx].applyResumeIndex()
            animateToContact(at: previousIdx)
        } else {
            // Already first user — restart first segment.
            controller.resetPlayer()
            story.currentIndex = 0
            configureAndStartTimeline()
        }
    }
    
    // MARK: - Current Status View
    @ViewBuilder
    private func currentStatusView(ownImage: UIImage?, loader: ImageDownloader, currentIndex: Int) -> some View {
        let status = story.status[currentIndex]
        
        ZStack {
            switch status.type {
            case .image:
                if let diskImage = StatusLocalMediaResolver.diskImage(for: status) {
                    statusContainImage(diskImage)
                        .onAppear {
                            markCurrentSegmentViewedIfNeeded(at: currentIndex)
                            resumeTimer()
                        }
                } else if CurrentSessionInfo.shared.currentUid == status.userId, let image = ownImage {
                    statusContainImage(image)
                        .onAppear {
                            markCurrentSegmentViewedIfNeeded(at: currentIndex)
                            resumeTimer()
                        }
                } else {
                    DownloadableImageView(
                        loader: loader,
                        url: status.content ?? "",
                        scale: scale,
                        onPause: { pauseTimer() },
                        onResume: { resumeTimer() },
                        onReady: {
                            markCurrentSegmentViewedIfNeeded(at: currentIndex)
                        },
                        thumbnail: status.thumbnail?.cleanedBase64,
                        codeStatus: status.codeStatus,
                        translationService: translationService
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
                }
                
            case .text:
                TextStatusViewComponent(
                    text: status.content ?? "",
                    backgroundColor: Color(hex: status.background ?? "#000000"),
                    fontSize: status.fontSize.map(CGFloat.init),
                    fontFamily: status.fontText ?? "system",
                    fontWeight: status.fontWeight?.asFontWeight ?? .regular,
                    hasShadow: false,
                    fillsContainer: true
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    markCurrentSegmentViewedIfNeeded(at: currentIndex)
                }
                
            case .video:
                let playbackURL = StatusLocalMediaResolver.playbackURL(for: status)
                let showDownloadProblem = controller.hasError && !isCurrentUser
                ZStack {
                    CustomVideoPlayer(
                        url: playbackURL,
                        autoPlay: true,
                        fromServer: !(playbackURL?.isFileURL ?? false),
                        contentMode: .fit,
                        loaderColor: .blue,
                        OnStartPlaying: { duration in
                            markCurrentSegmentViewedIfNeeded(at: currentIndex)
                            // Stream now; cache full file + poster in background for strip preview.
                            StatusLocalMediaResolver.cacheRemoteVideoIfNeeded(for: status)
                            StatusLocalMediaResolver.cacheVideoPosterIfNeeded(
                                for: status,
                                from: StatusLocalMediaResolver.playbackURL(for: status)
                            )
                            if statusStore.isOwnStatus(userId: status.userId) {
                                statusStore.ownStatus?.status[currentIndex].duration = duration
                            } else if let idx = statusStore.contactStatus.firstIndex(where: { $0.userId == status.userId }) {
                                statusStore.contactStatus[idx].status[currentIndex].duration = duration
                            }
                            isPaused = false
                            timeline.restartCurrent(duration: max(0.5, duration))
                            controller.resume()
                        },
                        controller: controller
                    )
                    .id("\(status.codeStatus)-\(videoReloadNonce)")

                    // Contact offline / not-yet-downloaded: keep thumbnail under loader or on failure.
                    // Own published videos should not look "failed" from a transient player error.
                    if controller.isLoading || showDownloadProblem,
                       let poster = StatusLocalMediaResolver.thumbnailStill(for: status) {
                        statusContainImage(poster)
                            .blur(radius: showDownloadProblem ? 10 : 6)
                            .allowsHitTesting(false)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
                .onAppear {
                    pauseTimer()
                    if playbackURL == nil, !isCurrentUser {
                        controller.hasError = true
                        controller.isLoading = false
                    }
                }
                .onChange(of: controller.hasError) { failed in
                    if failed, !isCurrentUser { pauseTimer() }
                }
                
            case .audio:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusContainImage(_ image: UIImage) -> some View {
        GeometryReader { geo in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: geo.size.width, height: geo.size.height)
        }
        .background(Color.black)
    }
    
    private func updateToNextStory() {
        // Off-screen / inactive pages must never dismiss the viewer.
        guard isViewerActive else { return }

        if isSingleSegmentPresentation {
            story.currentIndex = 0
            controller.resetPlayer()
            statusStore.closeSingleSegmentViewer()
            return
        }

        // Own status is not part of the contact pager — just leave the viewer.
        if isCurrentUser {
            story.currentIndex = 0
            controller.resetPlayer()
            statusStore.goBack(coord: navigationCoord)
            return
        }

        guard let currentIdx = statusStore.contactStatus.firstIndex(where: { $0.id == story.id }),
              currentIdx + 1 < statusStore.contactStatus.count else {
            story.currentIndex = 0
            controller.resetPlayer()
            statusStore.goBack(coord: navigationCoord)
            return
        }

        statusStore.contactStatus[currentIdx].currentIndex = 0
        let nextIdx = currentIdx + 1
        statusStore.contactStatus[nextIdx].applyResumeIndex()
        animateToContact(at: nextIdx)
    }

    /// Animated page scroll so GeometryReader drives the same 3D tilt as a finger swipe.
    private func animateToContact(at index: Int) {
        guard statusStore.contactStatus.indices.contains(index) else { return }
        let nextId = statusStore.contactStatus[index].id
        controller.resetPlayer()
        pauseTimer(hideBar: false)
        statusStore.setPagingContacts(true)

        guard let storyPager else {
            statusStore.currentStory = nextId
            statusStore.setPagingContacts(false)
            return
        }

        // Animate the real pager scroll (drives 3D tilt), then sync selection.
        let didScroll = storyPager.scrollToPage(at: index, animated: true) {
            statusStore.currentStory = nextId
            statusStore.setPagingContacts(false)
        }
        if !didScroll {
            statusStore.currentStory = nextId
            statusStore.setPagingContacts(false)
        }
    }
    
    private enum ReplySendFeedback: Equatable {
        case sent
        case failed
    }

    @ViewBuilder
    private var statusReplyFeedbackBanner: some View {
        if let replySendFeedback {
            VStack {
                Spacer()
                HStack(spacing: 8) {
                    Image(systemName: replySendFeedback == .sent ? "paperplane.fill" : "exclamationmark.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                    Text(
                        replySendFeedback == .sent
                            ? t(ChatTranslationKeys.STORIES_MESSAGE_SENT)
                            : t(ChatTranslationKeys.STORIES_FAILED_SEND)
                    )
                    .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    (replySendFeedback == .sent ? AppColors.primary : Color.red.opacity(0.88))
                        .clipShape(Capsule())
                )
                .padding(.bottom, max(safeAreaBottom + 24, 40))
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(30)
            .allowsHitTesting(false)
        }
    }

    private func presentReplySendFeedback(_ feedback: ReplySendFeedback) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            replySendFeedback = feedback
        }
        if feedback == .sent {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } else {
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            withAnimation(.easeOut(duration: 0.25)) {
                if replySendFeedback == feedback {
                    replySendFeedback = nil
                }
            }
        }
    }

    private func dismissViewer() {
        if isSingleSegmentPresentation {
            statusStore.closeSingleSegmentViewer()
        } else if isCurrentUser {
            statusStore.goBack(coord: navigationCoord)
        } else {
            statusStore.goBacktoRoot(coord: navigationCoord)
        }
    }
    
    // MARK: - Keyboard Handling
    private func addKeyboardObservers() {
        keyboardCancellables.removeAll()
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)
            .receive(on: DispatchQueue.main)
            .sink { notification in
                guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else {
                    return
                }
                // Keyboard frame is screen-absolute; overlap from the bottom of the screen.
                // Subtract home-indicator inset so the field sits flush above the keys.
                let safeBottom = UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap(\.windows)
                    .first(where: \.isKeyWindow)?
                    .safeAreaInsets.bottom ?? 0
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = max(0, frame.height - safeBottom)
                }
            }
            .store(in: &keyboardCancellables)
        
        NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)
            .receive(on: DispatchQueue.main)
            .sink { _ in
                withAnimation(.easeOut(duration: 0.25)) {
                    keyboardHeight = 0
                }
            }
            .store(in: &keyboardCancellables)
    }
    
    private func removeKeyboardObservers() {
        keyboardCancellables.removeAll()
        keyboardHeight = 0
    }
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Bottom Sheet View
struct BottomSheetView: View {
    var viewers: [SeenUser]? = []
    let translationService: (any TranslationServiceProtocol)?
    
    init(viewers: [SeenUser]? = [], translationService: (any TranslationServiceProtocol)? = nil) {
        self.viewers = viewers
        self.translationService = translationService
    }
    
    var body: some View {
        VStack(spacing: 16) {
            Text(t(ChatTranslationKeys.STORIES_VIEWED_BY, args: ["\(viewers?.count ?? 0)"]))
                .font(.headline)
                .foregroundStyle(.primary)
            
            Divider()

            if !(viewers?.isEmpty ?? true) {
                ScrollView {
                    VStack(spacing: 15) {
                        ForEach(viewers ?? []) { viewer in
                            HStack(spacing: 10) {
                                ImageViewComponent(url: URL(string: viewer.image ?? ""), width: 50, height: 50, name: viewer.username)
                                
                                VStack(alignment: .leading) {
                                    Text(viewer.username)
                                        .foregroundStyle(.primary)
                                        .font(.headline)
                                    Text(formatDate(viewer.viewedAt))
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                }
                                
                                Spacer()

                                if let reaction = viewer.reaction, !reaction.isEmpty {
                                    Text(reaction)
                                        .font(.title2)
                                }
                            }
                            .padding(.horizontal)
                            .frame(maxHeight: 80)
                        }
                    }
                }
            }
        }
        .padding(.top)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(.systemBackground))
    }
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - DownloadableImageView
struct DownloadableImageView: View {
    @StateObject var loader: ImageDownloader
    let url: String
    let scale: CGFloat
    let onPause: () -> Void
    let onResume: () -> Void
    let onReady: () -> Void
    let thumbnail: String?
    let codeStatus: String?
    let translationService: (any TranslationServiceProtocol)?

    init(
        loader: ImageDownloader,
        url: String,
        scale: CGFloat,
        onPause: @escaping () -> Void,
        onResume: @escaping () -> Void,
        onReady: @escaping () -> Void,
        thumbnail: String?,
        codeStatus: String?,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._loader = StateObject(wrappedValue: loader)
        self.url = url
        self.scale = scale
        self.onPause = onPause
        self.onResume = onResume
        self.onReady = onReady
        self.thumbnail = thumbnail
        self.codeStatus = codeStatus
        self.translationService = translationService
    }
    
    // Cache decoded thumbnail to avoid re-decoding Base64 on every body evaluation
    @State private var cachedThumbnail: UIImage?
    private static var thumbnailCache: [String: UIImage] = [:]
    
    var body: some View {
        GeometryReader { geo in
            ZStack {
                if let img = loader.image {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geo.size.width, height: geo.size.height)
                        .scaleEffect(scale)
                        .animation(.easeInOut, value: scale)
                } else if loader.hasError {
                    ZStack {
                        if let uiImage = cachedThumbnail {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .blur(radius: 10)
                        }

                        // Interactive retry lives in `downloadRetryOverlay` above the gesture layer.
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 44))
                                .foregroundColor(.white)
                            Text(t(ChatTranslationKeys.STORIES_DOWNLOAD))
                                .foregroundColor(.white.opacity(0.85))
                                .font(.caption.weight(.semibold))
                        }
                        .allowsHitTesting(false)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .background(Color.red.opacity(0.1))
                } else {
                    ZStack {
                        if let uiImage = cachedThumbnail {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                                .frame(width: geo.size.width, height: geo.size.height)
                                .blur(radius: 10)
                        }
                        
                        CircularProgressBar(
                            progress: $loader.progress,
                            lineWidth: 5,
                            backgroundColor: .clear,
                            foregroundColor: .white,
                            showPercentage: false
                        )
                        .frame(width: 70, height: 70)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .onChange(of: loader.hasError) { _ in
            // Keep timeline paused while broken; user can retry manually.
            if loader.hasError { onPause() }
        }
        .onChange(of: url) { newUrl in
            loader.reset()
            onPause()
            loader.downloadImage(from: newUrl, codeStatus: codeStatus ?? "")
            // Disk/cache hit sets image synchronously — resume immediately.
            if loader.image != nil {
                onResume()
                onReady()
            }
        }
        .onChange(of: loader.image) { img in
            if img != nil {
                onResume()
                onReady()
            }
        }
        .onAppear {
            // Decode and cache thumbnail once
            if cachedThumbnail == nil, let thumb = thumbnail, !thumb.isEmpty {
                if let cached = Self.thumbnailCache[thumb] {
                    cachedThumbnail = cached
                } else if let decoded = imageFromDataURL(thumb) {
                    Self.thumbnailCache[thumb] = decoded
                    cachedThumbnail = decoded
                }
            }

            // Hold the story bar until the full image is visible (WhatsApp-style).
            if loader.image == nil {
                onPause()
            }
            loader.downloadImage(from: url, codeStatus: codeStatus ?? "")
            if loader.image != nil {
                onResume()
                onReady()
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Story Viewer & Card
@available(iOS 16.0, *)
struct StoryViewer: View {
    @ObservedObject var statusStore: StoriesViewModel
    @StateObject var videoModel : VideoPlayerController
    @StateObject private var storyPager = StoryPagerController()
    let navigationCoord:UpdatesTabCoordinator
    let translationService: (any TranslationServiceProtocol)?

    
    init(
        statusStore: StoriesViewModel,
        navigationCoord: UpdatesTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.statusStore = statusStore
        _videoModel = StateObject(wrappedValue: VideoPlayerController(storieVM: statusStore))
        self.navigationCoord = navigationCoord
        self.translationService = translationService
    }
    
    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TabView(selection: $statusStore.currentStory) {
                ForEach($statusStore.contactStatus) { story in
                    StoryCardView(
                        storie: story,
                        statusStore: statusStore,
                        navigationCoord: navigationCoord,
                        translationService: translationService
                    )
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)
            .background(
                StoryPagerScrollObserver(
                    pager: storyPager,
                    onPagingChanged: { isPaging in
                        statusStore.setPagingContacts(isPaging)
                    }
                )
            )
            .onDisappear {
                statusStore.setPagingContacts(false)
                videoModel.resetPlayer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .ignoresSafeArea()
        .environment(\.storyPager, storyPager)
        .onAppear {
            storyPager.onPagingChanged = { isPaging in
                statusStore.setPagingContacts(isPaging)
            }
        }
    }
}

/// Finds TabView's underlying UIScrollView and reports drag/decelerate
/// without forcing SwiftUI preference-driven redraws every frame.
private struct StoryPagerScrollObserver: UIViewRepresentable {
    let pager: StoryPagerController
    var onPagingChanged: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(pager: pager, onPagingChanged: onPagingChanged)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        context.coordinator.attach(from: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onPagingChanged = onPagingChanged
        context.coordinator.pager = pager
        context.coordinator.attach(from: uiView)
    }

    final class Coordinator: NSObject {
        var pager: StoryPagerController
        var onPagingChanged: (Bool) -> Void
        private weak var scrollView: UIScrollView?
        private var dragObservation: NSKeyValueObservation?
        private var decelObservation: NSKeyValueObservation?
        private var lastPaging = false

        init(pager: StoryPagerController, onPagingChanged: @escaping (Bool) -> Void) {
            self.pager = pager
            self.onPagingChanged = onPagingChanged
        }

        deinit {
            dragObservation?.invalidate()
            decelObservation?.invalidate()
        }

        func attach(from view: UIView) {
            DispatchQueue.main.async { [weak self, weak view] in
                guard let self, let view else { return }
                guard let scroll = Self.findPagingScrollView(from: view) else { return }
                self.pager.scrollView = scroll
                guard scroll !== self.scrollView else { return }
                self.dragObservation?.invalidate()
                self.decelObservation?.invalidate()
                self.scrollView = scroll

                let publish = { [weak self, weak scroll] in
                    guard let self, let scroll else { return }
                    self.publishPaging(scroll)
                }
                self.dragObservation = scroll.observe(\.isDragging, options: [.new]) { _, _ in publish() }
                self.decelObservation = scroll.observe(\.isDecelerating, options: [.new]) { _, _ in publish() }
                publish()
            }
        }

        private func publishPaging(_ scroll: UIScrollView) {
            let paging = scroll.isDragging || scroll.isDecelerating
            guard paging != lastPaging else { return }
            lastPaging = paging
            onPagingChanged(paging)
        }

        private static func findPagingScrollView(from view: UIView) -> UIScrollView? {
            var current: UIView? = view
            while let node = current {
                if let scroll = node as? UIScrollView, scroll.isPagingEnabled {
                    return scroll
                }
                for child in node.subviews {
                    if let found = findPagingScrollViewBFS(child) {
                        return found
                    }
                }
                current = node.superview
            }
            return nil
        }

        private static func findPagingScrollViewBFS(_ root: UIView) -> UIScrollView? {
            var queue: [UIView] = [root]
            while !queue.isEmpty {
                let node = queue.removeFirst()
                if let scroll = node as? UIScrollView, scroll.isPagingEnabled {
                    return scroll
                }
                queue.append(contentsOf: node.subviews)
            }
            return nil
        }
    }
}

@available(iOS 16.0, *)
struct StoryCardView: View {
    @Binding var storie: Status
     var statusStore: StoriesViewModel
    let navigationCoord:UpdatesTabCoordinator
    let translationService: (any TranslationServiceProtocol)?

    init(
        storie: Binding<Status>,
        statusStore: StoriesViewModel,
        navigationCoord: UpdatesTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._storie = storie
        self.statusStore = statusStore
        self.navigationCoord = navigationCoord
        self.translationService = translationService
    }

    var body: some View {
        GeometryReader { proxy in
            let minX = proxy.frame(in: .global).minX
            StatusViewer(
                storyId: storie.userId,
                viewModel: statusStore,
                updateTabCoordinator: navigationCoord,
                translationService: translationService
            )
            .frame(width: proxy.size.width, height: proxy.size.height)
            // Rotate the whole card (don't clip before tilt — that kills the 3D look).
            .rotation3DEffect(
                Angle(degrees: Double(45 * (minX / max(proxy.size.width, 1)))),
                axis: (x: 0, y: 1, z: 0),
                anchor: minX > 0 ? .leading : .trailing,
                perspective: 2.5
            )
        }
        .clipped()
        .background(Color.black)
        .tag(storie.id)
    }
}

/// Status reaction strip — same staggered spring feel as chat `ReactionPickerView`.
private struct StatusQuickReactionPicker: View {
    let emojis: [String]
    let onSelect: (String) -> Void

    @State private var animateBackground = false

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(emojis.enumerated()), id: \.element) { index, emoji in
                StatusReactionEmojiButton(emoji: emoji, entranceIndex: index) {
                    onSelect(emoji)
                }
            }
        }
        .fixedSize(horizontal: true, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(pickerBackground)
        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
        .frame(maxWidth: .infinity, alignment: .trailing)
        .onAppear {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.72)) {
                animateBackground = true
            }
        }
    }

    private var pickerBackground: some View {
        Capsule()
            .fill(.ultraThinMaterial)
            .overlay {
                Capsule()
                    .stroke(Color.white.opacity(0.35), lineWidth: 0.5)
            }
            .environment(\.colorScheme, .dark)
            .scaleEffect(animateBackground ? 1 : 0.2, anchor: .trailing)
            .opacity(animateBackground ? 1 : 0)
    }
}

private struct StatusReactionEmojiButton: View {
    let emoji: String
    let entranceIndex: Int
    let onTap: () -> Void

    @State private var appeared = false

    var body: some View {
        Button {
            Haptic.impact(.medium)
            onTap()
        } label: {
            Text(emoji)
                .font(.system(size: 28))
                .frame(width: 40, height: 40)
                .contentShape(Rectangle())
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

