//
//  ChatMediaEditorView.swift
//  FeatureChat
//

import AVKit
import WaanguCoreKit
import Photos
import WaanguSharedUI
import SwiftUI

/// Chat-specific media editor shell.
/// Combines WhatsApp-style media editor chrome (HD, save, stickers, caption bar, Restyle AI)
/// with Status editing primitives (crop, draw, text overlay, filters).
struct ChatMediaEditorView: View {

    let previewMedia: PreviewMediaItem
    let recipientName: String
    let mediaCount: Int
    let translationService: (any TranslationServiceProtocol)?
    let onSend: (String?, EditedMediaResult) -> Void
    let onDismiss: () -> Void
    var onAddMoreMedia: (() -> Void)?
    /// Sends as view once. Nil hides the toggle — channels have no view once.
    var onSendViewOnce: ((String?, EditedMediaResult) -> Void)?

    @State private var mediaInfo: MediaInfo
    @State private var loadedMedia: [MediaItem?] = []
    @State private var currentIndex = 0

    @State private var showCrop = false
    @State private var showFilter = false
    @State private var showStickerPicker = false
    @State private var addTextOnImage = false
    @State private var drawOnImage = false
    @State private var isDragging = false
    @State private var fontSize: CGFloat = 32
    @State private var caption = ""
    @State private var isReady = false
    @State private var isExporting = false
    @State private var isSaving = false
    @State private var saveToast: String?
    @State private var isHDEnabled = false
    @State private var isViewOnce = false
    @State private var selectedStickerIcon = ""
    @State private var currentPlayer = AVPlayer()
    @State private var containerSize: CGSize = .zero
    @State private var chromeVisible = false
    @StateObject private var videoTrimCache = VideoTrimCacheStore()

    init(
        previewMedia: PreviewMediaItem,
        recipientName: String,
        mediaCount: Int = 1,
        translationService: (any TranslationServiceProtocol)? = nil,
        onSend: @escaping (String?, EditedMediaResult) -> Void,
        onDismiss: @escaping () -> Void,
        onAddMoreMedia: (() -> Void)? = nil,
        onSendViewOnce: ((String?, EditedMediaResult) -> Void)? = nil
    ) {
        self.previewMedia = previewMedia
        self.recipientName = recipientName
        self.mediaCount = max(1, mediaCount)
        self.translationService = translationService
        self.onSend = onSend
        self.onDismiss = onDismiss
        self.onAddMoreMedia = onAddMoreMedia
        self.onSendViewOnce = onSendViewOnce

        if let state = MediaEditorBridge.makeEditorState(from: previewMedia) {
            _mediaInfo = State(initialValue: state.1)
            _loadedMedia = State(initialValue: [state.0])
            _isReady = State(initialValue: true)
        } else {
            _mediaInfo = State(initialValue: MediaEditorBridge.freshMediaInfo(
                for: MediaItem(image: nil, type: .none, fileSize: 0)
            ))
            _loadedMedia = State(initialValue: [])
            _isReady = State(initialValue: false)
        }
    }

