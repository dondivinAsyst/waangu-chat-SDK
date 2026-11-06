import SwiftUI
import UIKit

/// Full-screen status host with WhatsAppStories-style dismiss:
/// pan down from anywhere → the whole surface follows the finger;
/// past half screen → dismiss; otherwise spring back.
@available(iOS 16.0, *)
struct DraggableFullScreenModal<Content: View>: View {
    let statusStore: StoriesViewModel
    @Binding var isPresented: Bool
    let onDismiss: () -> Void
    let content: Content

    init(
        isPresented: Binding<Bool>,
        @ViewBuilder content: () -> Content,
        statusStore: StoriesViewModel,
        onDismiss: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.content = content()
        self.statusStore = statusStore
        self.onDismiss = onDismiss ?? { statusStore.closeStatusViewer() }
    }

    var body: some View {
        InteractiveStoryDismissHost(
            isPresented: $isPresented,
            onDraggingChanged: { dragging in
                statusStore.isSlidingToBottom = dragging
                if !dragging {
                    statusStore.statusViewerDragOffset = 0
                }
            },
            onDismiss: {
                onDismiss()
            }
        ) {
            content
        }
        .ignoresSafeArea()
        .onAppear {
            statusStore.resetStatusViewerDrag(animated: false)
        }
    }
}

// MARK: - UIKit interactive dismiss (matches WhatsAppStories StoryViewController)

@available(iOS 16.0, *)
private struct InteractiveStoryDismissHost<Content: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var onDraggingChanged: (Bool) -> Void
    var onDismiss: () -> Void
    @ViewBuilder var content: () -> Content

    func makeUIViewController(context: Context) -> InteractiveStoryDismissController<Content> {
        let controller = InteractiveStoryDismissController(rootView: content())
        controller.onDraggingChanged = onDraggingChanged
        controller.onDismiss = onDismiss
        return controller
    }

    func updateUIViewController(_ uiViewController: InteractiveStoryDismissController<Content>, context: Context) {
        // Do not replace rootView on every SwiftUI refresh — that remounts StoryViewer and resets timers.
        uiViewController.onDraggingChanged = onDraggingChanged
        uiViewController.onDismiss = onDismiss
    }
}

@available(iOS 16.0, *)
final class InteractiveStoryDismissController<Content: View>: UIViewController, UIGestureRecognizerDelegate {
    var rootView: Content {
        didSet { hostingController.rootView = rootView }
    }
    var onDraggingChanged: ((Bool) -> Void)?
    var onDismiss: (() -> Void)?

    private let hostingController: UIHostingController<Content>
    private var initialTouchPoint: CGPoint = .zero
    private let dismissThresholdFraction: CGFloat = 0.5
    private var isDraggingDown = false

    init(rootView: Content) {
        self.rootView = rootView
        self.hostingController = UIHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        addChild(hostingController)
        hostingController.view.backgroundColor = .black
        hostingController.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hostingController.view)
        NSLayoutConstraint.activate([
            hostingController.view.topAnchor.constraint(equalTo: view.topAnchor),
            hostingController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hostingController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hostingController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        hostingController.didMove(toParent: self)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePan(_ sender: UIPanGestureRecognizer) {
        let touchPoint = sender.location(in: view.window)
        let translation = sender.translation(in: view)
        let hostView = hostingController.view!

        switch sender.state {
        case .began:
            initialTouchPoint = touchPoint
            isDraggingDown = false

        case .changed:
            let dy = touchPoint.y - initialTouchPoint.y
            let dx = translation.x
            // Only claim vertical-down dismiss (leave horizontal paging alone).
            if !isDraggingDown {
                if abs(dy) < 10 { return }
                if abs(dx) > abs(dy) { return }
                guard dy > 0 else { return }
                isDraggingDown = true
                onDraggingChanged?(true)
            }

            guard isDraggingDown else { return }
            let offsetY = max(0, dy)
            let progress = min(1, offsetY / (view.bounds.height * 0.5))
            hostView.transform = CGAffineTransform(translationX: 0, y: offsetY)
                .scaledBy(x: 1 - progress * 0.08, y: 1 - progress * 0.08)
            hostView.layer.cornerRadius = 32 * progress
            hostView.clipsToBounds = progress > 0.01
            view.backgroundColor = UIColor.black.withAlphaComponent(1 - progress * 0.55)

        case .ended, .cancelled, .failed:
            guard isDraggingDown else { return }
            isDraggingDown = false

            let dy = max(0, touchPoint.y - initialTouchPoint.y)
            let velocityY = sender.velocity(in: view).y
            let half = view.bounds.height * dismissThresholdFraction
            let shouldDismiss = dy >= half || (dy > 120 && velocityY > 900)

            if shouldDismiss {
                let remaining = view.bounds.height - dy
                UIView.animate(
                    withDuration: 0.28,
                    delay: 0,
                    options: [.curveEaseOut],
                    animations: {
                        hostView.transform = CGAffineTransform(translationX: 0, y: self.view.bounds.height)
                            .scaledBy(x: 0.9, y: 0.9)
                        self.view.backgroundColor = UIColor.black.withAlphaComponent(0.2)
                    },
                    completion: { _ in
                        self.onDraggingChanged?(false)
                        self.onDismiss?()
                    }
                )
                _ = remaining
            } else {
                UIView.animate(
                    withDuration: 0.3,
                    delay: 0,
                    usingSpringWithDamping: 0.86,
                    initialSpringVelocity: 0.4,
                    options: [.curveEaseOut],
                    animations: {
                        hostView.transform = .identity
                        hostView.layer.cornerRadius = 0
                        self.view.backgroundColor = .black
                    },
                    completion: { _ in
                        hostView.clipsToBounds = false
                        self.onDraggingChanged?(false)
                    }
                )
            }

        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
        let v = pan.velocity(in: view)
        // Prefer starting when movement is mostly downward.
        if abs(v.x) > abs(v.y) * 1.35 { return false }
        return v.y >= -40
    }
}
