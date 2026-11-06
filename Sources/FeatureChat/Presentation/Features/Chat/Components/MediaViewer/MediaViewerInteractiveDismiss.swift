import UIKit

/// Drag-to-dismiss driver.
///
/// Implements `UIViewControllerInteractiveTransitioning` directly rather than
/// subclassing `UIPercentDrivenInteractiveTransition`: percent-driven scrubs a
/// single fixed timeline and cannot express "the photo follows the finger in both
/// axes while scaling".
@MainActor
final class MediaViewerInteractiveDismiss: NSObject, UIViewControllerInteractiveTransitioning {

    private let registry: MediaHeroAnchorRegistry

    private var context: UIViewControllerContextTransitioning?
    private var snapshot: UIImageView?
    private weak var fromVC: MediaViewerController?

    /// True between gesture begin and finish/cancel. The transitioning delegate
    /// hands this driver over only while it is active, so a tap on the close
    /// button still gets the plain animated dismiss.
    private(set) var isActive = false

    init(registry: MediaHeroAnchorRegistry) {
        self.registry = registry
    }

    /// Starts an interactive dismissal. Called from the pan recognizer's `.began`.
    func begin(in controller: MediaViewerController) {
        guard !isActive else { return }
        isActive = true
        controller.dismiss(animated: true)
    }

    // MARK: - UIViewControllerInteractiveTransitioning

    func startInteractiveTransition(_ transitionContext: UIViewControllerContextTransitioning) {
        context = transitionContext

        guard let from = transitionContext.viewController(forKey: .from) as? MediaViewerController,
              let image = from.currentPageCell?.imageView.image else {
            transitionContext.completeTransition(false)
            reset()
            return
        }

        fromVC = from
        let container = transitionContext.containerView

        let view = UIImageView(image: image)
        view.contentMode = .scaleAspectFit
        view.frame = HeroGeometry.targetRect(for: image.size, in: container.bounds)
        container.addSubview(view)
        snapshot = view

        from.currentPageCell?.imageView.isHidden = true
        from.view.subviews
            .filter { $0 !== from.backdrop }
            .forEach { $0.alpha = 0 }
    }

    // MARK: - Gesture driving

    /// Called from the pan recognizer's `.changed`.
    func update(translation: CGSize, in bounds: CGRect) {
        guard let snapshot, let fromVC, let context else { return }

        let progress = DismissDecision.progress(translation: translation, in: bounds)
        let scale = DismissDecision.scale(forProgress: progress)

        snapshot.transform = CGAffineTransform(translationX: translation.width, y: translation.height)
            .scaledBy(x: scale, y: scale)
        fromVC.backdrop.alpha = 1 - progress
        context.updateInteractiveTransition(progress)
    }

    /// Called from the pan recognizer's `.ended` / `.cancelled` / `.failed`.
    func end(translation: CGSize, velocity: CGSize) {
        guard isActive else { return }

        switch DismissDecision.outcome(translation: translation, velocity: velocity) {
        case .finish:
            finish()
        case .cancel:
            cancel()
        }
    }

    // MARK: - Private

    private func finish() {
        guard let snapshot, let fromVC, let context else { return }

        let anchor = registry.flyableAnchor(for: fromVC.currentAnchorID)
        if anchor != nil {
            registry.hiddenAnchorID = fromVC.currentAnchorID
        }

        let animator = UIViewPropertyAnimator(
            duration: 0.28,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.9)
        )
        animator.addAnimations {
            if let anchor {
                snapshot.transform = .identity
                snapshot.frame = context.containerView.convert(anchor.rect, from: nil)
                snapshot.contentMode = .scaleAspectFill
                snapshot.clipsToBounds = true
                snapshot.layer.cornerRadius = 16
            } else {
                snapshot.alpha = 0
            }
            fromVC.backdrop.alpha = 0
        }
        animator.addCompletion { [registry] _ in
            snapshot.removeFromSuperview()
            registry.hiddenAnchorID = nil
            fromVC.view.removeFromSuperview()
            context.finishInteractiveTransition()
            context.completeTransition(true)
            self.reset()
        }
        animator.startAnimation()
    }

    private func cancel() {
        guard let snapshot, let fromVC, let context else { return }

        let animator = UIViewPropertyAnimator(
            duration: 0.25,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.85)
        )
        animator.addAnimations {
            snapshot.transform = .identity
            fromVC.backdrop.alpha = 1
        }
        animator.addCompletion { _ in
            snapshot.removeFromSuperview()
            fromVC.currentPageCell?.imageView.isHidden = false
            fromVC.view.subviews.forEach { $0.alpha = 1 }
            context.cancelInteractiveTransition()
            context.completeTransition(false)
            self.reset()
        }
        animator.startAnimation()
    }

    private func reset() {
        snapshot = nil
        fromVC = nil
        context = nil
        isActive = false
    }
}
