import SwiftUI
import UIKit

struct PhotoCropEditor: View {
    @StateObject private var viewModel = CropViewModel()
    @Binding var showFullScreen: Bool
    @Binding var currentInfo: MediaInfo
    @Binding var loadedMedia: [MediaItem?]
    @Binding var currentIndex: Int
    @State private var panStart: CGSize = .zero
    @State private var pinchStart: CGFloat = 1.0

    var body: some View {
        GeometryReader { _ in
            ZStack(alignment: .topLeading) {
                Color.black.ignoresSafeArea()

                VStack(alignment: .center, spacing: 0) {
                    topBar

                    Spacer()

                    GeometryReader { geo in
                        CropCanvasView(
                            cropRect: $viewModel.cropRect,
                            containerSize: geo.size,
                            viewModel: viewModel,
                            panStart: $panStart,
                            pinchStart: $pinchStart
                        )
                        .onAppear {
                            let original = currentInfo.originalMedia?.image ?? currentInfo.media?.image
                            viewModel.configure(
                                source: original,
                                session: currentInfo.cropSession,
                                containerSize: geo.size
                            )
                            panStart = viewModel.transform.panOffset
                            pinchStart = viewModel.transform.userZoomScale
                        }
                    }
                    .padding(.horizontal, 10)

                    bottomControls
                }
            }
        }
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            Button(action: {
                withAnimation {
                    showFullScreen = false
                }
            }) {
                Image(systemName: "xmark")
                    .resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.black.opacity(0.5))
            .cornerRadius(50)

            Spacer()

            if viewModel.hasChanges {
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        viewModel.resetAll()
                        currentInfo.cropSession = nil
                    }
                    panStart = .zero
                    pinchStart = 1.0
                }) {
                    Image(systemName: "arrow.counterclockwise")
                        .resizable().scaledToFit()
                        .frame(width: 24, height: 24)
                        .foregroundStyle(.white)
                }
                .padding()
                .background(.black.opacity(0.5))
                .cornerRadius(50)
            }

            Button(action: {
                guard let session = viewModel.exportSession(),
                      let preview = viewModel.applyCrop() else { return }

                withAnimation {
                    currentInfo.cropSession = session
                    currentInfo.media?.image = preview
                    loadedMedia[currentIndex]?.image = preview
                    showFullScreen = false
                }
            }) {
                Image(systemName: "checkmark")
                    .resizable().scaledToFit()
                    .frame(width: 24, height: 24)
                    .foregroundStyle(.white)
            }
            .padding()
            .background(.black.opacity(0.5))
            .cornerRadius(50)
            .disabled(!viewModel.canApplyCrop)
        }
        .padding(.horizontal, 30)
        .padding(.vertical, 10)
        .zIndex(999)
    }

    private var bottomControls: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    viewModel.rotateQuarterTurn()
                } label: {
                    Image(systemName: "rotate.right")
                        .font(.title2)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(Color.gray.opacity(0.3))
                        .clipShape(Circle())
                }
                .disabled(viewModel.isProcessing)

                Spacer()
            }
            .padding(.horizontal, 30)

            DraggableCompass(
                viewModel: viewModel,
                onBegin: {
                    viewModel.beginStraightening()
                },
                onChange: { degrees in
                    viewModel.updateFineAngle(degrees: degrees)
                },
                onDismiss: {
                    viewModel.finishStraightening()
                    pinchStart = viewModel.transform.userZoomScale
                },
                limit: 90
            )
        }
    }
}

// MARK: - Crop Canvas

/// Shared by the chat/stories crop shell and the standalone `ImageCropperView`.
struct CropCanvasView: View {
    @Binding var cropRect: CGRect
    let containerSize: CGSize
    @ObservedObject var viewModel: CropViewModel
    @Binding var panStart: CGSize
    @Binding var pinchStart: CGFloat
    var shape: CropWindowShape = .freeform

    var body: some View {
        ZStack {
            if let image = viewModel.sourceImage {
                CropMaskView(
                    cropRect: cropRect,
                    containerSize: containerSize,
                    isStraightening: viewModel.isStraightening,
                    shape: shape
                ) {
                    cropImage(image)
                }
                .gesture(imagePanGesture)
                .allowsHitTesting(!viewModel.isStraightening)

                DraggableCropOverlay(
                    cropRect: $cropRect,
                    containerSize: containerSize,
                    shape: shape,
                    onDismiss: {
                        pinchStart = viewModel.transform.userZoomScale
                    }
                )
            } else {
                ProgressView()
                    .tint(.white)
                    .scaleEffect(1.5)
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .clipped()
        .simultaneousGesture(imagePinchGesture)
    }

    @ViewBuilder
    private func cropImage(_ image: UIImage) -> some View {
        ZStack {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: viewModel.layoutRect.width, height: viewModel.layoutRect.height)
                .scaleEffect(viewModel.effectiveZoomScale)
                .rotationEffect(.degrees(viewModel.transform.totalAngleDegrees))
                .offset(viewModel.transform.panOffset)
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .animation(.easeInOut(duration: 0.15), value: viewModel.transform.fineAngleDegrees)
        .animation(.easeInOut(duration: 0.15), value: viewModel.effectiveZoomScale)
        .animation(.easeInOut(duration: 0.28), value: viewModel.transform.quarterTurns)
    }

    private var imagePanGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                viewModel.updatePanOffset(CGSize(
                    width: panStart.width + value.translation.width,
                    height: panStart.height + value.translation.height
                ))
            }
            .onEnded { _ in
                panStart = viewModel.transform.panOffset
            }
    }

