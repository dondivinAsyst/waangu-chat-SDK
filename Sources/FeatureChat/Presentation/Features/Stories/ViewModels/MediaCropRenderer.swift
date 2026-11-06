import UIKit

struct MediaCropSession: Equatable {
    var userZoomScale: CGFloat = 1.0
    var fineAngleDegrees: Double = 0
    var quarterTurns: Int = 0
    var normalizedCropRect: CGRect = .zero
    var normalizedPanOffset: CGSize = .zero

    var isEmpty: Bool {
        normalizedCropRect.width <= 0 || normalizedCropRect.height <= 0
    }

    func makeTransform(containerSize: CGSize) -> MediaCropTransform {
        MediaCropTransform(
            userZoomScale: userZoomScale,
            panOffset: MediaCropRenderer.denormalizedPan(normalizedPanOffset, containerSize: containerSize),
            fineAngleDegrees: fineAngleDegrees,
            quarterTurns: quarterTurns
        )
    }
}

struct MediaCropTransform: Equatable {
    static let identity = MediaCropTransform()

    var userZoomScale: CGFloat = 1.0
    var panOffset: CGSize = .zero
    var fineAngleDegrees: Double = 0
    var quarterTurns: Int = 0

    var totalAngleDegrees: CGFloat {
        CGFloat(quarterTurns) * 90 + CGFloat(fineAngleDegrees)
    }

    var isIdentity: Bool {
        userZoomScale == 1.0
            && panOffset == .zero
            && fineAngleDegrees == 0
            && quarterTurns == 0
    }

    func effectiveZoomScale(
        fitSize: CGSize,
        cropRect: CGRect,
        layoutRect: CGRect,
        panOffset: CGSize,
        angleDegrees: CGFloat
    ) -> CGFloat {
        let cover = MediaCropRenderer.minimumCoverScale(
            fitSize: fitSize,
            cropRect: cropRect,
            layoutRect: layoutRect,
            panOffset: panOffset,
            angleDegrees: angleDegrees
        )
        return max(userZoomScale, cover)
    }
}

enum MediaCropRenderer {
    static func normalizedRect(_ rect: CGRect, containerSize: CGSize) -> CGRect {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        return CGRect(
            x: rect.origin.x / containerSize.width,
            y: rect.origin.y / containerSize.height,
            width: rect.width / containerSize.width,
            height: rect.height / containerSize.height
        )
    }

    static func denormalizedRect(_ rect: CGRect, containerSize: CGSize) -> CGRect {
        CGRect(
            x: rect.origin.x * containerSize.width,
            y: rect.origin.y * containerSize.height,
            width: rect.width * containerSize.width,
            height: rect.height * containerSize.height
        )
    }

    static func normalizedPan(_ offset: CGSize, containerSize: CGSize) -> CGSize {
        guard containerSize.width > 0, containerSize.height > 0 else { return .zero }
        return CGSize(
            width: offset.width / containerSize.width,
            height: offset.height / containerSize.height
        )
    }

    static func denormalizedPan(_ offset: CGSize, containerSize: CGSize) -> CGSize {
        CGSize(
            width: offset.width * containerSize.width,
            height: offset.height * containerSize.height
        )
    }

    static func makeSession(
        transform: MediaCropTransform,
        cropRect: CGRect,
        containerSize: CGSize
    ) -> MediaCropSession {
        MediaCropSession(
            userZoomScale: transform.userZoomScale,
            fineAngleDegrees: transform.fineAngleDegrees,
            quarterTurns: transform.quarterTurns,
            normalizedCropRect: normalizedRect(cropRect, containerSize: containerSize),
            normalizedPanOffset: normalizedPan(transform.panOffset, containerSize: containerSize)
        )
    }

    static func previewImage(
        source: UIImage,
        session: MediaCropSession,
        containerSize: CGSize
    ) -> UIImage? {
        guard containerSize.width > 0, containerSize.height > 0 else { return nil }
        let cropRect = denormalizedRect(session.normalizedCropRect, containerSize: containerSize)
        let transform = session.makeTransform(containerSize: containerSize)
        return render(
            source: source,
            cropRect: cropRect,
            containerSize: containerSize,
            transform: transform
        )
    }

