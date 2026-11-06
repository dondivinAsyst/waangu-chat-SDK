import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import UIKit
import AVKit
import Photos
import WaanguSharedUI
import WaanguCoreKit


@available(iOS 16.0, *)
struct StatusEditor: View {
//    private let fontData = FontData.shared
    private let myFont = ConstantFont.shared.AllFonts
    private let colors = ConstantColors.customColors
    @Environment(\.dismiss) var dismiss
    @ObservedObject var statusStore:StoriesViewModel
    @StateObject var videoModel : VideoPlayerController
    let translationService: (any TranslationServiceProtocol)?
    let viewModel: PHMediaManagerViewModel
//    @State private var text: String = ""
    @State private var height : CGFloat = 30
    @State private var animateArrow = false
    @State private var showContactPreference = false
//    @State private var selectedFilter: FilterType = .none
    @State private var showFilterView = false
    @State private var loadedImages: [String: UIImage] = [:]
    @State private var addTextOnImage : Bool = false
    @State private var drawOnImage : Bool = false
    @State private var isAddingMedia : Bool = false
//    @State private var  selectedFontIndex : Int = 0
    @State private var fontSize: CGFloat = TextStatusFontSizing.baseFontSize
//    @State private var selectedTextColor: Color = .black
    @State private var isDraging : Bool = false
    @State private var isInDeleteTextZone : Bool = false
    @State private var isRotating : Bool = false
    @State private var isInDeleteTextSpace : Bool = false
    @State private var isChangingImage : Bool = false
    @State private var showFullScreen : Bool = false
    var selectedMedia : [Any] = []
//    @State private var selectedImages : [Any] = ["https://letsenhance.io/static/73136da51c245e80edc6ccfe44888a99/396e9/MainBefore.jpg","https://img.freepik.com/free-photo/closeup-scarlet-macaw-from-side-view-scarlet-macaw-closeup-head_488145-3540.jpg","https://picsum.photos/400/300"]
     @State private var currentMediaState: [MediaInfo] = []
//     @State private var currentMedia: MediaInfo? = nil
     @State private var currentIndex: Int = 0
    var imageURL: String = "https://letsenhance.io/static/73136da51c245e80edc6ccfe44888a99/396e9/MainBefore.jpg"
//    @State private var uiImage: UIImage? = nil
//    @State private var loadedUIImages : [UIImage?] = []
    @State private var loadedMedia : [MediaItem?] = []
    
    @State private var showStatusPrivacy = false
    @State private var showMentionPicker = false
    @State private var mentionedText = ""
    @State private var rect : CGRect = .zero
    @State private var genImageUI : UIImage = UIImage()
    @State private var showGeneratedImage : Bool = false
    @State private var currentPlayer = AVPlayer()
    @State private var startTime = 0.0
    @State private var endTime = 0.0
    @State private var isExporting = false
    @State private var exportProgress: Float = 0
    
    init(
        selectedMedia: [Any],
        statusStore: StoriesViewModel,
        phMediaManagerViewModel: PHMediaManagerViewModel,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.selectedMedia = selectedMedia
        self.statusStore = statusStore
        self.translationService = translationService
        _videoModel = StateObject(wrappedValue: VideoPlayerController(storieVM: statusStore))
        self.viewModel = phMediaManagerViewModel
    }
    
//    @StateObject private var model = VideoPlayerController()

    // MARK: - Current image helpers

    @State private var currentInfo = MediaInfo(
         imageFilter: .none,
         overLayText: "",
         captionText: "",
         selectedTextColor: .black,
         selectedFontIndex: 0,
         lines: [],
         drawSelectedColor: .green,
         selectedLineWidth : 5,
         textScale: 1.0,
         lastScale: 1.0,
         textOffset: .zero,
         lastOffset: .zero,
         textPosition: .zero
     )

    private var currentInfoBinding: Binding<MediaInfo> {
        Binding(
            get: { currentInfo },
            set: { currentInfo = $0 }
        )
    }

    var overlayTextBinding: Binding<String> {
        Binding(
            get: { currentInfo.overLayText },
            set: { newValue in
                currentInfo.overLayText = newValue
            }
        )
    }
    var captionTextBinding: Binding<String> {
        Binding(
            get: { currentInfo.captionText },
            set: { newValue in
                currentInfo.captionText = newValue
            }
        )
    }
    
