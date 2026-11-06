import Foundation
import AVFoundation
import SwiftUI
import PhotosUI
import AVKit
import WaanguCoreKit

@available(iOS 16.0, *)
struct TrimmerTimeline: View {
    @StateObject var model: VideoPlayerController
    var phAsset: PHAsset?
    let translationService: (any TranslationServiceProtocol)? = nil
    // MARK: - Constants
    private let handleWidth: CGFloat = 12
    private let borderWidth: CGFloat = 3
    private let minTrimDuration: Double = 3.0
    var maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds
    private let cornerRadius: CGFloat = 8
    private let thumbnailHeight: CGFloat = 60
    var onTrim: ((Double, Double) -> Void)? = nil
//    @State private var trimDuration : Double = 0.0
    
    // MARK: - Drag state
    @State private var isInitialized = false
    @State private var dragStartValue: Double?
    @State private var dragEndValue: Double?
    @State private var dragBothStartValue: (start: Double, end: Double)?


    var body: some View {
        GeometryReader { geometry in
            let visibleWidth = geometry.size.width
            let totalWidth  = visibleWidth
            
            let timePerPixel = model.duration / Double(totalWidth)
            let trimX = CGFloat(model.startTime / timePerPixel)
            let trimWidth = CGFloat((model.endTime - model.startTime) / timePerPixel)
//            var  trimWidth = 150.0
        
            Color.clear.frame(width: 0,height:0).onChange(of: model.duration) { newDuration in
                guard visibleWidth > 0 else { return }
                let newTimePerPixel = newDuration / Double(visibleWidth)
                model.timePerPixel = newTimePerPixel
                // Max possible trim = min(maxTrimDuration, full video)
                let newEnd = min(maxTrimDuration, newDuration)
                let newStart = model.startTime < newEnd ? model.startTime : 0

                // Update model’s state (this will trigger UI recalculation)
                model.updateTrim(start: newStart, end: newEnd,phAsset: phAsset)
                let trimWidth1 = (newEnd - newStart) / newTimePerPixel
                model.trimDuration = trimWidth1 * newTimePerPixel
                onTrim?(newStart, newEnd)
            }.onChange(of: model.currentTime){ newCurrent in
                
//                print("current playing timeeeeee \(newCurrent)")
                
            }.onChange(of: model.trimProgress){ newCurrent in
                
//                print("current trim pos  \(newCurrent)")
                
            }
            // -----------------------------------------------------------------
            // Filmstrip + trim chrome — always interactive (WhatsApp-style).
            // Video plays immediately; thumbs fill the strip progressively.
            // -----------------------------------------------------------------
            ZStack(alignment: .leading) {
                let availableWidth = visibleWidth
                let expectedCount = max(model.thumbnails.count, 2)
                let thumbWidth = max(CGFloat(50), availableWidth / CGFloat(max(expectedCount, 2)))

                // Placeholder bar while thumbs arrive
                Rectangle()
                    .fill(Color.gray.opacity(0.35))
                    .frame(width: availableWidth, height: thumbnailHeight)

                HStack(spacing: 0) {
                    if model.thumbnails.isEmpty {
                        // Subtle shimmer-like empty strip (non-blocking)
                        ForEach(0..<8, id: \.self) { _ in
                            Rectangle()
                                .fill(Color.white.opacity(0.08))
                                .frame(width: availableWidth / 8, height: thumbnailHeight)
                        }
                    } else {
                        ForEach(Array(model.thumbnails.enumerated()), id: \.offset) { _, uiImage in
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: max(thumbWidth, availableWidth / CGFloat(model.thumbnails.count)), height: thumbnailHeight)
                                .clipped()
                        }
                    }
                }
                .frame(width: availableWidth, height: thumbnailHeight)
                .clipped()
                .animation(.easeOut(duration: 0.15), value: model.thumbnails.count)

                // ---- DARK OVERLAY (left of trim) ----------------------------
                if trimX > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: trimX, height: thumbnailHeight)
                        .allowsHitTesting(false)
                }

