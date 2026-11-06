import SwiftUI
import Combine

// MARK: - ViewModel
class CropViewModel: ObservableObject {
    @Published var sourceImage: UIImage?
    @Published var cropRect = CGRect(x: 50, y: 50, width: 250, height: 250)
    @Published var layoutRect = CGRect(x: 50, y: 50, width: 250, height: 250)
    @Published var transform = MediaCropTransform()
    @Published var containerSize: CGSize = .zero
    @Published var startRotation: Angle = .zero
    @Published var rotateCompass: Angle = .zero
    @Published var isProcessing = false
    @Published var isStraightening = false

    private(set) var baselineCropRect = CGRect.zero
    private var savedSession: MediaCropSession?
    private var hasManualPinchZoom = false

    /// Width ÷ height the crop window must hold, or `nil` for freeform.
    /// Set by `configure` and honoured by `resetAll`, so the reset button in a
    /// locked cropper doesn't hand back a full-frame rectangle.
    private var lockedAspectRatio: CGFloat?

    var canApplyCrop: Bool {
        !isProcessing
    }

    var effectiveZoomScale: CGFloat {
        transform.effectiveZoomScale(
            fitSize: layoutRect.size,
            cropRect: cropRect,
            layoutRect: layoutRect,
            panOffset: transform.panOffset,
            angleDegrees: transform.totalAngleDegrees
        )
    }

    var minimumCoverScale: CGFloat {
        MediaCropRenderer.minimumCoverScale(
            fitSize: layoutRect.size,
            cropRect: cropRect,
            layoutRect: layoutRect,
            panOffset: transform.panOffset,
            angleDegrees: transform.totalAngleDegrees
        )
    }

    var hasChanges: Bool {
        guard sourceImage != nil else { return false }
        guard let exported = exportSession() else { return false }
        if let savedSession {
             return exported != savedSession
        }
        return !transform.isIdentity || !rectsApproximatelyEqual(cropRect, baselineCropRect)
    }

    func configure(
        source: UIImage?,
        session: MediaCropSession?,
        containerSize: CGSize,
        lockedAspectRatio: CGFloat? = nil
    ) {
        sourceImage = source?.normalizedUp()
        savedSession = session
        self.lockedAspectRatio = lockedAspectRatio
        guard sourceImage != nil, containerSize.width > 0 else { return }

        self.containerSize = containerSize
        layoutRect = MediaCropRenderer.layoutRect(for: sourceImage!, in: containerSize)
        baselineCropRect = defaultCropRect(within: layoutRect)

        if let session, session.normalizedCropRect.width > 0, session.normalizedCropRect.height > 0 {
            var restored = session.makeTransform(containerSize: containerSize)
            cropRect = MediaCropRenderer.denormalizedRect(
                session.normalizedCropRect,
                containerSize: containerSize
            )
            let cover = MediaCropRenderer.minimumCoverScale(
                fitSize: layoutRect.size,
                cropRect: cropRect,
                layoutRect: layoutRect,
                panOffset: restored.panOffset,
                angleDegrees: restored.totalAngleDegrees
            )
            if abs(restored.fineAngleDegrees) < 0.5,
               restored.quarterTurns == 0,
               restored.userZoomScale <= cover + 0.05 {
                restored.userZoomScale = 1.0
                hasManualPinchZoom = false
            } else {
                hasManualPinchZoom = restored.userZoomScale > cover + 0.05
            }
            transform = restored
            rotateCompass = .degrees(session.fineAngleDegrees)
            startRotation = rotateCompass
            isStraightening = false
        } else {
            transform = .identity
            cropRect = baselineCropRect
            rotateCompass = .zero
            startRotation = .zero
            hasManualPinchZoom = false
            isStraightening = false
        }
    }

    func resetAll() {
        savedSession = nil
        transform = .identity
        rotateCompass = .zero
        startRotation = .zero
        hasManualPinchZoom = false
        isStraightening = false
        if containerSize.width > 0 {
            layoutRect = MediaCropRenderer.layoutRect(for: sourceImage!, in: containerSize)
            baselineCropRect = defaultCropRect(within: layoutRect)
            cropRect = baselineCropRect
        }
    }