    static func layoutRect(for image: UIImage, in containerSize: CGSize) -> CGRect {
        let imageAspect = image.size.width / image.size.height
        let containerAspect = containerSize.width / containerSize.height

        let displayedWidth: CGFloat
        let displayedHeight: CGFloat

        if imageAspect > containerAspect {
            displayedWidth = containerSize.width
            displayedHeight = containerSize.width / imageAspect
        } else {
            displayedHeight = containerSize.height
            displayedWidth = containerSize.height * imageAspect
        }

        let originX = (containerSize.width - displayedWidth) / 2
        let originY = (containerSize.height - displayedHeight) / 2

        return CGRect(
            origin: CGPoint(x: originX, y: originY),
            size: CGSize(width: displayedWidth, height: displayedHeight)
        )
    }

    /// Minimum uniform scale so a rotated image fully covers `cropRect`.
    static func minimumCoverScale(
        fitSize: CGSize,
        cropRect: CGRect,
        layoutRect: CGRect,
        panOffset: CGSize,
        angleDegrees: CGFloat
    ) -> CGFloat {
        guard fitSize.width > 0, fitSize.height > 0, cropRect.width > 0, cropRect.height > 0 else {
            return 1.0
        }

        let center = CGPoint(
            x: layoutRect.midX + panOffset.width,
            y: layoutRect.midY + panOffset.height
        )
        let radians = angleDegrees * .pi / 180
        let cosA = cos(radians)
        let sinA = sin(radians)
        let halfW = fitSize.width / 2
        let halfH = fitSize.height / 2

        let corners = [
            CGPoint(x: cropRect.minX, y: cropRect.minY),
            CGPoint(x: cropRect.maxX, y: cropRect.minY),
            CGPoint(x: cropRect.minX, y: cropRect.maxY),
            CGPoint(x: cropRect.maxX, y: cropRect.maxY),
        ]

        var required: CGFloat = 1.0
        for corner in corners {
            let dx = corner.x - center.x
            let dy = corner.y - center.y
            let localX = dx * cosA + dy * sinA
            let localY = -dx * sinA + dy * cosA
            let scaleX = halfW > 0 ? abs(localX) / halfW : 1
            let scaleY = halfH > 0 ? abs(localY) / halfH : 1
            required = max(required, scaleX, scaleY)
        }

        return required
    }

    static func render(
        source: UIImage,
        cropRect: CGRect,
        containerSize: CGSize,
        transform: MediaCropTransform
    ) -> UIImage? {
        guard let cgImage = source.cgImage,
              cropRect.width > 0,
              cropRect.height > 0,
              containerSize.width > 0,
              containerSize.height > 0 else { return nil }

        let pixelScale = source.scale
        let fitRect = layoutRect(for: source, in: containerSize)
        let zoom = transform.effectiveZoomScale(
            fitSize: fitRect.size,
            cropRect: cropRect,
            layoutRect: fitRect,
            panOffset: transform.panOffset,
            angleDegrees: transform.totalAngleDegrees
        )
        let outputSize = CGSize(
            width: cropRect.width * pixelScale,
            height: cropRect.height * pixelScale
        )

        let renderer = UIGraphicsImageRenderer(size: outputSize)
        return renderer.image { ctx in
            let context = ctx.cgContext
            context.translateBy(x: -cropRect.origin.x * pixelScale, y: -cropRect.origin.y * pixelScale)
            context.scaleBy(x: pixelScale, y: pixelScale)

            let center = CGPoint(
                x: fitRect.midX + transform.panOffset.width,
                y: fitRect.midY + transform.panOffset.height
            )
            let radians = transform.totalAngleDegrees * .pi / 180

            context.translateBy(x: center.x, y: center.y)
            context.rotate(by: radians)
            context.scaleBy(x: zoom, y: zoom)

            let drawRect = CGRect(
                x: -fitRect.width / 2,
                y: -fitRect.height / 2,
                width: fitRect.width,
                height: fitRect.height
            )
            UIImage(cgImage: cgImage, scale: source.scale, orientation: .up)
                .draw(in: drawRect)
        }
    }
}
