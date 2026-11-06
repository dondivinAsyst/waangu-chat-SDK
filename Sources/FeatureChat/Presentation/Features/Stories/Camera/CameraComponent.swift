import SwiftUI
import UIKit
import WaanguCoreKit

// MARK: - Camera View for Photos
struct CameraView1: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.cameraCaptureMode = .photo
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraView1
        
        init(_ parent: CameraView1) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let uiImage = info[.originalImage] as? UIImage {
                parent.image = uiImage
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Video Recorder
struct VideoRecorderView: UIViewControllerRepresentable {
    @Binding var videoURL: URL?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        picker.mediaTypes = ["public.movie"]
        picker.cameraCaptureMode = .video
        return picker
    }
    
    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: VideoRecorderView
        
        init(_ parent: VideoRecorderView) {
            self.parent = parent
        }
        
        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
            if let url = info[.mediaURL] as? URL {
                parent.videoURL = url
            }
            parent.dismiss()
        }
        
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

// MARK: - Capture Mode Enum (Only Photo & Video)
enum CaptureMode: String, CaseIterable {
    case photo = "PHOTO"
    case video = "VIDEO"
    
    var icon: String {
        switch self {
        case .photo: return "camera.fill"
        case .video: return "video.fill"
        }
    }
}

// MARK: - Simple Tab Menu
struct CameraTabMenu: View {
    @Binding var selectedMode: CaptureMode
    let translationService: (any TranslationServiceProtocol)?
    
    init(selectedMode: Binding<CaptureMode>, translationService: (any TranslationServiceProtocol)? = nil) {
        self._selectedMode = selectedMode
        self.translationService = translationService
    }
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureMode.allCases, id: \.self) { mode in
                VStack(spacing: 8) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                            selectedMode = mode
                        }
                    }) {
                        VStack(spacing: 6) {
                            Image(systemName: mode.icon)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.7))
                            
                            Text(title(for: mode))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(selectedMode == mode ? .white : .white.opacity(0.7))
                        }
                    }
                    
                    // Underline indicator
                    Rectangle()
                        .fill(Color.white)
                        .frame(height: 3)
                        .frame(width: 50)
                        .opacity(selectedMode == mode ? 1 : 0)
                        .cornerRadius(1.5)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 12)
    }

    private func title(for mode: CaptureMode) -> String {
        switch mode {
        case .photo:
            return translationService?.resolve(key: ChatTranslationKeys.STORIES_PHOTO_LABEL, module: ChatTranslationKeys.MODULE).value ?? "PHOTO"
        case .video:
            return translationService?.resolve(key: ChatTranslationKeys.STORIES_VIDEO_LABEL, module: ChatTranslationKeys.MODULE).value ?? "VIDEO"
        }
    }
}

// MARK: - Main Camera View
struct CameraTabView: View {
    @State private var capturedImage: UIImage?
    @State private var videoURL: URL?
    @State private var isShowingCamera = false
    @State private var selectedMode: CaptureMode = .photo
    let translationService: (any TranslationServiceProtocol)? = nil
    
    var body: some View {
        ZStack {
            // Black background
            Color.black.ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with tab menu
                HStack {
                    Spacer()
                    
                    // Tab menu
                    CameraTabMenu(selectedMode: $selectedMode, translationService: translationService)
                        .frame(width: 150)
                    
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 50)
                
                Spacer()
                
                // Content area
                Group {
                    switch selectedMode {
                    case .photo:
                        photoContentView
                    case .video:
                        videoContentView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                
                Spacer()
                
                // Bottom controls
                VStack(spacing: 20) {
                    // Capture button
                    Button(action: {
                        handleCapture()
                    }) {
                        ZStack {
                            Circle()
                                .stroke(Color.white, lineWidth: 4)
                                .frame(width: 70, height: 70)
                            
                            Circle()
                                .fill(Color.white)
                                .frame(width: 60, height: 60)
                        }
                    }
                    
                    // Mode description
                    Text(selectedMode == .photo ? "Tap to take a photo" : "Tap to record video")
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.7))
                        .padding(.bottom, 30)
                }
            }
        }
        .chatAppearanceSheet(isPresented: $isShowingCamera) {
            if selectedMode == .photo {
                CameraView1(image: $capturedImage)
            } else {
                VideoRecorderView(videoURL: $videoURL)
            }
        }
    }
    
    // MARK: - Photo Content
    private var photoContentView: some View {
        VStack {
            if let image = capturedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .cornerRadius(12)
                    .padding()
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(t(ChatTranslationKeys.STORIES_NO_PHOTO_CAPTURED))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Video Content
    private var videoContentView: some View {
        VStack {
            if let url = videoURL {
                // You can add video player here to preview recorded video
                VStack(spacing: 20) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 60))
                        .foregroundColor(.green)
                    
                    Text(t(ChatTranslationKeys.STORIES_VIDEO_RECORDED))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.8))
                    
                    Text(url.lastPathComponent)
                        .font(.system(size: 12))
                        .foregroundColor(.white.opacity(0.6))
                }
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "video.slash")
                        .font(.system(size: 80))
                        .foregroundColor(.white.opacity(0.3))
                    
                    Text(t(ChatTranslationKeys.STORIES_NO_VIDEO_RECORDED))
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
        }
    }
    
    // MARK: - Capture Handler
    private func handleCapture() {
        isShowingCamera = true
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}



#Preview {
    CameraTabView()
}