    /// The window a fresh crop opens with: the whole image when freeform, or
    /// the largest centred rect of the locked ratio that still fits inside it.
    private func defaultCropRect(within rect: CGRect) -> CGRect {
        guard let ratio = lockedAspectRatio, ratio > 0, rect.width > 0, rect.height > 0 else {
            return rect
        }

        let size: CGSize = rect.width / rect.height > ratio
            ? CGSize(width: rect.height * ratio, height: rect.height)
            : CGSize(width: rect.width, height: rect.width / ratio)

        return CGRect(
            x: rect.midX - size.width / 2,
            y: rect.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    func rotateQuarterTurn() {
        var updated = transform
        updated.quarterTurns = (updated.quarterTurns + 1) % 4
        transform = updated
    }

    func beginStraightening() {
        withAnimation(.easeInOut(duration: 0.28)) {
            isStraightening = true
        }
    }

    func updateFineAngle(degrees: Double) {
        var updated = transform
        updated.fineAngleDegrees = degrees
        rotateCompass = .degrees(degrees)

        if abs(degrees) < 0.5, updated.quarterTurns == 0, !hasManualPinchZoom {
            updated.userZoomScale = 1.0
        }

        transform = updated
    }

    func finishStraightening() {
        withAnimation(.easeInOut(duration: 0.28)) {
            isStraightening = false
        }
    }

    func updatePanOffset(_ offset: CGSize) {
        var updated = transform
        updated.panOffset = offset
        transform = updated
    }

    func updateUserZoomScale(_ scale: CGFloat) {
        let cover = minimumCoverScale
        let clamped = max(scale, cover)
        hasManualPinchZoom = clamped > cover + 0.05
        var updated = transform
        updated.userZoomScale = clamped
        transform = updated
    }

    func exportSession() -> MediaCropSession? {
        guard containerSize.width > 0 else { return nil }
        return MediaCropRenderer.makeSession(
            transform: transform,
            cropRect: cropRect,
            containerSize: containerSize
        )
    }

    /// Renders the visible crop region from the untouched source image.
    func applyCrop() -> UIImage? {
        guard let source = sourceImage else { return nil }

        isProcessing = true
        defer { isProcessing = false }

        return MediaCropRenderer.render(
            source: source,
            cropRect: cropRect,
            containerSize: containerSize,
            transform: transform
        )
    }

    private func rectsApproximatelyEqual(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 1) -> Bool {
        abs(lhs.origin.x - rhs.origin.x) < tolerance
            && abs(lhs.origin.y - rhs.origin.y) < tolerance
            && abs(lhs.width - rhs.width) < tolerance
            && abs(lhs.height - rhs.height) < tolerance
    }
}

// MARK: - Extensions

extension CGRect {
    func scaleToFit(in targetSize: CGSize,
                    withFixedScale extra: CGFloat = 1.0) -> CGAffineTransform {

        let fitScaleX = targetSize.width / self.width
        let fitScaleY = targetSize.height / self.height
        let fitScale = min(fitScaleX, fitScaleY)

        let finalScale = fitScale * extra

        let newWidth = self.width * finalScale
        let newHeight = self.height * finalScale

        let originX = (targetSize.width - newWidth) / 2
        let originY = (targetSize.height - newHeight) / 2

        var t = CGAffineTransform.identity
        t = t.translatedBy(x: originX, y: originY)
        t = t.scaledBy(x: finalScale, y: finalScale)
        return t
    }
}

extension UIImage {
    func scaleToFit(in viewSize: CGSize, withFixedScale: CGFloat = 1.0) -> CGAffineTransform {
        return CGRect(x: 0, y: 0, width: size.width, height: size.height)
            .scaleToFit(in: viewSize, withFixedScale: withFixedScale)
    }
}

extension UIImage {
    /// Renders the visually-oriented image into a `.up` bitmap so crop math matches on-screen pixels.
    func normalizedUp() -> UIImage {
        guard imageOrientation != .up else { return self }
        let renderer = UIGraphicsImageRenderer(size: size)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