    func getSelectedFileURL(from imageURL: String) -> URL? {
        let fileString = imageURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !fileString.isEmpty else { return nil }
        
        // Try absolute URL (e.g., file://, https://)
        if let url = URL(string: fileString), url.scheme != nil {
            return url
        }
        // Fallback to a local path
        return URL(fileURLWithPath: fileString)
    }
    
    
    // Thumbnail loader for the horizontal strip
    private func loadImage(from url: URL, for key: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let data = try Data(contentsOf: url)
                if let image = UIImage(data: data) {
                    DispatchQueue.main.async {
                        self.loadedImages[key] = image
                    }
                }
            } catch {
                #if DEBUG
                print("❌ Failed to load image for key \(key): \(error)")
                #endif
            }
        }
    }
    
    private func saveImage(lines: [Line], background: UIImage,imageSize: CGSize) -> (url: URL?, image: UIImage?) {
       // Validate size is non-zero
        let size = imageSize
        guard size.width > 0 && size.height > 0 else {
            debugLog("❌ Invalid size for drawing lines: \(size)")
            return (nil, nil)
        }

        let renderer = UIGraphicsImageRenderer(size: size)

        let image = renderer.image { ctx in
            
            // Draw background
            background.draw(in: CGRect(origin: .zero, size: size))

            // Draw lines
            for line in lines {
                let path = UIBezierPath()
                guard !line.points.isEmpty else { continue }

                path.move(to: line.points[0])

                for point in line.points.dropFirst() {
                    path.addLine(to: point)
                }

                UIColor(line.color).setStroke()
                path.lineWidth = line.lineWidth
                path.lineCapStyle = .round
                path.lineJoinStyle = .round

                path.stroke()
            }
        }

        let url = saveToDocuments(image: image, name: UUID().uuidString)
        #if DEBUG
        print("Image generated successfully. URL: \(url?.absoluteString ?? "")")
        #endif

        return (url, image)
    }

    func loadGenImage(from url: URL) async throws -> UIImage {
        let data = try Data(contentsOf: url)
        guard let image = UIImage(data: data) else {
            throw NSError(domain: "ImageLoading", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to decode image"])
        }
        return image
    }

    func saveToDocuments(image: UIImage, name: String) -> URL? {
        guard let data = image.jpegData(compressionQuality: 1.0) else { return nil }

        guard let url = FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("\(name).jpg") else { return nil }

        do {
            try data.write(to: url)
            return url
        } catch {
            #if DEBUG
            print("Save error:", error)
            #endif
            return nil
        }
    }

    func fittedImageRect(forImageSize imageSize: CGSize, inFrameSize frameSize: CGSize) -> CGRect {
        let imageAspect = imageSize.width / imageSize.height
        let frameAspect = frameSize.width / frameSize.height

        var drawSize = CGSize.zero

        if imageAspect > frameAspect {
            // Image is wider — match width
            drawSize.width = frameSize.width
            drawSize.height = frameSize.width / imageAspect
        } else {
            // Image is taller — match height
            drawSize.height = frameSize.height
            drawSize.width = frameSize.height * imageAspect
        }

        // Center inside frame
        let origin = CGPoint(
            x: (frameSize.width - drawSize.width) / 2,
            y: (frameSize.height - drawSize.height) / 2
        )
        return CGRect(origin: origin, size: drawSize)
    }


    
    private func onPublishStatus(geo: GeometryProxy) {
        currentMediaState[currentIndex] = currentInfo

        var myStatus: [StoryToSend] = []

        for (index, media) in loadedMedia.enumerated() {
            #if DEBUG
            print("Current index is \(index)")
            #endif
            guard currentMediaState.indices.contains(index) else { continue }
            let currentInfoIdx = currentMediaState[index]
            // ---------------------------
            // HANDLE IMAGE
            // ---------------------------
            if media?.video?.url == nil {

                if media?.type == .image {
                    let backgroundView = FilteredImageView(
                        path: media?.image,
                        filter: currentInfoIdx.imageFilter,
                        hideCanvas: true,
                        currentInfo: $currentMediaState[index],
                        addTextOnImage: $addTextOnImage,
                        fontSize: $fontSize,
                        isDraging: $isDraging,
                        geo: geo,
                        translationService: translationService
                    )
//                        .frame(width: currentInfoIdx.imageRenderedSize.width,height: currentInfoIdx.imageRenderedSize.height).clipped()

                    let backgroundImage = backgroundView.asUIImage(size: currentInfoIdx.imageRenderedSize)
//                    let url = saveToDocuments(image: backgroundImage, name: UUID().uuidString)
                    let savedImage = saveImage(
                        lines: currentInfoIdx.lines,
                        background: backgroundImage,
                        imageSize: currentInfoIdx.imageRenderedSize
                    )

                    #if DEBUG
                    print("Image processed at index \(index), url = \(savedImage.url?.absoluteString ?? "nil")")
                    #endif
                  
//
                    let st = StoryToSend(
                        id: StatusIDGenerator.newCode(),
                        userId: CurrentSessionInfo.shared.currentUid,
                        type: .image,
                        content: savedImage.url?.absoluteString,
                        caption: currentInfoIdx.captionText,
                        PHMedia: media?.PHMedia,
//                        thumbnail: imageToDataURL(currentMediaState[index].media?.image ?? UIImage()),
                        thumbnail: imageToDataURL(savedImage.image ?? UIImage()),
                        userName: CurrentSessionInfo.shared.userName,
//                        userImage: CurrentSessionInfo.shared.userProfile,
                        userImage: nil,
                        fileSize: currentInfoIdx.media?.fileSize ?? 0
                      
                       
                    )
                    myStatus.append(st)
                }

                if index == loadedMedia.count - 1 {
                    for status in myStatus {
                        Task{
                            await statusStore.addOwnStatus(story:status)
                        }
                    }
                    dismiss()
                    withAnimation{
                        statusStore.isFirstPageStory = true
                    }
                }

                continue
            }

            // ---------------------------
            // HANDLE VIDEO (async)
            // ---------------------------
            guard let phAsset = media?.video?.pHAsset else { continue }
            var asset : AVAsset?
            let options = PHVideoRequestOptions()
            options.version = .current
            options.isNetworkAccessAllowed = true
            Task {
                
            await withCheckedContinuation { continuation in
                PHImageManager.default().requestAVAsset(forVideo: phAsset, options: options) { avAsset, _, _ in
                    Task { @MainActor in
                        asset = avAsset
                        continuation.resume()
                    }
                }
            }

//             asset = AVAsset(url: url)

            // Create unique output
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("trimmed_\(UUID().uuidString).mp4")
                let outputURL1 = FileManager.default.temporaryDirectory
                .appendingPathComponent("composite_\(UUID().uuidString).mp4")

         
                let cacheKey = phAsset.localIdentifier
                let duration = statusStore.videoCache[cacheKey]?.trimDuration ?? 30

                let success = await videoModel.exportTrimmedVideo(
                    to: outputURL,
                    videoID: cacheKey,
                    asset: asset
                )

                if success {
                    #if DEBUG
                    print("🔥Exported index \(index) duration \(duration) → \(outputURL)")
                    #endif
                    let id = StatusIDGenerator.newCode()
                    
                    // Build drawing lines and text overlays for video composition
                    let hasDrawings = !currentMediaState[index].lines.isEmpty
                    let hasText = !currentMediaState[index].overLayText.isEmpty
                    
                    // Determine the final video URL (with or without overlays)
                    var finalVideoURL = outputURL
                    
                    if hasDrawings || hasText {
                        let drawingLines: [DrawingLine] = currentMediaState[index].lines.map { line in
                            DrawingLine(
                                points: line.points,
                                color: UIColor(line.color),
                                lineWidth: line.lineWidth
                            )
                        }
                        
                        var textOverlays: [TextOverlay] = []
                        if hasText {
                            // Compute the exact same colors as the display view
                            let selectedColor = currentMediaState[index].selectedTextColor
                            let bg = adjustedBackground(forTextColor: selectedColor)
                            let normalizedBG = normalizeBackgroundForEdges(bg, forTextColor: selectedColor)
                            let visibleTextColor = readableTextColor(forBackground: normalizedBG)
                            
                            // Compute the actual center position of the text overlay.
                            // The display uses: centered in screen + .offset(textOffset)
                            // textPosition is set during drag = screenCenter + textOffset
                            // If user never dragged, textPosition is .zero → compute from offset
                            let mediaInfo = currentMediaState[index]
                            var textCenter = mediaInfo.textPosition
                            if textCenter == .zero {
                                textCenter = CGPoint(
                                    x: self.rect.size.width / 2 + mediaInfo.textOffset.width,
                                    y: self.rect.size.height / 2 + mediaInfo.textOffset.height
                                )
                            }
                            
                            textOverlays.append(
                                TextOverlay(
                                    text: mediaInfo.overLayText,
                                    position: textCenter,
                                    font: UIFont(name: ConstantFont.shared.AllFonts[mediaInfo.selectedFontIndex].family, size: fontSize) ?? UIFont.systemFont(ofSize: fontSize),
                                    color: UIColor(visibleTextColor),
                                    backgroundColor: UIColor(normalizedBG),
                                    scale: mediaInfo.textScale
                                )
                            )
                        }
                        
                        // Show loading state
                        await MainActor.run {
                            self.isExporting = true
                            self.exportProgress = 0
                        }
                        
                        // Compose video with overlays using async continuation
                        let compositeSuccess = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                            composeVideoWithOverlays(
                                videoURL: outputURL,
                                drawings: drawingLines,
                                textOverlays: textOverlays,
                                screenSize: self.rect.size,
                                outputURL: outputURL1,
                                onProgress: { progress in
                                    self.exportProgress = progress
                                }
                            ) { result in
                                switch result {
                                case .success(let url):
                                    finalVideoURL = url
                                    continuation.resume(returning: true)
                                case .failure(_):
                                    #if DEBUG
                                    print("⚠️ Video composition failed, using trimmed video without overlays")
                                    #endif
                                    continuation.resume(returning: false)
                                }
                            }
                        }
                        
                        await MainActor.run {
                            self.isExporting = false
                        }
                        
                        if compositeSuccess {
                            finalVideoURL = outputURL1
                        }
                    }
                    
                    DiskMediaManager.shared.saveVideoToDisk(from: finalVideoURL, fileName: id, pathName: .STATUS)
                    // Prefer a frame from the *final* exported video (trim/overlays), not the empty MediaItem.image.
                    let thumbImage = await generateThumbnail(url: finalVideoURL)
                        ?? currentMediaState[index].media?.image
                    if let thumbImage, thumbImage.size.width > 0 {
                        DiskMediaManager.shared.saveImageToDisk(thumbImage, fileName: id, pathName: .STATUS)
                    }
                    let st = await StoryToSend(
                        id: id,
                        userId: CurrentSessionInfo.shared.currentUid,
                        type: .video,
                        content: finalVideoURL.absoluteString,
                        caption: currentMediaState[index].captionText,
                        PHMedia: media?.PHMedia,
                        thumbnail: thumbImage.flatMap { imageToDataURL($0) },
                        userName: CurrentSessionInfo.shared.userName,
                        userImage: nil,
                        fileSize: getFileSizeAsync(url: finalVideoURL)
                    )
                    myStatus.append(st)

                    if index == loadedMedia.count - 1 {
                        #if DEBUG
                        print("Finished: last was a VIDEO. Total = \(myStatus)")
                        #endif
                        for status in myStatus {
                            await statusStore.addOwnStatus(story:status)
                        }
                        dismiss()
                        withAnimation{
                            statusStore.isFirstPageStory = true
                        }
                    }
                } else {
                    #if DEBUG
                    print("🔥Export failed at index \(index)")
                    #endif
                }
            }
        }
    }
    func getFileSizeAsync(asset: PHAsset? = nil,url:URL? = nil) async -> Int {
        await withCheckedContinuation { continuation in
            viewModel.getFileSize(asset: asset,url: url) { sizeInBytes in
                continuation.resume(returning: Int(sizeInBytes ?? 0))
            }
        }
    }

    func prepareLoadedMedia(from mediaList: [GalleryMedia]) async -> (
        loadedMedia: [MediaItem],
        mediaInfoList: [MediaInfo],
        firstMediaInfo: MediaInfo?
    ) {

        var newLoadedMedia: [MediaItem] = []
        newLoadedMedia.reserveCapacity(mediaList.count)

        for media in mediaList {

            // --- Safe URL parsing ---
            let url: URL? = {
                if let u = media.uri, let parsed = URL(string: u) {
                    return parsed
                }
                return nil
            }()

            switch media.type {

            case .image:
                let img = media.highQualityImage ?? UIImage()
                let fileSize = await getFileSizeAsync(asset: media.asset)
                let item = MediaItem(image: img, type: .image, PHMedia: media,fileSize: fileSize)
                newLoadedMedia.append(item)

            case .video:
                guard let url = url else { continue }

                let videoObj = videoItem(url: url, pHAsset: media.asset)
                let fileSize = await getFileSizeAsync(asset: media.asset)
                // Video files are not UIImages — pull a real frame for editor + StoryToSend.thumbnail.
                let uiImage = await generateThumbnail(url: url) ?? UIImage()
                let item = MediaItem(
                    image: uiImage,
                    video: videoObj,
                    type: .video,
                    PHMedia: media,
                    fileSize: fileSize
                )
                newLoadedMedia.append(item)
                
                // Pre-generate video thumbnails so they are ready when the editor opens
                let phAsset = media.asset
                await VideoPlayerController.preGenerateThumbnails(for: phAsset, cacheStore: statusStore.videoTrimCache)
                
            }
        }

        // Build MediaInfo list
        let mediaInfoList: [MediaInfo] = newLoadedMedia.map { el in
            MediaInfo(
                media: el,
                originalMedia: el,
                imageFilter: .none,
                overLayText: "",
                captionText: "",
                selectedTextColor: .black,
                selectedFontIndex: 0,
                lines: [],
                drawSelectedColor: .green,
                selectedLineWidth: 5,
                textScale: 1.0,
                lastScale: 1.0,
                textOffset: .zero,
                lastOffset: .zero,
                textPosition: .zero
            )
        }

        return (newLoadedMedia, mediaInfoList, mediaInfoList.first)
    }

    private func appendSelectedGalleryMedia(_ items: [GalleryMedia]) {
        isAddingMedia = false
        viewModel.resetSelectedMedia()

        Task {
            let result = await prepareLoadedMedia(from: items)
            await MainActor.run {
                loadedMedia.append(contentsOf: result.loadedMedia)
                currentMediaState.append(contentsOf: result.mediaInfoList)
            }
        }
    }

    @ViewBuilder
    private func statusEditorMediaPage(at index: Int, geo: GeometryProxy) -> some View {
        switch loadedMedia[index]?.type {
        case .image:
            VStack {
                FilteredImageView(
                    path: loadedMedia[index]?.image,
                    filter: currentInfo.imageFilter,
                    currentInfo: $currentInfo,
                    addTextOnImage: $addTextOnImage,
                    fontSize: $fontSize,
                    isDraging: $isDraging,
                    isInDeleteZone: $isInDeleteTextZone,
                    geo: geo,
                    translationService: translationService
                )
                .tag(index)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black)

        case .video:
            if let pHAsset = loadedMedia[index]?.PHMedia?.asset {
                ZStack {
                    VideoTrimmerView(
                        storieVM: statusStore,
                        pHAsset: pHAsset,
                        fromServer: false,
                        hideTrimmer: self.drawOnImage,
                        currentPlayer: self.$currentPlayer,
                        onTrim: { (start, end) in
                            self.currentInfo.media?.video?.startTime = start
                            self.currentInfo.media?.video?.endTime = end
                            self.startTime = start
                            self.endTime = end
                        },
                        translationService: translationService
                    )
                    .padding(.vertical, 70)
                    .tag(index)
                    .allowsHitTesting(!self.drawOnImage && !self.addTextOnImage)

                    Canvas { context, size in
                        for line in currentInfo.lines {
                            var path = Path()
                            path.addLines(line.points)
                            context.stroke(
                                path,
                                with: .color(line.color),
                                lineWidth: line.lineWidth
                            )
                        }

                        if let currentLine = currentInfo.currentLine {
                            var path = Path()
                            path.addLines(currentLine.points)
                            context.stroke(
                                path,
                                with: .color(currentLine.color),
                                lineWidth: currentLine.lineWidth
                            )
                        }
                    }
                    .allowsHitTesting(false)
                    .zIndex(4)

                    if isDraging {
                        StoryTextDeleteZone(isActive: isInDeleteTextZone)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(.leading, StoryTextDeleteZoneMetrics.paddingLeading)
                            .padding(.top, StoryTextDeleteZoneMetrics.paddingTop)
                            .zIndex(6)
                    }

                    TextOverlayView(
                        currentInfoBinding: currentInfoBinding,
                        addTextOnImage: $addTextOnImage,
                        selectedTextColor: $currentInfo.selectedTextColor,
                        selectedFontIndex: $currentInfo.selectedFontIndex,
                        fontSize: $fontSize,
                        isDraging: $isDraging,
                        isInDeleteZone: $isInDeleteTextZone,
                        geo: geo
                    )
                    .zIndex(isDraging ? 20 : 5)
                }
                .zIndex(3)
                .compositingGroup()
            } else {
                Color.black
                    .overlay(
                        Text(t(ChatTranslationKeys.GALLERY_VIDEO_UNAVAILABLE))
                            .foregroundColor(.white)
                    )
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.black)
            }

        case nil, .some(.none):
            Color.black
                .overlay(
                    Text(t(ChatTranslationKeys.STORIES_NO_MEDIA))
                        .foregroundColor(.white)
                )
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.black)
        }
    }

    @ViewBuilder
    private func statusEditorTabView(geo: GeometryProxy) -> some View {
        if #available(iOS 17.0, *) {
            TabView(selection: $currentIndex) {
                ForEach(loadedMedia.indices, id: \.self) { index in
                    statusEditorMediaPage(at: index, geo: geo)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(.black)
            .transition(.move(edge: .bottom))
            .onAppear {
                self.rect = geo.frame(in: .global)
            }
            .onChange(of: currentIndex) {
                withAnimation(.easeInOut) {
                    if loadedMedia.indices.contains(currentIndex) {
                        let media = loadedMedia[currentIndex]
                        if currentInfo.media?.image != media?.image {
                            if let idxToUpdate = currentMediaState.firstIndex(where: { $0.media?.image == currentInfo.media?.image }) {
                                currentMediaState[idxToUpdate] = currentInfo
                            }
                            if let idx = currentMediaState.firstIndex(where: { $0.media?.image == media?.image }) {
                                currentInfo = currentMediaState[idx]
                            }
                            if currentInfo.media?.type == .video {
                                currentPlayer.play()
                            }
                        }
                    }
                }

                let curr: MediaInfo = currentMediaState[currentIndex]
                self.startTime = curr.media?.video?.startTime ?? 0
                self.endTime = curr.media?.video?.endTime ?? 0
            }
            .compositingGroup()
            .allowsHitTesting(true)
        }
    }

    var body: some View {
       
            GeometryReader { geo in
             
                ZStack(alignment: .topLeading) {
                    if #available(iOS 16.0, *) {
                        Spacer().toolbar(statusStore.isFirstPageStory ? .visible : .hidden,for: .tabBar)
                    } else {
                        // Fallback on earlier versions
                    }
                    // Background image or error message
                    statusEditorTabView(geo: geo)
                    
                    // Top control bar
                    HStack {
                        Image(systemName: "xmark")
                            .resizable()
                            .scaledToFit()
                            .frame(height: 24)
                            .foregroundColor(.white)
                            .padding()
                            .onTapGesture {
                                dismiss()
                                withAnimation{
                                    statusStore.isFirstPageStory = true
                                }
//                                self.saveImage(lines: currentInfo.lines)
//                                print("want to return")
                               
                                //                            withAnimation{
                                //                                storyVM.isStatusEditorOpen = false
                                //                            }
                                
                            }
                        
                        Spacer()
                        
                        HStack(spacing: 24) {
                            if currentInfo.media?.type != .video {
                                Image(systemName: "rotate.right")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(height: 24)
                                    .foregroundColor(.white)
                                    .onTapGesture {
                                        withAnimation{
                                            showFullScreen = true
                                        }
                                        
                                    }
                            }
                            
                            Text(t(ChatTranslationKeys.STORIES_AA))
                                .font(.title3)
                                .bold()
                                .foregroundColor(.white)
                                .onTapGesture {
                                    withAnimation(.easeInOut){
                                        addTextOnImage = true
                                        currentPlayer.pause()
                                    }
                                    
                                }
                            
                            Image(systemName: "pencil")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                                .foregroundColor(.white)
                                .onTapGesture {
                                    withAnimation(.easeInOut){
                                        drawOnImage = true
                                        currentPlayer.pause()
                                    }
                                }
                        }
                        .padding()
                    }.padding(.horizontal,3).zIndex(2).offset(y: showFilterView  || addTextOnImage || drawOnImage || isDraging ? -200 : 0)
                    HStack {
                        if #available(iOS 16.0, *) {
                            Text(t(ChatTranslationKeys.STORIES_DONE))
                                .font(.title3)
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(24)
                                .bold()
                                .foregroundColor(.primary)
                            
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        showFilterView = false
                                    }
                                    //                        dismiss()
                                }
                        } else {
                            // Fallback on earlier versions
                            Text(t(ChatTranslationKeys.STORIES_DONE))
                                .font(.title3)
                                .padding(8)
                                .background(Color(.systemBackground))
                                .cornerRadius(24)
                                .foregroundColor(.primary)
                            
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        showFilterView = false
                                    }
                                    //                        dismiss()
                                }
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 24) {
                            
                            
                            
                            
                            Image(systemName: "pencil")
                                .resizable()
                                .scaledToFit()
                                .frame(height: 24)
                                .foregroundColor(.white)
                                .onTapGesture {
                                    withAnimation(.easeInOut(duration: 0.5)) {
                                        drawOnImage = true
                                        showFilterView = false
                                    }
                                }
                            
                        }
                        .padding()
                    }.padding(.horizontal,3).zIndex(2).offset(y: showFilterView  ? 0 : -200)
                    
                    if addTextOnImage {
                        TextOnImage(
                            addTextOnImage: $addTextOnImage,
                            text: overlayTextBinding,
                            selectedFontIndex: $currentInfo.selectedFontIndex,
                            fontSize: $fontSize,
                            currentPlayer: $currentPlayer,
                            currentInfo: $currentInfo,
                            selectedTextColor: $currentInfo.selectedTextColor,
                            translationService: translationService
                        )
                        .zIndex(10)
                    }
                    if drawOnImage {
                        DrawingView(
                            lines: $currentInfo.lines,
                            currentLine: $currentInfo.currentLine,
                            selectedColor: $currentInfo.drawSelectedColor,
                            drawOnImage: $drawOnImage,
                            currentPlayer: $currentPlayer,
                            selectedLineWidth: $currentInfo.selectedLineWidth,
                            currentInfo: $currentInfo,
                            imageRect: fittedImageRect(forImageSize:self.currentInfo.imageOriginalSize ?? self.rect.size , inFrameSize: self.rect.size),
                            translationService: translationService
                        )
                        .zIndex(10)
                    }
                    ZStack{
                        VStack{
                            Spacer()
                                .allowsHitTesting(false)
                            HStack {
                                VStack(spacing:0){
                                    // 🟢 Input field row
                                    HStack {
                                        HStack(alignment: .bottom, spacing: 3) {
                                            VStack {
                                                Image(systemName: "plus.square.on.square")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(height: 20)
                                                    .foregroundColor(.white).onTapGesture {
                                                        withAnimation{
                                                            isAddingMedia = true
                                                        }
                                                    }
                                            }.frame( maxHeight: 50)
                                            
                                            ResizableTextEditor(
                                                text: captionTextBinding,
                                                height: self.$height,
                                                textColor: .white,
                                                placeholder: t(ChatTranslationKeys.STORIES_FILE_ADD_CAPTION),
                                                placeholderColor: .white
                                            )
                                                .frame(height: self.height < 150  ? self.height : 150).foregroundStyle(.white)
                                            
                                            VStack {
                                                Text("@")
                                                    .font(.title.bold())
                                                    .frame(width: 40, height: 40)
                                                    .background(mentionedText.isEmpty ? .black : .white)
                                                    .cornerRadius(50)
                                                
                                                    .foregroundColor(mentionedText.isEmpty ? .white : .black).onTapGesture {
                                                        withAnimation{
                                                            showMentionPicker = true
                                                        }
                                                    }
                                            }.frame(maxHeight: 50)
                                        }
                                        .padding(.horizontal, 12)
                                        .frame(maxWidth: .infinity, minHeight: 50)
                                        
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 25)
                                                .stroke(Color.white.opacity(0.3), lineWidth: 2)
                                        ) .background(Color.black).cornerRadius(25)
                                    }.padding(.horizontal,12)
                                    
                                    // 🟢 Status row
                                    HStack(spacing: 8) {
                                        HStack{
                                            Image(systemName: "scope")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 20)
                                                .foregroundColor(.white)
                                            
                                            Text(t(ChatTranslationKeys.STORIES_STATUS_PRIVACY))
                                                .font(.headline)
                                                .foregroundColor(.white)
                                        }.padding(8).background(.white.opacity(0.2)).cornerRadius(16)
                                            .onTapGesture {
                                                withAnimation{
                                                    showStatusPrivacy = true
                                                }
                                                
                                            }
                                        
                                        
                                        Spacer()
                                        Button(action:{
//                                            if self.currentInfo.media?.type == .image {
//                                                       let backgroundView = FilteredImageView(
//                                                    path: loadedMedia[currentIndex]?.image,
//                                                    filter: currentInfo.imageFilter,
//                                                    hideCanvas : true,
//                                                    currentInfo: $currentInfo,
//                                                    addTextOnImage: $addTextOnImage,
//                                                    fontSize: $fontSize,
//                                                    isDraging: $isDraging,
//                                                    geo: geo
//                                                    
//                                                )
//
//                                                let backgroundImage = backgroundView.asUIImage(size: rect.size)
//                                                print("image original size \(backgroundImage.size)")
//                                                saveImage(lines: currentInfo.lines, background: backgroundImage)
//                                            }else{
                                            onPublishStatus(geo: geo)
//                                            }
                                        
                                        }){
                                            Image(systemName: "paperplane.fill")
                                                .resizable()
                                                .scaledToFit()
                                                .frame(height: 20)
                                                .padding(8)
                                                .background(AppColors.primary)
                                                .clipShape(Circle())
                                                .foregroundColor(.white)
//                                                .onTapGesture {
//                                                    print("📤 Post status tapped")
//                                                }

                                        }
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(maxWidth: .infinity, minHeight: 50)
                                    .background(Color.black.opacity(0.5))
                                }
                            }
                        }.offset(y: showFilterView || drawOnImage || isDraging ? 200 : 0)
                            .zIndex(1)
