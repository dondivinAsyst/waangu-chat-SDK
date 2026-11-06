import SwiftUI
import AVFoundation
import WaanguCoreKit

struct VideoThumbnailViewComponent: View {
    let url: URL?
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let borderWidth: CGFloat
    let borderColor: Color
    let contentMode: ContentMode
    let placeholder: Image?
    
    @State private var thumbnail: UIImage?
    @State private var isLoading: Bool = false
    
    init(
        url: URL?,
        width: CGFloat = 100,
        height: CGFloat = 100,
        cornerRadius: CGFloat = 8,
        borderWidth: CGFloat = 0,
        borderColor: Color = .gray,
        contentMode: ContentMode = .fill,
        placeholder: Image? = Image(systemName: "video.fill")
    ) {
        self.url = url
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.contentMode = contentMode
        self.placeholder = placeholder
    }
    
    var body: some View {
        ZStack {
            if isLoading {
                ZStack {
                    AnimatedSpinner(StrokeColor: .white,lineWidth: 2,size: width / 2)
                }.frame(width: width,height: height).background(.black.opacity(0.4)).cornerRadius(cornerRadius)
            } else if let image = thumbnail {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .frame(width: width, height: height)
                    .cornerRadius(cornerRadius)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth))
                
            } else {
                placeholder?
                    .resizable()
                    .scaledToFit()
                    .frame(width: width * 0.6, height: height * 0.6)
                    .foregroundColor(.gray)
                    .background(Color.black.opacity(0.2))
                    .frame(width: width, height: height)
                    .cornerRadius(cornerRadius)
            }
        }
        .onAppear {
            generateThumbnail()
        }
        .frame(width: width, height: height)
    }
    
    private func generateThumbnail() {
        guard let url = url else { return }
        isLoading = true
        
        DispatchQueue.global(qos: .background).async {
            let asset = AVAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            let time = CMTime(seconds: 1, preferredTimescale: 60)
            
            do {
                let cgImage = try imageGenerator.copyCGImage(at: time, actualTime: nil)
                let uiImage = UIImage(cgImage: cgImage)
                
                DispatchQueue.main.async {
                    self.thumbnail = uiImage
                    self.isLoading = false
                }
            } catch {
                debugLog("❌ Failed to generate thumbnail: \(error)")
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

//#Preview {
//    VideoThumbnailViewComponent(
//        url: URL(string: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"),
//        width: 250,
//        height: 250,
//        cornerRadius: 200
//    )
//}
