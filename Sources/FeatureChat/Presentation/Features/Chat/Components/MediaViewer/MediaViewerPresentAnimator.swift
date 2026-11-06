import UIKit

/// Flies a snapshot from the tapped bubble to the full-screen page.
///
/// Two properties make this seamless where the previous SwiftUI hero was not:
/// the source rect is converted into the transition container's coordinate space,
/// and the destination image view stays hidden until this animator's completion
/// block runs — not until a `DispatchQueue.asyncAfter` guesses that the spring
/// has settled.
@MainActor
final class MediaViewerPresentAnimator: NSObject, UIViewControllerAnimatedTransitioning {

    private let registry: MediaHeroAnchorRegistry
    private let anchorID: String
    private let duration: TimeInterval = 0.32

    init(registry: MediaHeroAnchorRegistry, anchorID: String) {
        self.registry = registry
        self.anchorID = anchorID
    }

    func transitionDuration(using context: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using context: UIViewControllerContextTransitioning) {
        let container = context.containerView

        guard let toVC = context.viewController(forKey: .to) as? MediaViewerController else {
            context.completeTransition(false)
            return
        }

        toVC.view.frame = container.bounds
        container.addSubview(toVC.view)
        toVC.view.layoutIfNeeded()

        let anchor = registry.anchor(for: anchorID)
        let heroImage = anchor?.image ?? toVC.currentItem?.thumbnail

        // No usable anchor: fade and scale up from center instead of flying from
        // a rect we do not trust.
        guard let anchor, let heroImage, anchor.rect != .zero else {
            animateFallback(toVC: toVC, context: context)
            return
        }

        toVC.view.alpha = 1
        toVC.backdrop.alpha = 0

        let destination = toVC.currentPageCell?.imageView
        destination?.isHidden = true

        registry.hiddenAnchorID = anchorID

        let snapshot = UIImageView(image: heroImage)
        snapshot.contentMode = .scaleAspectFill
        snapshot.clipsToBounds = true
        snapshot.layer.cornerRadius = 16
        snapshot.frame = container.convert(anchor.rect, from: nil)
        container.addSubview(snapshot)

        // Because the target rect already carries the image's aspect ratio,
        // aspectFill and aspectFit converge there — so animating the frame alone
        // takes the snapshot from the bubble's cropped fill to the fitted full
        // image with no content-mode pop.
        let targetRect = HeroGeometry.targetRect(for: heroImage.size, in: container.bounds)

        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.9)
        )
        animator.addAnimations {
            snapshot.frame = targetRect
            snapshot.layer.cornerRadius = 0
            toVC.backdrop.alpha = 1
        }
        animator.addCompletion { [registry] _ in
            snapshot.removeFromSuperview()
            destination?.isHidden = false
            registry.hiddenAnchorID = nil
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }

    private func animateFallback(
        toVC: MediaViewerController,
        context: UIViewControllerContextTransitioning
    ) {
        toVC.view.alpha = 0
        toVC.view.transform = CGAffineTransform(scaleX: 0.9, y: 0.9)

        let animator = UIViewPropertyAnimator(
            duration: duration,
            timingParameters: UISpringTimingParameters(dampingRatio: 0.9)
        )
        animator.addAnimations {
            toVC.view.alpha = 1
            toVC.view.transform = .identity
        }
        animator.addCompletion { _ in
            context.completeTransition(!context.transitionWasCancelled)
        }
        animator.startAnimation()
    }
}
