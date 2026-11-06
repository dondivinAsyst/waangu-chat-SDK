import UIKit

/// Flies the current page back to its bubble, or fades it out in place when that
/// bubble has scrolled off screen or been deleted.
///
/// Targets `currentAnchorID`, not the anchor the viewer was opened from — open on
/// photo 1, swipe to photo 5, and this returns to photo 5.
@MainActor
final class MediaViewerDismissAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    private let registry: MediaHeroAnchorRegistry
    private let duration: TimeInterval = 0.3

    init(registry: MediaHeroAnchorRegistry) {
        self.registry = registry
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView

        guard let fromVC = context.viewController(forKey: .from) as? MediaViewerController else {
            context.completeTransition(false)
            return
        }

        let anchorID = fromVC.currentAnchorID
        let image = fromVC.currentPageCell?.imageView.image

        guard let anchor = registry.flyableAnchor(for: anchorID), let image else {
            animateFadeOut(fromVC: fromVC, context: context)
            return
        }

        registry.hiddenAnchorID = anchorID

        let snapshot = UIImageView(image: image)
        snapshot.contentMode = .scaleAspectFill
        snapshot.clipsToBounds = true
        snapshot.frame = HeroGeometry.targetRect(for: image.size, in: container.bounds)
        container.addSubview(snapshot)

        // Hide the live page so only the snapshot is visible in flight.
        fromVC.currentPageCell?.imageView.isHidden = true
        fromVC.view.subviews
            .filter { $0 !== fromVC.backdrop }
            .forEach { $0.alpha = 0 }

        let targetRect = container.convert(anchor.rect, from: nil)

        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.9)
        )
        animator.addAnimations {
            snapshot.frame = targetRect
            snapshot.layer.cornerRadius = 16
            fromVC.backdrop.alpha = 0
        }
        animator.addCompletion { [registry] _ in
            snapshot.removeFromSuperview()
            registry.hiddenAnchorID = nil
            fromVC.view.removeFromSuperview()
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }

    private func animateFadeOut(
        fromVC: MediaViewerController,
        context: UIViewControllerContextTransitioning
    ) {
        let animator = UIViewPropertyAnimator(duration: duration, curve: .easeOut)
        animator.addAnimations {
            fromVC.view.alpha = 0
            fromVC.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)
        }
        animator.addCompletion { [registry] _ in
            fromVC.view.removeFromSuperview()
            registry.hiddenAnchorID = nil
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
