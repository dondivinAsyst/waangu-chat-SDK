
import SwiftUI
import UIKit
import WaanguCoreKit

// MARK: - Camera Mode Enum
enum CameraMode {
    case photo
    case video
    case both  // Allow both photo and video
}

// MARK: - Captured Media Result
struct CapturedMedia {
    let type: MediaType
    let caption: String
}

// MARK: - SwiftUI Wrapper for CameraViewController
struct CameraView: UIViewControllerRepresentable {
    @Environment(\.dismiss) var dismiss
    
    
    let mode: CameraMode
    let onCapture: ((CapturedMedia) -> Void)?
    let onDismiss: (() -> Void)?
    let onAppearTab  : (() -> Void)?
    
    
    init(
        mode: CameraMode = .both,
        onCapture: ((CapturedMedia) -> Void)? = nil,
        onDismiss: (() -> Void)? = nil,
        onAppearTab  : (() -> Void)? = nil
    ) {
        self.mode = mode
        self.onCapture = onCapture
        self.onDismiss = onDismiss
        self.onAppearTab = onAppearTab
    }
    
    func makeUIViewController(context: Context) -> CameraViewController {
        let cameraVC = CameraViewController()
        cameraVC.cameraMode = mode
        cameraVC.delegate = context.coordinator
        return cameraVC
    }
    
    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {
        // Live property update. The controller ignores a no-op change, so this
        // is safe on every SwiftUI update pass.
        uiViewController.cameraMode = mode
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, CameraViewControllerDelegate {
        let parent: CameraView
        
        init(_ parent: CameraView) {
            self.parent = parent
        }
        
        func didCaptureMedia(_ media: MediaType, caption: String) {
            let capturedMedia = CapturedMedia(type: media, caption: caption)
            parent.onCapture?(capturedMedia)
            parent.dismiss()
        }
        
        func didDismissCamera() {
            debugLog("camera dissmiss")
            parent.onDismiss?()
            parent.dismiss()
            parent.onAppearTab?()
        }
    }
}