                // ---- DARK OVERLAY (right of trim) ---------------------------
                let rightOverlayStart = trimX + trimWidth
                if rightOverlayStart < visibleWidth {
                    Rectangle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: visibleWidth - rightOverlayStart, height: thumbnailHeight)
                        .position(x: rightOverlayStart + (visibleWidth - rightOverlayStart) / 2,
                                  y: thumbnailHeight / 2)
                        .allowsHitTesting(false)
                }

                // ---- TRIM BORDER --------------------------------------------
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white, lineWidth: 2)
                    .frame(width: max(trimWidth, 1), height: thumbnailHeight)
                    .position(x: trimX + max(trimWidth, 1) / 2, y: thumbnailHeight / 2)
                    .allowsHitTesting(false)

                // ---- CENTER DRAG AREA ---------------------------------------
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: max(0, trimWidth - handleWidth * 2), height: thumbnailHeight)
                    .position(x: trimX + trimWidth / 2, y: thumbnailHeight / 2)
                    .contentShape(Rectangle())
                    .gesture(centerDragGesture(timePerPixel: timePerPixel))
                    .zIndex(1)

                // ---- LEFT HANDLE --------------------------------------------
                handleView
                    .position(x: trimX, y: thumbnailHeight / 2)
                    .gesture(leftHandleGesture(timePerPixel: timePerPixel))
                    .zIndex(2)

                // ---- RIGHT HANDLE -------------------------------------------
                handleView
                    .position(x: trimX + trimWidth, y: thumbnailHeight / 2)
                    .gesture(rightHandleGesture(timePerPixel: timePerPixel))
                    .zIndex(2)

                Spacer().frame(width: 5, height: thumbnailHeight).background(.white)
                    .position(x: model.trimProgress, y: thumbnailHeight / 2)
            }
            .frame(width: visibleWidth, height: thumbnailHeight)
            .clipped()
            .animation(.easeInOut(duration: 0.1), value: model.startTime)
            .animation(.easeInOut(duration: 0.1), value: model.endTime)
        }
        .frame(height: thumbnailHeight)
        .background(Color.black)
        .cornerRadius(cornerRadius)
        .onAppear {
            guard !isInitialized else { return }
            isInitialized = true
            
            // Initial trim = maxTrimDuration (or full video if shorter)
            let initialEnd = min(maxTrimDuration, model.duration > 0 ? model.duration : maxTrimDuration)
            model.updateTrim(start: 0, end: initialEnd,phAsset: phAsset)
            model.trimDuration = initialEnd
            onTrim?(0, initialEnd)
        }
    }
    
    // MARK: - Handle View
    private var handleView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color.white)
                .frame(width: handleWidth, height: thumbnailHeight)
                .shadow(radius: 1)
            Capsule()
                .fill(Color.gray)
                .frame(width: 2, height: 16)
        }
        .contentShape(Rectangle())
    }
    
    // MARK: - Gestures
    private func leftHandleGesture(timePerPixel: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragStartValue == nil {
                    dragStartValue = model.startTime
                    model.dragMode = .left
                }
                guard let initial = dragStartValue else { return }

                let delta = Double(value.translation.width) * timePerPixel
                var newStart = initial + delta
                var newEnd = model.endTime

                // --- Clamp new start within bounds ---
                newStart = max(0, newStart)
                newStart = min(model.endTime - minTrimDuration, newStart)

                // --- If exceeds max trim width, shift window instead ---
                if newEnd - newStart > maxTrimDuration {
                    // Calculate overflow beyond max
                    let overflow = (newEnd - newStart) - maxTrimDuration
                    // Move both ends to the left by overflow
                    newEnd -= overflow
                    newStart = newEnd - maxTrimDuration
                }

                // --- Prevent overflow beyond start ---
                if newStart < 0 {
                    let shift = -newStart
                    newStart = 0
                    newEnd += shift
                    if newEnd > model.duration {
                        newEnd = model.duration
                    }
                }

                model.startTime = newStart
                model.endTime = newEnd
                let trimWidth = (newEnd - newStart) / timePerPixel
                model.trimDuration = trimWidth * timePerPixel
            }
            .onEnded { _ in
                dragStartValue = nil
                model.dragMode = nil
                model.updateTrim(start: model.startTime, end: model.endTime,fromTrimimg: true,phAsset: phAsset)
                onTrim?(model.startTime,model.endTime)
                debugLog("stop left")
            }
    }

    private func rightHandleGesture(timePerPixel: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragEndValue == nil {
                    dragEndValue = model.endTime
                    model.dragMode = .right
                }
                guard let initial = dragEndValue else { return }

                let delta = Double(value.translation.width) * timePerPixel
                var newEnd = initial + delta
                var newStart = model.startTime

                // --- Clamp new end within bounds ---
                newEnd = max(model.startTime + minTrimDuration, newEnd)
                newEnd = min(model.duration, newEnd)

                // --- If exceeds max trim width, shift window instead ---
                if newEnd - newStart > maxTrimDuration {
                    // Calculate overflow beyond max
                    let overflow = (newEnd - newStart) - maxTrimDuration
                    // Move both ends to the right by overflow
                    newStart += overflow
                    newEnd = newStart + maxTrimDuration
                }

                // --- Prevent overflow beyond video end ---
                if newEnd > model.duration {
                    let overflow = newEnd - model.duration
                    newEnd = model.duration
                    newStart -= overflow
                    if newStart < 0 {
                        newStart = 0
                    }
                }

                model.startTime = newStart
                model.endTime = newEnd
                let trimWidth = (newEnd - newStart) / timePerPixel
                model.trimDuration = trimWidth * timePerPixel
            }
            .onEnded { _ in
                dragEndValue = nil
                model.dragMode = nil
                model.updateTrim(start: model.startTime, end: model.endTime,fromTrimimg: true,phAsset: phAsset)
                onTrim?(model.startTime,model.endTime)
                debugLog("stop right")
            }
    }

    
    private func centerDragGesture(timePerPixel: Double) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if dragBothStartValue == nil {
                    dragBothStartValue = (model.startTime, model.endTime)
                    model.dragMode = .center
                }
                guard let initial = dragBothStartValue else { return }

                let delta = Double(value.translation.width) * timePerPixel
                var newStart = initial.0 + delta
                var newEnd = initial.1 + delta

                if newStart < 0 {
                    newEnd -= newStart
                    newStart = 0
                }
                if newEnd > model.duration {
                    let overflow = newEnd - model.duration
                    newStart -= overflow
                    newEnd = model.duration
                }

                model.startTime = newStart
                model.endTime = newEnd
            }
            .onEnded { _ in
                dragBothStartValue = nil
                model.dragMode = nil
                model.updateTrim(start: model.startTime, end: model.endTime,fromTrimimg: true,phAsset: phAsset)
                onTrim?(model.startTime,model.endTime)
            }
    }
    
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
    
}
@available(iOS 16.0, *)
struct VideoTrimmerView: View {
    @StateObject private var model: VideoPlayerController
    let pHAsset: PHAsset?
    let videoURL: URL?
    var autoPlay: Bool = false
    var fromServer: Bool = false
    var hideTrimmer: Bool = false
    var showsEstimatedSendSize: Bool = false
    var useHD: Bool = false
    var maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds
    @Binding var currentPlayer: AVPlayer
    var onTrim: ((Double, Double) -> Void)? = nil
    let translationService: (any TranslationServiceProtocol)?

