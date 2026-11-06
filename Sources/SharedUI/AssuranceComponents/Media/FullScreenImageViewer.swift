import SwiftUI

struct FullScreenImageViewer: View {
    let image: UIImage
    let sourceFrame: CGRect
    let onClose: () -> Void

    @State private var isExpanded = false
    @State private var dragOffset: CGSize = .zero
    @State private var backgroundOpacity: Double = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0

    private let openSpring = Animation.spring(response: 0.4, dampingFraction: 0.88)
    private let closeSpring = Animation.spring(response: 0.35, dampingFraction: 0.88)
    private let dismissThreshold: CGFloat = 150
    private let sourceRadius: CGFloat = AppCornerRadius.lg

    private var screenBounds: CGRect { UIScreen.main.bounds }

    private var targetSize: CGSize {
        let imgAspect = image.size.width / image.size.height
        let scrAspect = screenBounds.width / screenBounds.height
        if imgAspect > scrAspect {
            let w = screenBounds.width
            return CGSize(width: w, height: w / imgAspect)
        } else {
            let h = screenBounds.height
            return CGSize(width: h * imgAspect, height: h)
        }
    }

    private var currentCenter: CGPoint {
        isExpanded
            ? CGPoint(x: screenBounds.midX, y: screenBounds.midY)
            : CGPoint(x: sourceFrame.midX, y: sourceFrame.midY)
    }

    private var currentSize: CGSize {
        isExpanded ? targetSize : sourceFrame.size
    }

    private var currentRadius: CGFloat {
        isExpanded ? 0 : sourceRadius
    }

    var body: some View {
        ZStack {
            Color.black
                .opacity(backgroundOpacity)
                .onTapGesture { close() }

            Image(uiImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: currentSize.width, height: currentSize.height)
                .clipShape(RoundedRectangle(cornerRadius: currentRadius))
                .scaleEffect(scale)
                .position(
                    x: currentCenter.x + dragOffset.width,
                    y: currentCenter.y + dragOffset.height
                )
                .gesture(pinchGesture)
                .simultaneousGesture(panGesture)
        }
        .ignoresSafeArea()
        .statusBarHidden(isExpanded)
        .onAppear {
            withAnimation(openSpring) {
                isExpanded = true
                backgroundOpacity = 1.0
            }
        }
    }

    // MARK: - Pinch to Zoom

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                scale = lastScale * value
            }
            .onEnded { _ in
                if scale < 1.0 {
                    withAnimation(openSpring) {
                        scale = 1.0
                        lastScale = 1.0
                    }
                } else {
                    lastScale = scale
                }
            }
    }

    // MARK: - Drag to Dismiss

    private var panGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale <= 1.05 else { return }
                dragOffset = value.translation
                let progress = abs(value.translation.height) / 300
                backgroundOpacity = max(0, 1.0 - progress)
            }
            .onEnded { value in
                guard scale <= 1.05 else { return }
                if abs(value.translation.height) > dismissThreshold {
                    close()
                } else {
                    withAnimation(openSpring) {
                        dragOffset = .zero
                        backgroundOpacity = 1.0
                    }
                }
            }
    }

    private func close() {
        withAnimation(closeSpring) {
            isExpanded = false
            backgroundOpacity = 0
            dragOffset = .zero
            scale = 1.0
            lastScale = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            onClose()
        }
    }
}