//
                        
                        
                        GeometryReader { geometry in
                            VStack(spacing: 0) {
                                if showFilterView {
                                    Color.clear
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            hideKeyboard()
                                            withAnimation(.easeInOut(duration: 0.5)) {
                                                showFilterView = false
                                            }
                                        }
                                } else {
                                    Spacer(minLength: 0)
                                        .allowsHitTesting(false)
                                }

                                VStack(spacing: 4) {
                                    if !showFilterView {
                                        if self.currentInfo.media?.type != .video {
                                            VStack(spacing: 4) {
                                                Image(systemName: "chevron.up")
                                                    .resizable()
                                                    .scaledToFit()
                                                    .frame(height: 8)
                                                    .foregroundStyle(.white)
                                                    .offset(y: animateArrow ? -6 : 0)
                                                    .animation(
                                                        .easeInOut(duration: 0.8)
                                                        .repeatForever(autoreverses: true),
                                                        value: animateArrow
                                                    )

                                                Text(t(ChatTranslationKeys.STORIES_SWIPE_UP_FILTER))
                                                    .font(Font.custom("Avenir Next", size: 14))
                                                    .foregroundStyle(.white)
                                            }
                                            .gesture(
                                                DragGesture(minimumDistance: 30)
                                                    .onEnded { value in
                                                        if abs(value.translation.width) < abs(value.translation.height),
                                                           value.translation.height < -30 {
                                                            withAnimation(.easeInOut(duration: 0.5)) {
                                                                showFilterView = true
                                                            }
                                                        }
                                                    }
                                            )
                                        }
                                        Spacer().frame(height: 50)
                                        if loadedMedia.count > 1 {
                                            HStack {
                                                
                                                ScrollView(.horizontal, showsIndicators: false) {
                                                    HStack(spacing: 8) {
                                                        ForEach(loadedMedia.indices, id: \.self) { index in
                                                            ZStack {
                                                                // 🗑️ Trash button
                                                                if currentIndex == index {
                                                                    Image(systemName: "trash")
                                                                        .resizable()
                                                                        .scaledToFit()
                                                                        .frame(height: 42)
                                                                        .foregroundStyle(.white)
                                                                        .zIndex(1)
                                                                        .contentShape(Rectangle())
                                                                        .onTapGesture {
                                                                        
                                                                            let image = loadedMedia[index]?.image
                                                                            loadedMedia.remove(at: index)
                                                                            
                                                                            
                                                                            currentMediaState.removeAll(where: {$0.media?.image == image})
                                                                            // TODO: implement remove logic
                                                                        }
                                                                }
                                                                
                                                                // 🖼️ Image or placeholder
                                                                Group {
                                                                    if let uiImage = loadedMedia[index]?.image {
                                                                        Image(uiImage: uiImage)
                                                                            .resizable()
                                                                            .scaledToFill()
                                                                            .frame(width: 70, height: 70)
                                                                            .clipped()
                                                                    } else {
                                                                        Image(systemName: "photo")
                                                                            .resizable()
                                                                            .scaledToFit()
                                                                            .frame(width: 24, height: 24)
                                                                            .foregroundColor(.white)
                                                                            .frame(width: 70, height: 70)
                                                                    }
                                                                }
                                                                .allowsHitTesting(currentIndex != index)
                                                            }
                                                            .frame(width: 70, height: 70)
                                                            .contentShape(Rectangle())
                                                            .onTapGesture {
                                                                
                                                                guard currentIndex != index else { return }
                                                                
                                                                // Ensure array is properly sized before accessing
                                                                if currentMediaState.count < loadedMedia.count {
                                                                    currentMediaState = Array(repeating: currentInfo, count: loadedMedia.count)
                                                                }
                                                                
                                                                // Save previous state
                                                                if currentIndex < currentMediaState.count {
                                                                    currentMediaState[currentIndex] = currentInfo
                                                                }
                                                                
                                                                // Load new state
                                                                currentInfo = currentMediaState[index]
                                                                withAnimation{
                                                                    currentIndex = index
                                                                }
                                                              
                                                                
                                                                
                                                                //                                                            withAnimation(.easeInOut) {
                                                                
                                                                currentInfo.media = loadedMedia[index]
                                                                //                                                            }
                                                            }
                                                            .overlay(
                                                                RoundedRectangle(cornerRadius: 12)
                                                                    .stroke(Color.white, lineWidth: currentIndex == index ? 8 : 0)
                                                            )
                                                            .cornerRadius(12)
                                                            //                                                        .onAppear {
                                                            //                                                            if loadedImages[selectedImages[index]] == nil,
                                                            //                                                               let url = getSelectedFileURL(from: selectedImages[index]) {
                                                            //                                                                loadImage(from: url, for: selectedImages[index])
                                                            //                                                            }
                                                            //                                                        }
                                                        }
                                                        
                                                        
                                                    }
                                                }
                                                .frame(width: loadedMedia.count > 5 ? .infinity :  CGFloat(75 * loadedMedia.count))
                                            }
                                            //                                        .frame(maxWidth: .infinity, alignment: .center)
                                        }
                                        
                                        
                                    }
                                }
                                .offset(y: drawOnImage ? geo.size.height : 0)

                                if showFilterView {
                                    FilterView(selectedFilter: $currentInfo.imageFilter, image: currentInfo.media?.image ?? UIImage())
                                        .frame(height: 200)
                                        .transition(.move(edge: .bottom).combined(with: .opacity))
                                }

                                Spacer()
                                    .frame(height: showFilterView ? 0 : geometry.size.height * 0.1)
                                    .allowsHitTesting(false)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                            .zIndex(2)
                            .onAppear {
                                animateArrow = true
                            }
                            .ignoresSafeArea(.keyboard)
                        }
                    }.offset(y: addTextOnImage || drawOnImage || isDraging ? 300 : 0).zIndex(1)
                    
                }.chatAppearanceFullScreenCover(isPresented: $showGeneratedImage){
                    VStack{
                        Image(uiImage: genImageUI).resizable().scaledToFit().frame(maxWidth:.infinity)
                    }.background(.red.opacity(0.2))
                }
                .onAppear{
                    Task {
                        let result = await prepareLoadedMedia(from: statusStore.selectedMedia)

                        await MainActor.run {
                            loadedMedia = result.loadedMedia
                            currentMediaState = result.mediaInfoList

                            if let first = result.firstMediaInfo {
                                currentInfo.media = first.media
                                currentInfo.originalMedia = first.media
                                currentInfo.textOffset = .zero
                                currentInfo.lastOffset = .zero
                            }

                        }
                    }

                }
                