    init(
        cacheStore: VideoTrimCacheStore,
        pHAsset: PHAsset? = nil,
        videoURL: URL? = nil,
        autoPlay: Bool = false,
        fromServer: Bool = false,
        hideTrimmer: Bool = false,
        showsEstimatedSendSize: Bool = false,
        useHD: Bool = false,
        maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds,
        currentPlayer: Binding<AVPlayer>,
        onTrim: ((Double, Double) -> Void)? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _model = StateObject(wrappedValue: VideoPlayerController(
            cacheStore: cacheStore,
            clearCache: false,
            maxTrimDuration: maxTrimDuration
        ))
        self.pHAsset = pHAsset
        self.videoURL = videoURL
        self.autoPlay = autoPlay
        self.fromServer = fromServer
        self.hideTrimmer = hideTrimmer
        self.showsEstimatedSendSize = showsEstimatedSendSize
        self.useHD = useHD
        self.maxTrimDuration = maxTrimDuration
        _currentPlayer = currentPlayer
        self.onTrim = onTrim
        self.translationService = translationService
    }

    init(
        storieVM: StoriesViewModel,
        pHAsset: PHAsset,
        autoPlay: Bool = false,
        fromServer: Bool = false,
        hideTrimmer: Bool = false,
        maxTrimDuration: Double = StatusVideoTrimPolicy.maxDurationSeconds,
        currentPlayer: Binding<AVPlayer>,
        onTrim: ((Double, Double) -> Void)? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.init(
            cacheStore: storieVM.videoTrimCache,
            pHAsset: pHAsset,
            autoPlay: autoPlay,
            fromServer: fromServer,
            hideTrimmer: hideTrimmer,
            maxTrimDuration: maxTrimDuration,
            currentPlayer: currentPlayer,
            onTrim: onTrim,
            translationService: translationService
        )
    }
    var body: some View {
        ZStack (alignment:.topLeading){
            Color.black
//            if let player = model.player {
//                VideoPlayer(player: player)
//                    .frame(maxWidth: .infinity,maxHeight: .infinity)
//                    .clipped()
//                    .onAppear { player.play() }
//                    .onDisappear { player.pause() }
            ZStack {
            
                CustomVideoPlayer(
                    url: videoURL,
                    phAsset: pHAsset,
                    isPHAsset: pHAsset != nil,
                    autoPlay: self.autoPlay,
                    fromServer: fromServer,
                    contentMode: .fill,
                    loaderColor: .white,
                    OnStartPlaying: { _ in
                        self.currentPlayer = self.model.player ?? AVPlayer()
                    },
                    OnReadyPlaying: {
                        self.currentPlayer = self.model.player ?? AVPlayer()
                    },
                    controller: model,
                ).frame(width: UIScreen.main.bounds.width)
                Color.black.opacity(0.01)
//                                .ignoresSafeArea()
                                .onTapGesture {
                                    if !model.isLoading {
                                        if model.showOverlay  {
                                            withAnimation{
                                                model.timer?.invalidate()
                                                model.showOverlay = false
                                            }
                                        }else{
                                            
                                            if model.isPlaying{
                                                model.player?.pause()
                                            }else{
                                                model.player?.play()
                                            }
                                            model.startCountdown()
                                        }
                                    }
                                  
                                 
                                }
                if model.showOverlay {
                    VStack{
                        
                        Image(systemName:model.isPlaying ? "pause.fill" : "play.fill").resizable().scaledToFit().foregroundStyle(.white).frame(width: 50, height: 50).padding().cornerRadius(50).onTapGesture {
                            model.startCountdown()
                                         if model.isPlaying {
                                             model.player?.pause()
                                         }else{
                                             model.player?.play()
                                         }
                                     }
                                 }
                }
             
                
            }.frame(maxWidth: .infinity,maxHeight: .infinity)
            
//            } else {
//                VStack {
//                    ProgressView("Loading video...").foregroundStyle(.white)
//
//                } .frame(maxWidth: .infinity,maxHeight: .infinity)
//            }
            if !hideTrimmer {
                VStack {
                    TrimmerTimeline(
                        model: model,
                        phAsset: pHAsset,
                        maxTrimDuration: maxTrimDuration,
                        onTrim: onTrim
                    )
                        .padding(.horizontal)
                    Spacer().frame(height: 10)
                    HStack {
                        Text(formatTime(self.model.trimDuration))
                            .font(.headline)
                            .foregroundColor(.white).padding(10).background(.black.opacity(0.6)).cornerRadius(50)
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                model.player?.isMuted.toggle()
                            }
                        }) {
                            Image(systemName: model.player?.isMuted == true ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                .font(.system(size: 16))
                                .foregroundColor(.white)
                                .padding(10)
                                .background(.black.opacity(0.6))
                                .clipShape(Circle())
                                .shadow(radius: 3)
                        }
                        if showsEstimatedSendSize {
                            Text(ChatVideoSendSizeEstimator.formattedSize(
                                ChatVideoSendSizeEstimator.estimatedBytes(
                                    trimDuration: model.trimDuration,
                                    useHD: useHD
                                )
                            ))
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(.black.opacity(0.6))
                            .cornerRadius(50)
                        }
                        Spacer()
                    }
                    .padding(.horizontal,30)
                }

            }
       
        

//            Button("Export Trimmed Video") {
//                exportVideo()
//            }
//            .buttonStyle(.borderedProminent)
//            .disabled(model.isExporting)

            if model.isExporting {
                ProgressView("Exporting trimmed video...")
                    .progressViewStyle(.circular)
                    .padding()
            }
        }.frame(maxWidth: .infinity,maxHeight: .infinity).zIndex(3)
            .compositingGroup()
            .allowsHitTesting(true)
//        .task {
//            await model.loadVideo()
//        }
    }

    private func formatTime(_ seconds: Double) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        let ms = Int((seconds.truncatingRemainder(dividingBy: 1)) * 100)
//        return String(format: "%d:%02d.%02d", mins, secs, ms)
        return String(format: "%d:%02d", mins, secs)
    }

    private func exportVideo() {
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("trimmed_\(UUID().uuidString).mp4")
let cacheKey = ""
//        Task {
//            let success = await model.exportTrimmedVideo(to: outputURL,videoID: cacheKey)
//            if success {
//                print("Exported successfully: \(outputURL)")
//                // Optionally: Share or preview
//            } else {
//                print("Export failed")
//            }
//        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