    private var isVideo: Bool { mediaInfo.media?.type == .video }
    /// Hides chrome for draw/text modes — filter keeps toolbar visible so it can be dismissed.
    private var chromeHidden: Bool { addTextOnImage || drawOnImage || isDragging }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if isReady {
                GeometryReader { geo in
                    ZStack {
                        mediaCanvas(in: geo)

                        if drawOnImage {
                            drawingOverlay(in: geo)
                        }

                        if addTextOnImage {
                            TextOnImage(
                                addTextOnImage: $addTextOnImage,
                                text: $mediaInfo.overLayText,
                                selectedFontIndex: $mediaInfo.selectedFontIndex,
                                fontSize: $fontSize,
                                currentPlayer: $currentPlayer,
                                currentInfo: $mediaInfo,
                                selectedTextColor: $mediaInfo.selectedTextColor,
                                translationService: translationService
                            )
                            .zIndex(10)
                        }

                        if isDragging {
                            deleteZone(in: geo)
                        }

                        VStack(spacing: 0) {
                            if showFilter {
                                filterDoneBar
                            }

                            chatTopToolbar
                                .offset(y: chromeHidden ? -120 : (chromeVisible ? 0 : -40))
                                .opacity(chromeHidden ? 0 : (chromeVisible ? 1 : 0))

                            Spacer()

                            if showFilter, !isVideo, let image = mediaInfo.media?.image {
                                FilterView(selectedFilter: $mediaInfo.imageFilter, image: image)
                                    .frame(height: 180)
                                    .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if !chromeHidden && !showFilter {
                                restyleWithAIPill
                                    .padding(.bottom, 12)
                                    .opacity(chromeVisible ? 1 : 0)
                                    .offset(y: chromeVisible ? 0 : 16)
                            }

                            chatBottomBar
                                .offset(y: (addTextOnImage || drawOnImage || isDragging || showFilter)
                                        ? 200
                                        : (chromeVisible ? 0 : 40))
                                .opacity((addTextOnImage || drawOnImage || showFilter)
                                         ? 0
                                         : (chromeVisible ? 1 : 0))
                        }
                    }
                    .onAppear { containerSize = geo.size }
                    .onChange(of: geo.size) { containerSize = $0 }
                }
            } else {
                ProgressView()
                    .tint(.white)
                    .task { await loadIfNeeded() }
            }

            if isExporting || isSaving {
                Color.black.opacity(0.5).ignoresSafeArea()
                ProgressView(isSaving ? "Saving…" : "Preparing…")
                    .tint(.white)
                    .foregroundStyle(.white)
            }

            if let saveToast {
                VStack {
                    Text(saveToast)
                        .font(.subheadline)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(Capsule().fill(Color.black.opacity(0.75)))
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        withAnimation { self.saveToast = nil }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .preferredColorScheme(.dark)
        .onAppear {
            withAnimation(ChatMediaOpenAnimation.chromeEnter) {
                chromeVisible = true
            }
        }
        .onChange(of: isReady) { ready in
            if ready {
                withAnimation(ChatMediaOpenAnimation.chromeEnter) {
                    chromeVisible = true
                }
            }
        }
        .chatAppearanceFullScreenCover(isPresented: $showCrop) {
            if loadedMedia.indices.contains(currentIndex) {
                PhotoCropEditor(
                    showFullScreen: $showCrop,
                    currentInfo: $mediaInfo,
                    loadedMedia: $loadedMedia,
                    currentIndex: $currentIndex
                )
            }
        }
        .chatAppearanceSheet(isPresented: $showStickerPicker) {
            ChatMediaStickerPickerSheet(
                selectedIcon: $selectedStickerIcon,
                translationService: translationService,
                onPick: { sticker in
                    applySticker(sticker)
                    showStickerPicker = false
                }
            )
            .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Canvas

    @ViewBuilder
    private func mediaCanvas(in geo: GeometryProxy) -> some View {
        if isVideo {
            ZStack {
                if let phAsset = mediaInfo.media?.PHMedia?.asset {
                    VideoTrimmerView(
                        cacheStore: videoTrimCache,
                        pHAsset: phAsset,
                        hideTrimmer: drawOnImage,
                        showsEstimatedSendSize: true,
                        useHD: isHDEnabled,
                        maxTrimDuration: ChatVideoSendPolicy.maxDurationSeconds,
                        currentPlayer: $currentPlayer,
                        onTrim: { start, end in
                            mediaInfo.media?.video?.startTime = start
                            mediaInfo.media?.video?.endTime = end
                        },
                        translationService: translationService
                    )
                    .padding(.vertical, 70)
                    .allowsHitTesting(!drawOnImage && !addTextOnImage)
                } else if let url = previewMedia.videoURL ?? mediaInfo.media?.video?.url {
                    VideoTrimmerView(
                        cacheStore: videoTrimCache,
                        videoURL: url,
                        hideTrimmer: drawOnImage,
                        showsEstimatedSendSize: true,
                        useHD: isHDEnabled,
                        maxTrimDuration: ChatVideoSendPolicy.maxDurationSeconds,
                        currentPlayer: $currentPlayer,
                        onTrim: { start, end in
                            mediaInfo.media?.video?.startTime = start
                            mediaInfo.media?.video?.endTime = end
                        },
                        translationService: translationService
                    )
                    .padding(.vertical, 70)
                    .allowsHitTesting(!drawOnImage && !addTextOnImage)
                }

                if !drawOnImage {
                    Canvas { context, _ in
                        strokeLines(in: &context)
                    }
                    .allowsHitTesting(false)
                    .zIndex(4)
                }

                TextOverlayView(
                    currentInfoBinding: $mediaInfo,
                    addTextOnImage: $addTextOnImage,
                    selectedTextColor: $mediaInfo.selectedTextColor,
                    selectedFontIndex: $mediaInfo.selectedFontIndex,
                    fontSize: $fontSize,
                    isDraging: $isDragging,
                    geo: geo
                )
                .zIndex(5)
            }
            .zIndex(3)
            .compositingGroup()
        } else {
            FilteredImageView(
                path: mediaInfo.media?.image,
                filter: mediaInfo.imageFilter,
                currentInfo: $mediaInfo,
                addTextOnImage: $addTextOnImage,
                fontSize: $fontSize,
                isDraging: $isDragging,
                geo: geo,
                translationService: translationService
            )
        }
    }

    private func drawingOverlay(in geo: GeometryProxy) -> some View {
        DrawingView(
            lines: $mediaInfo.lines,
            currentLine: $mediaInfo.currentLine,
            selectedColor: $mediaInfo.drawSelectedColor,
            drawOnImage: $drawOnImage,
            currentPlayer: $currentPlayer,
            selectedLineWidth: $mediaInfo.selectedLineWidth,
            currentInfo: $mediaInfo,
            imageRect: MediaEditorBridge.fittedImageRect(
                forImageSize: mediaInfo.imageOriginalSize ?? geo.size,
                inFrameSize: geo.size
            ),
            translationService: translationService
        )
        .zIndex(10)
    }

    private func strokeLines(in context: inout GraphicsContext) {
        for line in mediaInfo.lines {
            var path = Path()
            path.addLines(line.points)
            context.stroke(path, with: .color(line.color), lineWidth: line.lineWidth)
        }
        if let current = mediaInfo.currentLine {
            var path = Path()
            path.addLines(current.points)
            context.stroke(path, with: .color(current.color), lineWidth: current.lineWidth)
        }
    }

    private func deleteZone(in geo: GeometryProxy) -> some View {
        HStack {
            Image(systemName: "trash")
                .resizable()
                .scaledToFit()
                .frame(height: 44)
                .foregroundStyle(.white)
        }
        .padding(50)
        .background(.red.opacity(mediaInfo.textPosition.y < 70 ? 0.8 : 0.5))
        .clipShape(Circle())
        .offset(x: geo.size.width * -0.15, y: geo.size.height * -0.1)
    }

    // MARK: - Filter done bar

    private var filterDoneBar: some View {
        HStack {
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    showFilter = false
                }
            } label: {
                Text(doneLabel)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .clipShape(Capsule())
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var doneLabel: String {
        translationService?
            .resolve(key: ChatTranslationKeys.STORIES_DONE, module: ChatTranslationKeys.MODULE)
            .value ?? "Done"
    }

    // MARK: - Chat media editor top toolbar (WhatsApp-style)

    private var chatTopToolbar: some View {
        HStack(spacing: 22) {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .mediaEditorToolbarIcon()
            }

            Spacer()

            Button(action: saveToCameraRoll) {
                Image(systemName: "square.and.arrow.down")
                    .mediaEditorToolbarIcon()
            }
            .disabled(isVideo && previewMedia.videoURL == nil && mediaInfo.media?.PHMedia?.asset == nil)

            Button {
                withAnimation { isHDEnabled.toggle() }
            } label: {
                Text("HD")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isHDEnabled ? AppColors.primary : .white.opacity(0.55))
                    .lineLimit(1)
                    .fixedSize()
                    .layoutPriority(1)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(isHDEnabled ? AppColors.primary : Color.white.opacity(0.8), lineWidth: 1)
                    )
            }

            if !isVideo {
                Button { withAnimation { showCrop = true } } label: {
                    Image(systemName: "crop")
                        .mediaEditorToolbarIcon()
                }
            }

            Button {
                showStickerPicker = true
            } label: {
                Image(systemName: "seal")
                    .mediaEditorToolbarIcon()
            }

            Button {
                withAnimation {
                    addTextOnImage = true
                    currentPlayer.pause()
                }
            } label: {
                Text("Aa")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
            }

            Button {
                withAnimation {
                    drawOnImage = true
                    showFilter = false
                    currentPlayer.pause()
                }
            } label: {
                Image(systemName: "pencil.tip")
                    .mediaEditorToolbarIcon()
            }

            if !isVideo {
                Button {
                    withAnimation { showFilter.toggle() }
                } label: {
                    Image(systemName: "camera.filters")
                        .mediaEditorToolbarIcon()
                        .foregroundStyle(showFilter ? AppColors.primary : .white)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    // MARK: - Restyle with AI (chat media editor feature)

    private var restyleWithAIPill: some View {
        Button {
            // Placeholder — AI restyle pipeline to be wired separately
            withAnimation { saveToast = "Restyle with AI coming soon" }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                Text("Restyle with AI")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(Capsule().fill(Color.white.opacity(0.16)))
            .overlay(Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1))
        }
    }

    // MARK: - Chat bottom bar (caption + paperclip + count + recipient + send)

    private var chatBottomBar: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button(action: handlePaperclipTap) {
                    Image(systemName: "paperclip")
                        .foregroundStyle(.white.opacity(0.85))
                        .font(.system(size: 16))
                        .padding(.leading, 4)
                }

                TextField("", text: $caption, prompt: Text("Add a caption...")
                    .foregroundStyle(.white.opacity(0.55)))
                    .foregroundStyle(.white)
                    .font(.system(size: 16))

                // The view-once toggle takes the place of the old media-count
                // badge, where WhatsApp puts it too.
                if onSendViewOnce != nil {
                    viewOnceToggle
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color.white.opacity(0.12))
            )
            .padding(.horizontal, 10)

            HStack {
                Text(recipientName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Capsule().fill(Color.white.opacity(0.10)))
                    .padding(.leading, 14)

                Spacer()

                Button(action: handleSend) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(AppColors.primary))
                }
                .disabled(isExporting)
                .padding(.trailing, 14)
            }
        }
        .padding(.bottom, 20)
    }