    private var imagePinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let next = pinchStart * value
                viewModel.updateUserZoomScale(min(max(next, viewModel.minimumCoverScale), 5.0))
            }
            .onEnded { _ in
                pinchStart = viewModel.transform.userZoomScale
            }
    }
}

// MARK: - Draggable Crop Overlay

struct DraggableCropOverlay: View {
    @Binding var cropRect: CGRect
    let containerSize: CGSize
    var shape: CropWindowShape = .freeform
    @State private var isDraggingBox = false
    @State private var activeHandle: HandlePosition?
    @State private var initialCropRect: CGRect = .zero
    var onDismiss: (() -> Void)?

    let handleHitSize: CGFloat = 44
    let minCropSize: CGFloat = 80

    private var isInteracting: Bool {
        isDraggingBox || activeHandle != nil
    }

    private var bounds: CGRect {
        CGRect(origin: .zero, size: containerSize)
    }

    var body: some View {
        ZStack {
            cropOutline
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            if shape.showsGrid {
                CropGridView(cropRect: cropRect)
                    .opacity(isInteracting ? 0 : 1)
                    .animation(.easeInOut(duration: 0.15), value: isInteracting)
            }

            Rectangle()
                .fill(Color.clear)
                .contentShape(Rectangle())
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(
                    DragGesture()
                        .onChanged { value in
                            if !isDraggingBox {
                                withAnimation(.easeInOut) {
                                    initialCropRect = cropRect
                                    isDraggingBox = true
                                }
                            }

                            let newX = initialCropRect.origin.x + value.translation.width
                            let newY = initialCropRect.origin.y + value.translation.height

                            let clampedX = max(bounds.minX, min(newX, bounds.maxX - cropRect.width))
                            let clampedY = max(bounds.minY, min(newY, bounds.maxY - cropRect.height))

                            cropRect.origin = CGPoint(x: clampedX, y: clampedY)
                        }
                        .onEnded { _ in
                            withAnimation(.easeInOut) {
                                isDraggingBox = false
                                onDismiss?()
                            }
                        }
                )

            ForEach(HandlePosition.allCases, id: \.self) { position in
                CornerBracketHandle(corner: position)
                    .frame(width: handleHitSize, height: handleHitSize, alignment: bracketAlignment(for: position))
                    .contentShape(Rectangle())
                    .position(handlePosition(for: position))
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if activeHandle != position {
                                    initialCropRect = cropRect
                                    activeHandle = position
                                }
                                resizeCrop(handle: position, translation: value.translation)
                            }
                            .onEnded { _ in
                                activeHandle = nil
                                onDismiss?()
                            }
                    )
            }
        }
    }

    private var cropOutline: CropOutlineShape {
        CropOutlineShape(shape: shape)
    }

    private func bracketAlignment(for position: HandlePosition) -> Alignment {
        switch position {
        case .topLeft: return .topLeading
        case .topRight: return .topTrailing
        case .bottomLeft: return .bottomLeading
        case .bottomRight: return .bottomTrailing
        }
    }

    func handlePosition(for position: HandlePosition) -> CGPoint {
        let inset = handleHitSize / 2
        switch position {
        case .topLeft:
            return CGPoint(x: cropRect.minX + inset, y: cropRect.minY + inset)
        case .topRight:
            return CGPoint(x: cropRect.maxX - inset, y: cropRect.minY + inset)
        case .bottomLeft:
            return CGPoint(x: cropRect.minX + inset, y: cropRect.maxY - inset)
        case .bottomRight:
            return CGPoint(x: cropRect.maxX - inset, y: cropRect.maxY - inset)
        }
    }

    func resizeCrop(handle: HandlePosition, translation: CGSize) {
        guard bounds.width > 0, bounds.height > 0 else { return }

        if let ratio = shape.lockedAspectRatio {
            resizeCropLocked(handle: handle, translation: translation, ratio: ratio)
            return
        }

        var newRect = initialCropRect

        switch handle {
        case .topLeft:
            newRect.origin.x += translation.width
            newRect.origin.y += translation.height
            newRect.size.width -= translation.width
            newRect.size.height -= translation.height
        case .topRight:
            newRect.origin.y += translation.height
            newRect.size.width += translation.width
            newRect.size.height -= translation.height
        case .bottomLeft:
            newRect.origin.x += translation.width
            newRect.size.width -= translation.width
            newRect.size.height += translation.height
        case .bottomRight:
            newRect.size.width += translation.width
            newRect.size.height += translation.height
        }

        if newRect.width < minCropSize { newRect.size.width = minCropSize }
        if newRect.height < minCropSize { newRect.size.height = minCropSize }

        if newRect.minX < bounds.minX {
            newRect.origin.x = bounds.minX
        }
        if newRect.minY < bounds.minY {
            newRect.origin.y = bounds.minY
        }
        if newRect.maxX > bounds.maxX {
            newRect.size.width = bounds.maxX - newRect.origin.x
        }
        if newRect.maxY > bounds.maxY {
            newRect.size.height = bounds.maxY - newRect.origin.y
        }

        cropRect = newRect
    }

    /// Resizes about the corner opposite the one being dragged, so the anchored
    /// corner stays put while the window keeps its `ratio` (width ÷ height).
    ///
    /// Both drag axes feed one side length — otherwise a diagonal drag fights
    /// itself, with the horizontal component asking for a size the vertical one
    /// immediately overrides.
    private func resizeCropLocked(handle: HandlePosition, translation: CGSize, ratio: CGFloat) {
        guard ratio > 0 else { return }

        let growsRight = handle == .topRight || handle == .bottomRight
        let growsDown = handle == .bottomLeft || handle == .bottomRight

        let anchor = CGPoint(
            x: growsRight ? initialCropRect.minX : initialCropRect.maxX,
            y: growsDown ? initialCropRect.minY : initialCropRect.maxY
        )

        let widthFromDrag = initialCropRect.width + (growsRight ? translation.width : -translation.width)
        let heightFromDrag = initialCropRect.height + (growsDown ? translation.height : -translation.height)

        // The axis pulled furthest outward wins, which is what a diagonal drag
        // on a locked window is asking for.
        var side = max(widthFromDrag, heightFromDrag * ratio)

        let horizontalRoom = growsRight ? bounds.maxX - anchor.x : anchor.x - bounds.minX
        let verticalRoom = growsDown ? bounds.maxY - anchor.y : anchor.y - bounds.minY

        side = min(side, horizontalRoom)
        side = min(side, verticalRoom * ratio)
        side = max(side, minCropSize)

        // A container smaller than the floor would push the window out of
        // bounds; leave the rect alone rather than draw outside the image.
        guard side <= horizontalRoom, side / ratio <= verticalRoom else { return }

        let size = CGSize(width: side, height: side / ratio)
        cropRect = CGRect(
            origin: CGPoint(
                x: growsRight ? anchor.x : anchor.x - size.width,
                y: growsDown ? anchor.y : anchor.y - size.height
            ),
            size: size
        )
    }
}