//                .onAppear {
//
//                    print("editor states", statusStore.selectedMedia.count,"first size ",statusStore.selectedMedia.first?.size,"the first one ",statusStore.selectedMedia.first)
//
//                    Task {
//                        
//                        var newLoadedMedia: [MediaItem] = []
//                        newLoadedMedia.reserveCapacity(statusStore.selectedMedia.count)
//
//                        for media in statusStore.selectedMedia {
//
//                            // --- SAFETY: check media.uri parsing ---
//                            let url: URL? = {
//                                if let u = media.uri, let parsed = URL(string: u) {
//                                    return parsed
//                                } else {
//                                    return nil
//                                }
//                            }()
//    
//                            // --- Ordered switch ---
//                            switch media.type {
//
//                            case .image:
//                                // Safe unwrap for image
//                                let img = media.highQualityImage ?? UIImage()
//                                let item = MediaItem(image: img, type: .image,PHMedia: media)
//                                newLoadedMedia.append(item)
//                                print("Loaded media : Image",item)
//
//                            case .video:
//                                guard let url = url else {
//                                    print("⚠️ Skipping video: invalid URL")
//                                    continue
//                                }
//
//                                // Sequential ordered generation
//                                let thumbnail = await generateThumbnail(url: url)
//                                let videoObj = videoItem(url: url)
//
//                                let item = MediaItem(
//                                    image: thumbnail ?? UIImage(),
//                                    video: videoObj,
//                                    type: .video,
//                                    PHMedia: media
//                                )
//
//                                newLoadedMedia.append(item)
//                            }
//                        }
//
//                        // UI update
//                        await MainActor.run {
//                            loadedMedia = newLoadedMedia
//                            print("✅ Loaded media:", loadedMedia.count, "new media ",newLoadedMedia.count)
//                        }
//
//                        // Create MediaInfo array
//                        if !newLoadedMedia.isEmpty {
//                            currentMediaState = newLoadedMedia.map { el in
//                                MediaInfo(
//                                    media: el,
//                                    originalMedia: el,
//                                    imageFilter: .none,
//                                    overLayText: "",
//                                    captionText: "",
//                                    selectedTextColor: .black,
//                                    selectedFontIndex: 0,
//                                    lines: [],
//                                    drawSelectedColor: .green,
//                                    selectedLineWidth: 5,
//                                    textScale: 1.0,
//                                    lastScale: 1.0,
//                                    textOffset: .zero,
//                                    lastOffset: .zero,
//                                    textPosition: .zero
//                                )
//                            }
//
//                            currentInfo.media = newLoadedMedia.first!
//                            currentInfo.originalMedia = newLoadedMedia.first!
//                            currentInfo.textOffset = .zero
//                            currentInfo.lastOffset = .zero
//                        }
//                    }
//                }
                .chatAppearanceFullScreenCover(isPresented: $showFullScreen, onDismiss: {
                    if currentMediaState.indices.contains(currentIndex) {
                        currentMediaState[currentIndex] = currentInfo
                    }
                }) {
                    PhotoCropEditor(showFullScreen:$showFullScreen,currentInfo: $currentInfo,loadedMedia:$loadedMedia,currentIndex : $currentIndex)
                }
                .overlay(
                    Group {
                        if isExporting {
                            ZStack {
                                Color.black.opacity(0.6)
                                    .ignoresSafeArea()
                                VStack(spacing: 0) {
//                                    Spacer().frame(height: 10)
                                    AnimatedSpinner(StrokeColor: .white, lineWidth: 5, size: 20)
//                                    ProgressView()
//                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
//                                        .scaleEffect(1.5)
                                    
                                    Text(t(ChatTranslationKeys.STORIES_PROCESSING_POST))
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(exportProgress < 1 ? [] : .vertical, 20)
                                    if exportProgress > 0 && exportProgress < 1 {
                                        Spacer().frame(height: 10)
                                        ProgressView(value: exportProgress)
                                            .progressViewStyle(LinearProgressViewStyle(tint: .white))
                                            .frame(width: 200)
                                        Spacer().frame(height: 20)
                                    }
                                    
                                }
                                .padding(.horizontal,30)
                                .background(Color.black.opacity(0.8))
                                .cornerRadius(16)
                            }
                            .zIndex(9999)
                        }
                    }
                )
                
            }
           
                .chatAppearanceSheet(isPresented: $isAddingMedia, onDismiss: {
                    viewModel.resetSelectedMedia()
                    
                }){
                    if #available(iOS 16.0, *) {
                        GalleryView(
                            viewModel: viewModel,
                            translationService: translationService,
                            selectingEnded: appendSelectedGalleryMedia,
                            onDirectSelect: { media in
                                appendSelectedGalleryMedia([media])
                            }
                        )
                        .presentationDragIndicator(.visible)
                        .presentationDetents([.medium, .large])
                    } else {
                        // Fallback on earlier versions
                        GalleryView(
                            viewModel: viewModel,
                            translationService: translationService,
                            selectingEnded: appendSelectedGalleryMedia,
                            onDirectSelect: { media in
                                appendSelectedGalleryMedia([media])
                            }
                        )
                    }
                }
            .chatAppearanceSheet(isPresented: $showStatusPrivacy) {
                if #available(iOS 16.0, *) {
                    StatusPrivacyView(translationService: translationService).presentationDragIndicator(.visible).presentationDetents([.medium])
                } else {
                    // Fallback on earlier versions
                    StatusPrivacyView(translationService: translationService)
                }
            }
            .chatAppearanceSheet(isPresented: $showMentionPicker) {
                if #available(iOS 16.0, *) {
                    MentionPickerView(isPresented: $showMentionPicker, onSelect: { item in
                        switch item {
                        case .contact(let contact):
                            mentionedText += "@\(contact.name) "
                        case .group(let group):
                            mentionedText += "@\(group.name) "
                        }
                    }, translationService: translationService)
                    .presentationDetents([.medium, .large])
                } else {
                    // Fallback on earlier versions
                    MentionPickerView(isPresented: $showMentionPicker, onSelect: { item in
                        switch item {
                        case .contact(let contact):
                            mentionedText += "@\(contact.name) "
                        case .group(let group):
                            mentionedText += "@\(group.name) "
                        }
                    }, translationService: translationService)
                }
            }
        
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

