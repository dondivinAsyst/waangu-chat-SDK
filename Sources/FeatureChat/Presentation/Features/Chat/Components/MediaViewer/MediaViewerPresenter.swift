import SwiftUI
import UIKit

/// Zero-size bridge that presents `MediaViewerController` from inside the real
/// UIKit view-controller hierarchy.
///
/// Presenting from the host VC rather than from the key window's root keeps the
/// presentation context correct around the tab bar, sheets already on screen and
/// rotation — and removes the window-to-VC coordinate compensation that the
/// previous SwiftUI overlay needed and never did.
private struct MediaViewerPresenter: UIViewControllerRepresentable {

    @Binding var request: MediaViewerRequest?
    let userName: String
    /// Takes positional args because gallery strings use the Android `%1$s`
    /// convention that `TranslationService` interpolates — a key-only closure
    /// cannot substitute them and leaks the raw placeholder into the UI.
    let translate: (String, [String]) -> String
    let onDelete: (MediaViewerItem, Bool) -> Void
    let transferOverlay: (MediaViewerItem, @escaping () -> Void) -> AnyView?
    let itemRefresher: (String) -> MediaViewerItem?

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.isAccessibilityElement = false
        return controller
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard let request else {
            if let presented = context.coordinator.presented {
                context.coordinator.presented = nil
                presented.dismiss(animated: true)
            }
            return
        }

        guard context.coordinator.presented == nil else { return }

        let viewer = MediaViewerController(
            request: request,
            registry: .shared,
            userName: userName,
            translate: translate
        )
        viewer.onRequestDelete = onDelete
        viewer.transferOverlayProvider = transferOverlay
        viewer.itemRefresher = itemRefresher
        viewer.onFinished = {
            context.coordinator.presented = nil
            self.request = nil
        }
        context.coordinator.presented = viewer

        // The host view is zero-size and may not be in a window on the same
        // runloop turn the binding flips.
        DispatchQueue.main.async {
            guard host.view.window != nil, host.presentedViewController == nil else { return }
            host.present(viewer, animated: true)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator {
        var presented: MediaViewerController?
    }
}

extension View {
    /// Presents the media viewer when `request` becomes non-nil.
    func mediaViewer(
        _ request: Binding<MediaViewerRequest?>,
        userName: String = "",
        translate: @escaping (String, [String]) -> String = { key, _ in key },
        onDelete: @escaping (MediaViewerItem, Bool) -> Void,
        transferOverlay: @escaping (MediaViewerItem, @escaping () -> Void) -> AnyView? = { _, _ in nil },
        itemRefresher: @escaping (String) -> MediaViewerItem? = { _ in nil }
    ) -> some View {
        background(
            MediaViewerPresenter(
                request: request,
                userName: userName,
                translate: translate,
                onDelete: onDelete,
                transferOverlay: transferOverlay,
                itemRefresher: itemRefresher
            )
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
        )
    }
}
