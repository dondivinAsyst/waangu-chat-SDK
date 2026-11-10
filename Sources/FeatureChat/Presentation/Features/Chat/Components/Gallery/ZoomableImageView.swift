
////
/////
//  ZoomableImageView.swift
//  Pods
//
//  Created by Asyst on 6/19/25.
//
import SwiftUI
import WaanguSharedUI
import SDWebImageSwiftUI
import Photos
import WaanguCoreKit

struct ZoomableImageOverlay: View {
    let image: GalleryImage
    let isSelected: Bool
    let onDismiss: () -> Void
    let onSelect: () -> Void
    let sourceRect : CGRect
    let translationService: (any TranslationServiceProtocol)? = nil
    
    @State private var highQualityImage: UIImage?
    @State private var captionText: String = ""
    @FocusState private var isInputFocused: Bool
    @State private var animateIn = false
    @State private var dismissing = false
    @State private var dragOffset: CGSize = .zero
    @State private var isSwiping = false



    var body: some View {
                ZStack {
                    Color.black
                       .ignoresSafeArea()
                       .opacity(animateIn ? max(0, CGFloat(1) - abs(dragOffset.height) / CGFloat(300)) : 0)
                       .animation(.easeInOut(duration: 0.25), value: dragOffset)

                            
                    if let highQualityImage = highQualityImage {
                      GeometryReader { geometry in
                        let screenSize = geometry.size

                        let fullWidth = screenSize.width
                        let fullHeight = screenSize.height
                        let fullMidX = screenSize.width / 2
                        let fullMidY = screenSize.height / 2

                        ZoomableImageView(
                          image: highQualityImage,
                          onDismiss: dismissWithAnimation
                        )
                        .frame(
                                    width: animateIn ? fullWidth : sourceRect.width,
                                    height: animateIn ? fullHeight : sourceRect.height
                                )
                                .position(
                                    x: animateIn ? fullMidX : sourceRect.midX,
                                    y: animateIn ? fullMidY : sourceRect.midY
                                )
                                .offset(y: dragOffset.height)
                                .gesture(swipeToDismissGesture)
                                .animation(.spring(response: 0.5, dampingFraction: 0.9), value: animateIn)
                                .animation(.spring(response: 0.4, dampingFraction: 0.9), value: dragOffset)
                            
                      }
                    }

                   else {
                        ProgressView().scaleEffect(2.0)
                           .animation(.spring(response: 0.5, dampingFraction: 0.9), value: animateIn)
                    }

                    VStack {
                        // Top bar
                        HStack {
                            Button(action: dismissWithAnimation) {
                                Image(systemName: "xmark")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }

                            Spacer()

                            Button(action: onSelect) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                    .font(.title2)
                                    .foregroundColor(isSelected ? AppColors.primary : .white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                        }
                        .padding(.top, 20)
                        .padding(.horizontal)

                        Spacer()

                        // Caption TextField at the bottom
                        HStack {
                            TextField(translationService?.resolve(key: ChatTranslationKeys.FILE_ADD_CAPTION, module: ChatTranslationKeys.MODULE).value ?? "Add a caption...", text: $captionText)
                                .padding(12)
                                .background(CaptionBlurView(style: .systemThinMaterialDark))
                                .cornerRadius(25)
                                .foregroundColor(.white)
                                .padding(.horizontal)
                                .focused($isInputFocused)
                           
                            if isInputFocused {
                                Button(action: {
                                    isInputFocused = false
                                }) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(.white)
                                        .padding(10)
                                        .background(Circle().fill(Color.white.opacity(0.2)))
                                }
                            }
                                
                            
                        }
                        .padding(.bottom, 30)
                    }
    
                    .offset(y: dragOffset.height)
                    .opacity(isSwiping ? 0 : 1) // 🔥 key change
                    .animation(.easeInOut(duration: 0.2), value: isSwiping)
                }
                .statusBar(hidden: true)
                .onAppear {
                    loadHighQualityImage()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                        animateIn = true
                    }
                }
               

          
    }
    
    private var swipeToDismissGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                dragOffset = value.translation
                          if !isSwiping {
                              isSwiping = true
                          }
            }
            .onEnded { value in
                let verticalAmount = value.translation.height
                let verticalVelocity = value.predictedEndTranslation.height

                if abs(verticalAmount) > 120 || abs(verticalVelocity) > 300 {
                    // Disable input focus first
                    isInputFocused = false

                    withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
                        animateIn = false
                        dragOffset = .zero // Optional: Reset dragOffset
                    }

                    // Delay dismissal until animation finishes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        onDismiss()
                    }
                } else {
                    withAnimation(.spring()) {
                        dragOffset = .zero
                        isSwiping = false
                    }
                }
            }
    }

   
    
    private func dismissWithAnimation() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.9)) {
            animateIn = false
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            onDismiss()
        }
    }

    private func loadHighQualityImage() {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        PHImageManager.default().requestImage(
            for: image.asset,
            targetSize: PHImageManagerMaximumSize,
            contentMode: .aspectFit,
            options: options
        ) { result, _ in
            DispatchQueue.main.async {
                self.highQualityImage = result
            }
        }
    }
}



struct ZoomableImageView: View {
    let image: UIImage
    let onDismiss: () -> Void

    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        }
    }
}


struct CaptionBlurView: UIViewRepresentable {
    let style: UIBlurEffect.Style

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {}
}