struct TextOnImage : View {
    @Binding var addTextOnImage : Bool
//   @Binding var image : UIImage?
    @Binding var text: String
    @Binding var  selectedFontIndex : Int
    @Binding var fontSize: CGFloat
    @Binding var currentPlayer: AVPlayer
    @Binding var currentInfo: MediaInfo
    @State private var textHeight: CGFloat = 40
    @State private var textWidth: CGFloat = 0
    @State private var openColorSelector: Bool = false
    @State private var openTextStyleSelector: Bool = false
 
    @State private var isAtLimit : Bool = false
    @Binding var selectedTextColor: Color   // NEW
    let translationService: (any TranslationServiceProtocol)?

    init(
        addTextOnImage: Binding<Bool>,
        text: Binding<String>,
        selectedFontIndex: Binding<Int>,
        fontSize: Binding<CGFloat>,
        currentPlayer: Binding<AVPlayer>,
        currentInfo: Binding<MediaInfo>,
        selectedTextColor: Binding<Color>,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self._addTextOnImage = addTextOnImage
        self._text = text
        self._selectedFontIndex = selectedFontIndex
        self._fontSize = fontSize
        self._currentPlayer = currentPlayer
        self._currentInfo = currentInfo
        self._selectedTextColor = selectedTextColor
        self.translationService = translationService
    }

