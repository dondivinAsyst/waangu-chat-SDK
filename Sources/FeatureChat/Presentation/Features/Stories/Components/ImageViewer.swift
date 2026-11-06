import SwiftUI
import WaanguSharedUI

struct ImageViewComponent: View {
    let url: URL?
    let isImageDataUrl : Bool
    let width: CGFloat
    let height: CGFloat
    let cornerRadius: CGFloat
    let contentMode: ContentMode
    let shadow: Bool
    let placeholder: Image?
    let name : String
    let borderWidth : CGFloat
    let borderColor : Color
    let isMyStatusEmpty : Bool
    let isFromDisk : Bool
    let imageFromDisk : UIImage?
    let zoomIn : Double
    
    
    init(
        url: URL?,
        isImageDataUrl : Bool = false,
        width: CGFloat = 100,
        height: CGFloat = 100,
        cornerRadius: CGFloat = 100,
        contentMode: ContentMode = .fill,
        shadow: Bool = false,
        placeholder: Image? = Image(systemName: "photo"),
        name : String = "Name",
        borderWidth : CGFloat = 0,
        borderColor : Color = AppColors.primary,
        isMyStatusEmpty : Bool = false,
        isFromDisk : Bool = false,
        imageFromDisk: UIImage? = nil,
        zoomIn: Double = 1
    ) {
        self.url = url
        self.isImageDataUrl = isImageDataUrl
        self.width = width
        self.height = height
        self.cornerRadius = cornerRadius
        self.contentMode = contentMode
        self.shadow = shadow
        self.placeholder = placeholder
        self.name = name
        self.borderWidth = borderWidth
        self.borderColor = borderColor
        self.isMyStatusEmpty  = isMyStatusEmpty
        self.isFromDisk = isFromDisk
        self.imageFromDisk = imageFromDisk
        self.zoomIn = zoomIn
    }
    private var backgroundColor: Color {
          // Generate a deterministic color based on the name
          let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .red, .indigo]
          let index = abs(name.hashValue) % colors.count
          return colors[index]
      }
    private var initial: String {
          String(name.prefix(1)).uppercased()
      }
    
    var body: some View {
        VStack{
            if isFromDisk {
                if let image = imageFromDisk {
                    ZStack {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: contentMode)
                            .frame(
                                   width: isMyStatusEmpty ? width + 30 : width,
                                   height: isMyStatusEmpty ? height + 30 : height
                               )
                            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                            .overlay(
                                RoundedRectangle(cornerRadius: cornerRadius)
                                    .stroke(borderColor, lineWidth: borderWidth)
                            )
                    }
                    .frame(width: width, height: height)
                    .scaleEffect(zoomIn)
                    .clipped()
                    .contentShape(RoundedRectangle(cornerRadius: cornerRadius))

                } else if let url, url.isFileURL {
                    localFileImage(url: url)
                }
              
            }else{
                if url != nil {
                    if self.isImageDataUrl {
                       
                        if let uiImage = imageFromDataURL(url?.absoluteString ?? "") {
                            Image(uiImage: uiImage)
                                .resizable()
                                .aspectRatio(contentMode: contentMode)
                                .frame(width:isMyStatusEmpty ? width + 30 : width, height:isMyStatusEmpty ? height + 30 : height)
                                .cornerRadius(cornerRadius)
                                .scaleEffect(zoomIn)
                                .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
                        }
                    }else {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .empty:
                                ZStack {
                                    AnimatedSpinner(StrokeColor: .white,lineWidth: 2,size: width / 2)
                                }.frame(width: width,height: height).background(.black.opacity(0.4)).cornerRadius(cornerRadius)
                                
                            case .success(let image):
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: contentMode)
                                    .frame(width:isMyStatusEmpty ? width + 30 : width, height:isMyStatusEmpty ? height + 30 : height)
                                    .cornerRadius(cornerRadius)
                                    .scaleEffect(zoomIn)
                //                    .clipped()
                //                    .clipShape(Circle())
                                    .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
                                   
                                
                            case .failure(_):
                                ZStack {
                                    backgroundColor
                                        .frame(width: width, height: height)
                                        .cornerRadius(cornerRadius)
                                    Text(initial)
                                        .font(.system(size: width * 0.4, weight: .bold))
                                    .foregroundColor(.white)}
                //                placeholder?
                //                    .resizable()
                //                    .scaledToFit()
                //                    .frame(width: width, height: height)
                //                    .cornerRadius(cornerRadius)
                //                    .opacity(0.3)
                                
                            @unknown default:
                                ZStack {
                                    backgroundColor
                                        .frame(width: width, height: height)
                                        .cornerRadius(cornerRadius)
                                    Text(initial)
                                        .font(.system(size: width * 0.4, weight: .bold))
                                    .foregroundColor(.white)}
                            }
                        }
                    }
                   
                }else{
                    Image.custom("waangu")
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width:isMyStatusEmpty ? width + 30 : width, height: isMyStatusEmpty ? height + 30 : height)
                        .cornerRadius(cornerRadius)
                        .background(.white)
                            .clipped()
                            .clipShape(Circle())
                        .overlay(Circle().stroke(borderColor, lineWidth: borderWidth))
                }
            }
        }.frame(width: width,height: height) .clipShape(RoundedRectangle(cornerRadius: cornerRadius))   // clip content
            .shadow(color: .black.opacity(0.2), radius: 6)
  
    
       
    }

    @ViewBuilder
    private func localFileImage(url: URL) -> some View {
        if let data = try? Data(contentsOf: url),
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: contentMode)
                .frame(width: isMyStatusEmpty ? width + 30 : width, height: isMyStatusEmpty ? height + 30 : height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(borderColor, lineWidth: borderWidth)
                )
                .scaleEffect(zoomIn)
        }
    }
}

