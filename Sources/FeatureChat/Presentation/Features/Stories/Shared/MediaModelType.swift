import SwiftUI
import Photos
import WaanguSharedUI

enum StoryMediaType {
    case none
    case image
    case video
}
struct videoItem: Identifiable, Hashable {
    let id = UUID()
    var url : URL?
    var pHAsset : PHAsset?
    var  startTime : Double?
    var endTime : Double?
}
struct MediaItem: Identifiable,Equatable {
 
let id = UUID()
    var image: UIImage?
    var video: videoItem?
    var type: StoryMediaType = .none
    var PHMedia : GalleryMedia? = nil
    var fileSize : Int
    
    
    
}
struct MediaInfo: Identifiable ,Equatable{
    let id = UUID().uuidString          // stable id
    var media : MediaItem? = nil
//    var image: UIImage? = nil                 // URL string
//    var video: URL? = nil               // URL string
//    var type: StoryMediaType = .none
//    var originalImage: UIImage? = nil               // URL string
    var originalMedia: MediaItem? = nil               // URL string
    var cropSession: MediaCropSession? = nil
    var imageOriginalSize: CGSize?
    var imageRenderedSize : CGSize = .zero
    var imageFilter: ImageFilterType
    var overLayText: String
    var captionText: String
    var selectedTextColor: Color
    var selectedFontIndex : Int
    var currentLine: Line?
    var lines: [Line]
    var drawSelectedColor: Color
    var selectedLineWidth : CGFloat
    
    // Text-position helpers (stored per image)
    var textScale: CGFloat
    var lastScale: CGFloat
    var textOffset: CGSize
    var lastOffset: CGSize
    var textPosition : CGPoint
}