    let MyColors: [Color] = [
                .white,
                Color(red: 1.0, green: 0.9, blue: 0.7),  // Cream
                Color(red: 1.0, green: 0.8, blue: 0.5),  // Light Orange
                Color(red: 1.0, green: 0.6, blue: 0.2),  // Orange
                Color(red: 1.0, green: 0.3, blue: 0.3),  // Red-Orange
                Color(red: 0.9, green: 0.2, blue: 0.4),  // Red
                Color(red: 0.8, green: 0.2, blue: 0.6),  // Pink
                Color(red: 0.6, green: 0.3, blue: 0.8),  // Purple
                Color(red: 0.3, green: 0.4, blue: 0.9),  // Blue
                Color(red: 0.2, green: 0.7, blue: 0.9),  // Light Blue
                Color(red: 0.2, green: 0.8, blue: 0.6),  // Cyan
                Color(red: 0.3, green: 0.8, blue: 0.3),  // Green
                Color(red: 0.6, green: 0.8, blue: 0.2),  // Yellow-Green
                Color(red: 1.0, green: 0.9, blue: 0.2),  // Yellow
                Color(red: 0.6, green: 0.4, blue: 0.2),  // Brown
                Color(red: 0.4, green: 0.4, blue: 0.4),  // Gray
                .black
            ]
       
//       private let fontData = FontData.shared
    private let myFont = ConstantFont.shared.AllFonts
    private let colors = ConstantColors.customColors

    
  
    let screenWidth = UIScreen.main.bounds.width
    @State private var inputWidth: CGFloat = 0
    var body: some View {
        ZStack {
           
            VStack(alignment: /*@START_MENU_TOKEN@*/.center/*@END_MENU_TOKEN@*/) {
               HStack {
                   if #available(iOS 16.0, *) {
                       Text(t(ChatTranslationKeys.STORIES_DONE))
                           .font(.title3)
                           .padding(8)
                           .background(Color(.systemBackground))
                           .cornerRadius(24)
                           .bold()
                           .foregroundColor(.primary)
                       
                           .onTapGesture {
                               withAnimation(.easeInOut(duration: 0.5)) {
                                   addTextOnImage = false
                                   if currentInfo.media?.type == .video {
                                       self.currentPlayer.play()
                                   }
                                   
                               }
                           }
                   } else {
                       Text(t(ChatTranslationKeys.STORIES_DONE))
                           .font(.title3)
                           .padding(8)
                           .background(Color(.systemBackground))
                           .cornerRadius(24)
                           .foregroundColor(.primary)
                       
                           .onTapGesture {
                               withAnimation(.easeInOut(duration: 0.5)) {
                                   addTextOnImage = false
                                   if currentInfo.media?.type == .video {
                                       self.currentPlayer.play()
                                   }
                                   
                               }
                           }

                   }
                
                Spacer()
                
                HStack(spacing: 24) {
                    Image(systemName: "pencil")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                        .foregroundColor(.white)
                }
                .padding()
            }.padding(.horizontal,3).zIndex(2)
                
                Spacer()
                ZStack {
                    if !text.isEmpty {
                        // Compute background near the selected color
                        let bg = adjustedBackground(forTextColor: selectedTextColor)
                        // Enforce exact rule: black text => white background, white text => black background
                        let normalizedBG = normalizeBackgroundForEdges(bg, forTextColor: selectedTextColor)
                        // Choose the best visible text (white on dark bg, black on light bg)
                        let visibleTextColor = readableTextColor(forBackground: normalizedBG)
                        
                        Text(text)
                            .multilineTextAlignment(.center)
//                            .font(fontData.getFont(for: selectedFontIndex, size: fontSize))
                            .font(.applyFontCustom(myFont[selectedFontIndex],size: fontSize))
                            .foregroundStyle(visibleTextColor)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                normalizedBG
                                    .cornerRadius(8)
                            )
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.horizontal, 50)
                            .frame(maxWidth: .infinity, alignment: .center)}
                
                    PerfectCenteredTextEditor(
                        text: $text,
                        CurrentFontStyle: .applyFontCustom(myFont[selectedFontIndex], size: fontSize),
                        fontSize: $fontSize,
                        isAtLimit: $isAtLimit,
                        textColor: selectedTextColor,
                        translationService: translationService,
                        placeholder: t(ChatTranslationKeys.STORIES_TYPE_HERE)
                    )
                        .opacity(text.isEmpty ? 1 : 0)
                    
                    Spacer()
                 
                }
            }.navigationBarBackButtonHidden(true)
            VStack{
                Spacer()
                    FontStylePickerBar(selectedIndex: $selectedFontIndex)
            } .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      
            // NEW: Right-side vertical color bar
            VStack {
               
                RightColorBar(colors: colors, selectedColor: $selectedTextColor)
                    .padding(.top, 70)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            .ignoresSafeArea(.keyboard)
        }.background(.black.opacity(0.3)).zIndex(3)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

// MARK: - Background color that stays near selectedTextColor but keeps contrast
private func adjustedBackground(forTextColor textColor: Color) -> Color {
    // Try to find a nearby shade that achieves at least this contrast.
    let targetContrast: CGFloat = 4.5
    
    // Convert to HSB for intuitive adjustments
    var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
    textColor.toHSBA(&h, &s, &b, &a)
    
    // Heuristic: if text is bright, go darker; if dark, go lighter
    let goDarkerFirst = textColor.relativeLuminance() > 0.5
    
    // Small steps to keep “nearby”
    let step: CGFloat = 0.06
    let maxSteps = 12
    
    func colorFrom(h: CGFloat, s: CGFloat, b: CGFloat, a: CGFloat) -> Color {
        Color(hue: h, saturation: s, brightness: b, opacity: 1.0) // ensure opaque
    }
    
    
    // Try primary direction
    for i in 1...maxSteps {
        let delta = CGFloat(i) * step
        let newB = goDarkerFirst ? max(0, b - delta) : min(1, b + delta)
        let candidate = colorFrom(h: h, s: s, b: newB, a: 1.0)
        if candidate.contrastRatio(against: textColor) >= targetContrast {
            return candidate
        }
    }
    
    // Try opposite direction if not enough
    for i in 1...maxSteps {
        let delta = CGFloat(i) * step
        let newB = goDarkerFirst ? min(1, b + delta) : max(0, b - delta)
        let candidate = colorFrom(h: h, s: s, b: newB, a: 1.0)
        if candidate.contrastRatio(against: textColor) >= targetContrast {
            return candidate
        }
    }
    
    // Last resort: tweak saturation slightly
    let reducedS = max(0, s - 0.2)
    return colorFrom(h: h, s: reducedS, b: goDarkerFirst ? max(0, b - 0.2) : min(1, b + 0.2), a: 1.0)
}

// Enforce exact rule for pure black/white text choices
private func normalizeBackgroundForEdges(_ bg: Color, forTextColor textColor: Color) -> Color {
    // If text is exactly black or very close → background must be white
    if textColor.isNearlyBlack {
        return .white
    }
    // If text is exactly white or very close → background must be black
    if textColor.isNearlyWhite {
        return .black
    }
    return bg
}

// Decide the most readable text color on a given background (white on dark, black on light)
private func readableTextColor(forBackground bg: Color) -> Color {
    bg.relativeLuminance() > 0.5 ? .black : .white
}

// NEW: Slim vertical color picker similar to WhatsApp’s
struct RightColorBar: View {
    let colors: [Color]
    @Binding var selectedColor: Color
    
    var body: some View {
        VStack(spacing: 0) {
            // Top arrow/indicator
            Image(systemName: "chevron.up")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(height: 20)
            
            // Color gradient bar
            ZStack(alignment: .leading) {
                // Background gradient
                LinearGradient(
                    gradient: Gradient(colors: colors),
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(width: 8)
                .clipShape(Capsule())
                
                // Selection indicator
                Circle()
                    .fill(Color.white)
                    .frame(width: 20, height: 20)
                    .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
                    .overlay(
                        Circle()
                            .fill(selectedColor)
                            .frame(width: 16, height: 16)
                    )
                    .offset(x: -6, y: getIndicatorOffset())
            }
            .frame(height: 200)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        updateColorFromPosition(value.location.y)
                    }
            )
            .padding(.vertical, 8)
            
            // Bottom arrow/indicator
            Image(systemName: "chevron.down")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))
                .frame(height: 20)
        }
        .frame(width: 44)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 22)
                .fill(Color.black.opacity(0.4))
                .background(
                    RoundedRectangle(cornerRadius: 22)
                        .fill(.ultraThinMaterial)
                        .opacity(0.8)
                )
        )
    }
    
    private func getIndicatorOffset() -> CGFloat {
        guard let index = colors.firstIndex(of: selectedColor) else {
            return 0
        }
        let totalHeight: CGFloat = 200
        let segmentHeight = totalHeight / CGFloat(colors.count - 1)
        return CGFloat(index) * segmentHeight - (totalHeight / 2)
    }
    
    private func updateColorFromPosition(_ yPosition: CGFloat) {
        let totalHeight: CGFloat = 200
        let clampedY = max(0, min(yPosition, totalHeight))
        let percentage = clampedY / totalHeight
        let index = Int(percentage * CGFloat(colors.count - 1))
        let clampedIndex = max(0, min(index, colors.count - 1))
        
        withAnimation(.easeOut(duration: 0.1)) {
            selectedColor = colors[clampedIndex]
        }
    }
}
struct FilterView: View {
    @Binding var selectedFilter: ImageFilterType
    let image: UIImage
    
