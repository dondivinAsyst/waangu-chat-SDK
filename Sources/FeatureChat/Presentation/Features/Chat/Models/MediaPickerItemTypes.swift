//
//  MediaPickerItemTypes.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 22.01.2025.
//

import SwiftUI

//struct VideoPickerTransferable: Transferable {
//    let url: URL
//    
//    static var transferRepresentation: some TransferRepresentation {
//        FileRepresentation(contentType: .movie) { exportingFile in
//            return .init(exportingFile.url)
//        } importing: { receivedTransferredFile in
//            let originalURL = receivedTransferredFile.file
//            let uniqueFileName = "\(UUID().uuidString).mov"
//            let copiedFile = URL.documentsDirectory.appendingPathComponent(uniqueFileName)
//            try FileManager.default.copyItem(at: originalURL, to: copiedFile)
//            return .init(url: copiedFile)
//        }
//    }
//}

public struct MediaAttachment: Identifiable {
  public  let id: String
   public let type: MediaAttachmentType
    
    public var thumbnail: UIImage {
        switch type {
        case .photo(let thumbnail):
            return thumbnail
        case .video(let thumbnail, _):
            return thumbnail
        case .audio:
            return UIImage()
        }
    }
    
    public  var fileURL: URL? {
        switch type {
            case .photo:
                return nil
            case .video(_, let fileURL):
                return fileURL
            case .audio(let voiceURL, _, _):
                return voiceURL
        }
    }
    
    public  var audioDuration: TimeInterval? {
        switch type {
        case .audio(_, let duration, _):
            return duration
        default:
            return nil
        }
    }
    
    public var waveform: [Float]? {
        switch type {
        case .audio(_, _, let waveform):
            return waveform
        default:
            return nil
        }
    }
}

public enum MediaAttachmentType {
    case photo(_ thumbnail: UIImage)
    case video(_ thumbnail: UIImage, _ url: URL)
    case audio(_ url: URL, _ duration: TimeInterval, _ waveform: [Float]? = nil)
    
    public  static func == (lhs: MediaAttachmentType, rhs: MediaAttachmentType) -> Bool {
        switch (lhs, rhs) {
        case (.photo, .photo), (.video, .video), (.audio, .audio):
            return true
            
        default:
            return false
        }
    }
}