// MARK: - Corner Handles

struct CornerBracketHandle: View {
    let corner: HandlePosition

    private let armLength: CGFloat = 20
    private let thickness: CGFloat = 2.5

    var body: some View {
        Canvas { context, size in
            var path = Path()

            switch corner {
            case .topLeft:
                path.addRect(CGRect(x: 0, y: 0, width: armLength, height: thickness))
                path.addRect(CGRect(x: 0, y: 0, width: thickness, height: armLength))
            case .topRight:
                path.addRect(CGRect(x: size.width - armLength, y: 0, width: armLength, height: thickness))
                path.addRect(CGRect(x: size.width - thickness, y: 0, width: thickness, height: armLength))
            case .bottomLeft:
                path.addRect(CGRect(x: 0, y: size.height - thickness, width: armLength, height: thickness))
                path.addRect(CGRect(x: 0, y: size.height - armLength, width: thickness, height: armLength))
            case .bottomRight:
                path.addRect(
                    CGRect(x: size.width - armLength, y: size.height - thickness, width: armLength, height: thickness)
                )
                path.addRect(
                    CGRect(x: size.width - thickness, y: size.height - armLength, width: thickness, height: armLength)
                )
            }

            context.fill(path, with: .color(.white))
        }
        .frame(width: armLength, height: armLength)
    }
}

enum HandlePosition: CaseIterable {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Traces the crop window itself, so the outline matches the hole the mask
/// punches instead of always being a rectangle.
struct CropOutlineShape: Shape {
    let shape: CropWindowShape

    func path(in rect: CGRect) -> Path {
        switch shape {
        case .freeform: return Path(rect)
        case .circle: return Path(ellipseIn: rect)
        }
    }
}

// MARK: - Grid Lines

struct CropGridView: View {
    let cropRect: CGRect

    var body: some View {
        Canvas { context, _ in
            var path = Path()

            let thirdWidth = cropRect.width / 3
            for i in 1...2 {
                let x = cropRect.minX + (thirdWidth * CGFloat(i))
                path.move(to: CGPoint(x: x, y: cropRect.minY))
                path.addLine(to: CGPoint(x: x, y: cropRect.maxY))
            }

            let thirdHeight = cropRect.height / 3
            for i in 1...2 {
                let y = cropRect.minY + (thirdHeight * CGFloat(i))
                path.move(to: CGPoint(x: cropRect.minX, y: y))
                path.addLine(to: CGPoint(x: cropRect.maxX, y: y))
            }

            context.stroke(path, with: .color(.white.opacity(0.35)), lineWidth: 0.5)
        }
    }
}