    let filters: [ImageFilterType] = [.none, .vivid, .warm, .cool, .bw, .pop]
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 16) {
                    ForEach(filters, id: \.self) { filter in
                        FilterThumbnailView(
                            filter: filter,
                            image: image,
                            isSelected: selectedFilter == filter
                        )
                        .onTapGesture {
                            withAnimation(.easeInOut) {
                                selectedFilter = filter
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
    }
}

struct FilterThumbnailView: View {
    let filter: ImageFilterType
    let image: UIImage
    let isSelected: Bool
    
    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Image(uiImage: applyFilterToThumbnail(image, filter: filter))
                    .resizable()
                    .scaledToFill()
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(isSelected ? Color.green : Color.clear, lineWidth: 3)
                    )
            }
            
            Text(filter.name)
                .font(.caption)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .green : .white)
        }
    }
    
    func applyFilterToThumbnail(_ image: UIImage, filter: ImageFilterType) -> UIImage {
        guard filter != .none,
              let ciImage = CIImage(image: image) else {
            return image
        }
        
        let context = CIContext()
        var outputImage: CIImage?
        
        switch filter {
        case .none:
            return image
        case .vivid:
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(1.3, forKey: kCIInputSaturationKey)
                filter.setValue(0.1, forKey: kCIInputBrightnessKey)
                outputImage = filter.outputImage
            }
        case .warm:
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                filter.setValue(CIVector(x: 8000, y: 0), forKey: "inputTargetNeutral")
                outputImage = filter.outputImage
            }
        case .cool:
            if let filter = CIFilter(name: "CITemperatureAndTint") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(CIVector(x: 6500, y: 0), forKey: "inputNeutral")
                filter.setValue(CIVector(x: 5000, y: 0), forKey: "inputTargetNeutral")
                outputImage = filter.outputImage
            }
        case .bw:
            if let filter = CIFilter(name: "CIPhotoEffectMono") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                outputImage = filter.outputImage
            }
        case .pop:
            if let filter = CIFilter(name: "CIColorControls") {
                filter.setValue(ciImage, forKey: kCIInputImageKey)
                filter.setValue(1.5, forKey: kCIInputSaturationKey)
                filter.setValue(0.2, forKey: kCIInputContrastKey)
                outputImage = filter.outputImage
            }
        }
        
        guard let output = outputImage,
              let cgImage = context.createCGImage(output, from: output.extent) else {
            return image
        }
        
        return UIImage(cgImage: cgImage)
    }
}




// MARK: - Filtered Image View

struct FilteredImageView: View {
//    let path: String
    var path: UIImage? = nil
    var filter: ImageFilterType = .none
    var hideCanvas : Bool = false
   
    @Binding var currentInfo: MediaInfo
    @Binding var addTextOnImage: Bool
//    @Binding var selectedTextColor: Color
//    @Binding var selectedFontIndex: Int
    @Binding var fontSize: CGFloat
    @Binding var isDraging : Bool
    var isInDeleteZone: Binding<Bool>? = nil
    var geo : GeometryProxy
    let translationService: (any TranslationServiceProtocol)?

    init(
        path: UIImage? = nil,
        filter: ImageFilterType = .none,
        hideCanvas: Bool = false,
        currentInfo: Binding<MediaInfo>,
        addTextOnImage: Binding<Bool>,
        fontSize: Binding<CGFloat>,
        isDraging: Binding<Bool>,
        isInDeleteZone: Binding<Bool>? = nil,
        geo: GeometryProxy,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.path = path
        self.filter = filter
        self.hideCanvas = hideCanvas
        self._currentInfo = currentInfo
        self._addTextOnImage = addTextOnImage
        self._fontSize = fontSize
        self._isDraging = isDraging
        self.isInDeleteZone = isInDeleteZone
        self.geo = geo
        self.translationService = translationService
    }
    
    @State private var uiImage: UIImage? = nil
    @State private var isLoading = false
    @State private var imageRenderingSize : CGSize = .zero
    
    // Helper binding to simplify access
    private var currentInfoBinding: Binding<MediaInfo> { $currentInfo }

    private var resolvedImage: UIImage? {
        if let session = currentInfo.cropSession,
           let original = currentInfo.originalMedia?.image,
           geo.size.width > 0,
           let preview = MediaCropRenderer.previewImage(
               source: original,
               session: session,
               containerSize: geo.size
           ) {
            return preview
        }
        return path
    }
    
    var body: some View {
//        GeometryReader { geo in
            
            ZStack {
                // Image or placeholder
                Group {
                    if let image = resolvedImage {
                        Image(uiImage: applyFilter(to: image, filter: filter))
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
//                            .frame(
//                             width: imageRenderingSize.width,
//                             height: imageRenderingSize.height
//                         )
                            .background(Color.black)
                            .onAppear {
                                      let containerSize = geo.size
                                      let imageSize = image.size

                                      let scale = min(
                                          containerSize.width / imageSize.width,
                                          containerSize.height / imageSize.height
                                      )

                                      let renderedWidth  = imageSize.width * scale
                                      let renderedHeight = imageSize.height * scale

                                      currentInfo.imageOriginalSize = imageSize
                                imageRenderingSize = CGSize(
                                    width: renderedWidth,
                                    height: renderedHeight
                                )
                                      currentInfo.imageRenderedSize = imageRenderingSize
                                    

                                      
                                  }
                    } else if isLoading {
                        ProgressView(common("loading"))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    } else {
                        Text(t(ChatTranslationKeys.STORIES_NO_IMAGE))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.black)
                    }
                }
                .ignoresSafeArea()
                if !self.hideCanvas {
                    Canvas { context, size in
                                       for line in currentInfo.lines {
                                           var path = Path()
                                           path.addLines(line.points)
                                           context.stroke(
                                               path,
                                               with: .color(line.color),
                                               lineWidth: line.lineWidth
                                           )
                                       }
                                       
                                       if let currentLine = currentInfo.currentLine {
                                           var path = Path()
                                           path.addLines(currentLine.points)
                                           context.stroke(
                                               path,
                                               with: .color(currentLine.color),
                                               lineWidth: currentLine.lineWidth
                                           )
                                       }
                                   }.frame(
                                    width: imageRenderingSize.width,
                                    height: imageRenderingSize.height
                                )
                }
               
                if isDraging {
                    StoryTextDeleteZone(isActive: isInDeleteZone?.wrappedValue ?? false)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.leading, StoryTextDeleteZoneMetrics.paddingLeading)
                        .padding(.top, StoryTextDeleteZoneMetrics.paddingTop)
                        .zIndex(6)
                }

                // Text overlay
                TextOverlayView(
                    currentInfoBinding: currentInfoBinding,
                    addTextOnImage: $addTextOnImage,
                    selectedTextColor: $currentInfo.selectedTextColor,
                    selectedFontIndex: $currentInfo.selectedFontIndex,
                    fontSize: $fontSize,
                    isDraging : $isDraging,
                    isInDeleteZone: isInDeleteZone,
                    geo: geo
                )
                .zIndex(isDraging ? 20 : 4)
                
                
            }
//            .frame(width:imageRenderingSize.width  ,height: imageRenderingSize.height )
//            .frame(width: imageRenderingSize.width, height: imageRenderingSize.height).background(.red)
//        }
    }
    
//    func loadImage() {
//        isLoading = true
//        Task {
//            if let image = await loadUIImage(from: path) {
//                await MainActor.run {
//                    uiImage = image
//                    isLoading = false
//                }
//            } else {
//                await MainActor.run {
//                    isLoading = false
//                }
//            }
//        }
//    }
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

struct TextOverlayView: View {
    @Binding var currentInfoBinding: MediaInfo
    @Binding var addTextOnImage: Bool
    @Binding var selectedTextColor: Color
    @Binding var selectedFontIndex: Int
    @Binding var fontSize: CGFloat
//    var fontData = FontData.shared
    var fontData = ConstantFont.shared.AllFonts
    @Binding var isDraging : Bool
    var isInDeleteZone: Binding<Bool>? = nil
    var geo : GeometryProxy
    