    /// Off: a white timer in an outline. On: a white timer on a filled primary
    /// circle — the same two states as the voice recorder's button.
    private var viewOnceToggle: some View {
        Button {
            withAnimation(.easeOut(duration: 0.15)) { isViewOnce.toggle() }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            Image(systemName: "timer")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Circle().fill(isViewOnce ? AppColors.primary : Color.clear))
                .overlay(Circle().stroke(Color.white.opacity(isViewOnce ? 0 : 0.6), lineWidth: 1.2))
        }
        .accessibilityLabel(t(ChatTranslationKeys.CHAT_A11Y_VIEW_ONCE, fallback: "View once"))
        .accessibilityAddTraits(isViewOnce ? .isSelected : [])
    }

    private func t(_ key: String, fallback: String) -> String {
        translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE)
            .value ?? fallback
    }

    // MARK: - Actions

    private func loadIfNeeded() async {
        guard !isReady else { return }

        if let gallery = previewMedia.galleryMedia, gallery.highQualityImage == nil, gallery.type == .image {
            await withCheckedContinuation { continuation in
                PHMediaManagerViewModel.loadPreviewImage(for: gallery.asset) { image in
                    var updated = gallery
                    updated.highQualityImage = image
                    if let state = MediaEditorBridge.makeEditorState(
                        from: PreviewMediaItem(source: .gallery(updated))
                    ) {
                        mediaInfo = state.1
                        loadedMedia = [state.0]
                        isReady = true
                    }
                    continuation.resume()
                }
            }
        } else if let state = MediaEditorBridge.makeEditorState(from: previewMedia) {
            mediaInfo = state.1
            loadedMedia = [state.0]
            isReady = true
        }
    }

    private func handlePaperclipTap() {
        if let onAddMoreMedia {
            onAddMoreMedia()
        } else {
            onDismiss()
        }
    }

    private func applySticker(_ sticker: String) {
        guard !sticker.isEmpty else { return }
        if mediaInfo.overLayText.isEmpty {
            mediaInfo.overLayText = sticker
        } else {
            mediaInfo.overLayText += sticker
        }
        addTextOnImage = true
    }

    private func saveToCameraRoll() {
        guard let item = mediaInfo.media else { return }
        isSaving = true

        Task { @MainActor in
            let result = await MediaEditorExporter.export(
                preview: previewMedia,
                mediaInfo: mediaInfo,
                mediaItem: item,
                containerSize: containerSize,
                fontSize: fontSize,
                addTextOnImage: addTextOnImage,
                isDragging: isDragging,
                useHD: isHDEnabled,
                translationService: translationService
            )

            isSaving = false

            switch result {
            case .exportedImage(let image, _):
                persistImageToPhotoLibrary(image)
            case .exportedVideo(let url):
                persistVideoToPhotoLibrary(url)
            case .uneditedGallery(let media):
                if let image = media.highQualityImage ?? mediaInfo.media?.image {
                    persistImageToPhotoLibrary(image)
                }
            }
        }
    }

    private func persistImageToPhotoLibrary(_ image: UIImage) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async {
                    saveToast = "Photo library access denied"
                }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }) { success, _ in
                DispatchQueue.main.async {
                    withAnimation {
                        saveToast = success ? "Saved to Photos" : "Could not save"
                    }
                }
            }
        }
    }

    private func persistVideoToPhotoLibrary(_ url: URL) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { saveToast = "Photo library access denied" }
                return
            }
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, _ in
                DispatchQueue.main.async {
                    withAnimation {
                        saveToast = success ? "Saved to Photos" : "Could not save"
                    }
                }
            }
        }
    }

    private func handleSend() {
        guard let item = mediaInfo.media else { return }
        isExporting = true

        Task { @MainActor in
            let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
            let captionText = trimmed.isEmpty ? nil : trimmed

            let result = await MediaEditorExporter.export(
                preview: previewMedia,
                mediaInfo: mediaInfo,
                mediaItem: item,
                containerSize: containerSize,
                fontSize: fontSize,
                addTextOnImage: addTextOnImage,
                isDragging: isDragging,
                useHD: isHDEnabled,
                translationService: translationService
            )

            isExporting = false
            if isViewOnce, let onSendViewOnce {
                onSendViewOnce(captionText, result)
            } else {
                onSend(captionText, result)
            }
        }
    }
}

// MARK: - Sticker picker sheet

private struct ChatMediaStickerPickerSheet: View {
    @Binding var selectedIcon: String
    let translationService: (any TranslationServiceProtocol)?
    let onPick: (String) -> Void

    @State private var selectedCategory: EmojiCategory = .smileys

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                        spacing: 12
                    ) {
                        ForEach(selectedCategory.emojis, id: \.self) { emoji in
                            Button {
                                selectedIcon = emoji
                                onPick(emoji)
                            } label: {
                                Text(emoji)
                                    .font(.system(size: 32))
                                    .frame(minHeight: 44)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }

                Divider()

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(EmojiCategory.allCases, id: \.self) { category in
                            Button {
                                selectedCategory = category
                            } label: {
                                Image(systemName: category.icon)
                                    .font(.system(size: 18))
                                    .foregroundStyle(selectedCategory == category ? AppColors.primary : .gray)
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .frame(height: 50)
            }
            .navigationTitle("Stickers")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Toolbar icon style

private extension Image {
    func mediaEditorToolbarIcon() -> some View {
        font(.system(size: 18, weight: .medium))
            .foregroundStyle(.white)
    }
}
