import SwiftUI

/// Black bars drawn only outside the crop window.
/// Opacity 0.5 = dimmed image visible outside while straightening.
/// Opacity 1.0 = fully hidden outside when straightening ends.
struct CropOutsideShutter: View {
    let cropRect: CGRect
    let containerSize: CGSize
    let opacity: Double
    var shape: CropWindowShape = .freeform

    var body: some View {
        Canvas { context, _ in
            guard opacity > 0 else { return }
            switch shape {
            case .freeform:
                for bar in outsideBars {
                    context.fill(
                        Path(bar),
                        with: .color(.black.opacity(opacity))
                    )
                }
            case .circle:
                // Four bars can't describe a round hole, so dim the whole
                // container and subtract the circle with an even-odd fill.
                var path = Path(CGRect(origin: .zero, size: containerSize))
                path.addEllipse(in: cropRect)
                context.fill(
                    path,
                    with: .color(.black.opacity(opacity)),
                    style: FillStyle(eoFill: true)
                )
            }
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .allowsHitTesting(false)
    }

    private var outsideBars: [CGRect] {
        guard containerSize.width > 0, containerSize.height > 0 else { return [] }

        var bars: [CGRect] = []

        if cropRect.minY > 0 {
            bars.append(CGRect(x: 0, y: 0, width: containerSize.width, height: cropRect.minY))
        }
        if cropRect.maxY < containerSize.height {
            let height = containerSize.height - cropRect.maxY
            bars.append(CGRect(x: 0, y: cropRect.maxY, width: containerSize.width, height: height))
        }
        if cropRect.minX > 0 {
            bars.append(CGRect(x: 0, y: cropRect.minY, width: cropRect.minX, height: cropRect.height))
        }
        if cropRect.maxX < containerSize.width {
            let width = containerSize.width - cropRect.maxX
            bars.append(CGRect(x: cropRect.maxX, y: cropRect.minY, width: width, height: cropRect.height))
        }

        return bars
    }
}

/// Full image inside crop, shutter outside crop.
struct CropMaskView<Content: View>: View {
    let cropRect: CGRect
    let containerSize: CGSize
    let isStraightening: Bool
    var shape: CropWindowShape = .freeform
    @ViewBuilder let image: () -> Content

    private var outsideShutterOpacity: Double {
        isStraightening ? 0.5 : 0.5
    }

    var body: some View {
        ZStack {
            image()

            CropOutsideShutter(
                cropRect: cropRect,
                containerSize: containerSize,
                opacity: outsideShutterOpacity,
                shape: shape
            )
        }
        .frame(width: containerSize.width, height: containerSize.height)
        .animation(.easeInOut(duration: 0.28), value: isStraightening)
    }
}