    var body: some View {
        if !currentInfoBinding.overLayText.isEmpty && !addTextOnImage {
            let bg = adjustedBackground(forTextColor: selectedTextColor)
            let normalizedBG = normalizeBackgroundForEdges(bg, forTextColor: selectedTextColor)
            let visibleTextColor = readableTextColor(forBackground: normalizedBG)
            
          
                Text(currentInfoBinding.overLayText)
                    .multilineTextAlignment(.center)
//                    .font(fontData.getFont(for: selectedFontIndex, size: fontSize))
                    .font(.applyFontCustom(fontData[selectedFontIndex],size: fontSize))
                    .foregroundStyle(visibleTextColor)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(normalizedBG.cornerRadius(8))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 50)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .scaleEffect(currentInfoBinding.textScale)
                    .offset(currentInfoBinding.textOffset)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                currentInfoBinding.textOffset = CGSize(
                                    width: currentInfoBinding.lastOffset.width + value.translation.width,
                                    height: currentInfoBinding.lastOffset.height + value.translation.height
                                )
                                let pos = textCenter(for: currentInfoBinding.textOffset)
                                let inDeleteZone = StoryTextDeleteZoneMetrics.contains(pos)
                                if isInDeleteZone?.wrappedValue != inDeleteZone {
                                    isInDeleteZone?.wrappedValue = inDeleteZone
                                }
                                withAnimation(.easeInOut(duration: 0.3)) {
                                    currentInfoBinding.textPosition = pos
                                    isDraging = true
                                }
                            }
                            .onEnded { _ in
                                let center = textCenter(for: currentInfoBinding.textOffset)
                                let mediaRect = fittedMediaRect()
                                let inDeleteZone = StoryTextDeleteZoneMetrics.contains(center)

                                withAnimation(.easeInOut(duration: 0.3)) {
                                    isDraging = false
                                    isInDeleteZone?.wrappedValue = false

                                    if inDeleteZone {
                                        currentInfoBinding.overLayText = ""
                                        currentInfoBinding.lastOffset = .zero
                                        currentInfoBinding.textOffset = .zero
                                        currentInfoBinding.textScale = 1.0
                                        currentInfoBinding.lastScale = 1.0
                                        currentInfoBinding.selectedTextColor = .black
                                        currentInfoBinding.textPosition = .zero
                                    } else if isOutsideMediaBounds(center: center, mediaRect: mediaRect) {
                                        currentInfoBinding.textOffset = currentInfoBinding.lastOffset
                                        currentInfoBinding.textPosition = textCenter(for: currentInfoBinding.lastOffset)
                                    } else {
                                        currentInfoBinding.lastOffset = currentInfoBinding.textOffset
                                        currentInfoBinding.textPosition = center
                                    }
                                }
                            }
                            .simultaneously(with:
                                                MagnificationGesture()
                                .onChanged { value in
                                    currentInfoBinding.textScale = currentInfoBinding.lastScale * value
                                }
                                .onEnded { _ in
                                    currentInfoBinding.lastScale = currentInfoBinding.textScale
                                }
                                           )
                            .simultaneously(with:
                                                TapGesture()
                                .onEnded {
                                    withAnimation(.easeInOut) {
                                        addTextOnImage = true
                                    }
                                }
                                           )
                    )
                    .zIndex(isDraging ? 20 : 4)
                    .compositingGroup()
                    .allowsHitTesting(true)
        }
    }

    private func textCenter(for offset: CGSize) -> CGPoint {
        CGPoint(
            x: geo.size.width / 2 + offset.width,
            y: geo.size.height / 2 + offset.height
        )
    }

    private func isInDeleteZone(_ position: CGPoint) -> Bool {
        StoryTextDeleteZoneMetrics.contains(position)
    }

    private func fittedMediaRect() -> CGRect {
        let frameSize = geo.size
        let imageSize: CGSize
        if currentInfoBinding.imageRenderedSize != .zero {
            imageSize = currentInfoBinding.imageRenderedSize
        } else if let original = currentInfoBinding.imageOriginalSize, original.width > 0, original.height > 0 {
            imageSize = original
        } else if let image = currentInfoBinding.media?.image {
            imageSize = image.size
        } else {
            return CGRect(origin: .zero, size: frameSize)
        }

        let imageAspect = imageSize.width / imageSize.height
        let frameAspect = frameSize.width / frameSize.height
        let drawSize: CGSize
        if imageAspect > frameAspect {
            drawSize = CGSize(width: frameSize.width, height: frameSize.width / imageAspect)
        } else {
            drawSize = CGSize(width: frameSize.height * imageAspect, height: frameSize.height)
        }
        let origin = CGPoint(
            x: (frameSize.width - drawSize.width) / 2,
            y: (frameSize.height - drawSize.height) / 2
        )
        return CGRect(origin: origin, size: drawSize)
    }

    private func isOutsideMediaBounds(center: CGPoint, mediaRect: CGRect) -> Bool {
        !mediaRect.contains(center)
    }
}




// MARK: - Color utilities for contrast and HSBA extraction
private extension Color {
    // Convert to RGBA components (sRGB)
    func toRGBA(_ r: inout CGFloat, _ g: inout CGFloat, _ b: inout CGFloat, _ a: inout CGFloat) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var rr: CGFloat = 0, gg: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getRed(&rr, green: &gg, blue: &bb, alpha: &aa)
        r = rr; g = gg; b = bb; a = aa
        #else
        r = 0; g = 0; b = 0; a = 1
        #endif
    }
    
    // Convert to HSBA for intuitive brightness tweaks
    func toHSBA(_ h: inout CGFloat, _ s: inout CGFloat, _ b: inout CGFloat, _ a: inout CGFloat) {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var hh: CGFloat = 0, ss: CGFloat = 0, bb: CGFloat = 0, aa: CGFloat = 0
        ui.getHue(&hh, saturation: &ss, brightness: &bb, alpha: &aa)
        h = hh; s = ss; b = bb; a = aa
        #else
        h = 0; s = 0; b = 0; a = 1
        #endif
    }
    
    // WCAG relative luminance
    func relativeLuminance() -> CGFloat {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        toRGBA(&r, &g, &b, &a)
        func lin(_ c: CGFloat) -> CGFloat {
            return c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        let rl = 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
        return rl
    }
    
    // WCAG contrast ratio between two colors
    func contrastRatio(against other: Color) -> CGFloat {
        let l1 = self.relativeLuminance()
        let l2 = other.relativeLuminance()
        let lighter = max(l1, l2)
        let darker = min(l1, l2)
        return (lighter + 0.05) / (darker + 0.05)
    }
    
    // Helpers to detect near black/white (tolerant for non-ideal sRGB)
    var isNearlyBlack: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        toRGBA(&r, &g, &b, &a)
        return r < 0.1 && g < 0.1 && b < 0.1
    }
    var isNearlyWhite: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        toRGBA(&r, &g, &b, &a)
        return r > 0.9 && g > 0.9 && b > 0.9
    }
}
extension View {
    func asUIImage(size: CGSize) -> UIImage {
        let controller = UIHostingController(rootView: self)
        controller.view.bounds = CGRect(origin: .zero, size: size)
        controller.view.backgroundColor = .clear

        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            controller.view.drawHierarchy(in: controller.view.bounds, afterScreenUpdates: true)
        }
    }
}


extension UIImage {
    
    func croppingBlackBorders(
        tolerance: UInt8 = 30,
        padding: CGFloat = 10,
        targetSize: CGSize,
        backgroundColor: UIColor = .black
    ) -> UIImage? {
        
        guard let cgImage = self.cgImage else { return nil }
        
        let width = cgImage.width
        let height = cgImage.height
        guard width > 0, height > 0 else { return nil }
        
        // MARK: - Bitmap context
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        guard let data = ctx.data else { return nil }
        let pixels = data.bindMemory(to: UInt8.self, capacity: height * bytesPerRow)
        
        // MARK: - Detect non-black bounds
        var minX = width, minY = height, maxX = 0, maxY = 0
        
        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let r = pixels[offset]
                let g = pixels[offset + 1]
                let b = pixels[offset + 2]
                
                if r > tolerance || g > tolerance || b > tolerance {
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }
        
        // If no content found, return original
        guard minX < maxX, minY < maxY else { return self }
        
        // MARK: - Apply padding
        let pad = Int(padding * scale)
        let cropX = max(minX - pad, 0)
        let cropY = max(minY - pad, 0)
        let cropW = min(maxX - minX + 1 + pad * 2, width - cropX)
        let cropH = min(maxY - minY + 1 + pad * 2, height - cropY)
        
        guard let cropped = cgImage.cropping(to: CGRect(x: cropX, y: cropY, width: cropW, height: cropH)) else { return nil }
        
        // MARK: - Center crop to target aspect ratio
        let srcAspect = CGFloat(cropped.width) / CGFloat(cropped.height)
        let targetAspect = targetSize.width / targetSize.height
        
        let finalCrop: CGRect
        if srcAspect > targetAspect {
            // Too wide → crop sides
            let newWidth = CGFloat(cropped.height) * targetAspect
            let xOffset = (CGFloat(cropped.width) - newWidth) / 2
            finalCrop = CGRect(x: xOffset, y: 0, width: newWidth, height: CGFloat(cropped.height))
        } else {
            // Too tall → crop top/bottom
            let newHeight = CGFloat(cropped.width) / targetAspect
            let yOffset = (CGFloat(cropped.height) - newHeight) / 2
            finalCrop = CGRect(x: 0, y: yOffset, width: CGFloat(cropped.width), height: newHeight)
        }
        
        guard let aspectCropped = cropped.cropping(to: finalCrop) else { return nil }
        
        // MARK: - Resize to target size
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            backgroundColor.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            UIImage(cgImage: aspectCropped, scale: 1, orientation: imageOrientation)
                .draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}

