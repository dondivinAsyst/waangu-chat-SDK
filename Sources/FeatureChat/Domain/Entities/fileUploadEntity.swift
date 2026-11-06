
import Foundation

struct PresignedURL: Equatable, Codable {
    let url: String
    let fileUrl: String
    let expiresAt: Date?
    
    init(url: String, fileUrl: String, expiresAt: Date? = nil) {
        self.url = url
        self.fileUrl = fileUrl
        self.expiresAt = expiresAt
    }
}

public struct FileUploadRequest: Equatable {
    public enum Folder: String, Codable, Equatable {
        case story
        case message
        case profilePicture
        case chatFile
        case userDocuments
    }

    let fileName: String
    let fileType: String
    let fileSize: Int?
    let folder: String
    
    public  init(
        fileName: String,
        fileType: String,
        fileSize: Int? = nil,
        folder: Folder
    ) {
        self.fileName = fileName
        self.fileType = fileType
        self.fileSize = fileSize
        self.folder = folder.rawValue
    }
}


enum UploadFileType: String, CaseIterable {
    case image = "image"
    case document = "document"
    case video = "video"
    case audio = "audio"
    
    var allowedExtensions: [String] {
        switch self {
        case .image:
            return ["jpg", "jpeg", "png", "gif", "webp"]
        case .document:
            return ["pdf", "doc", "docx", "txt", "xlsx"]
        case .video:
            return ["mp4", "mov", "avi", "mkv"]
        case .audio:
            return ["mp3", "wav", "m4a", "aac"]
        }
    }
    
    var mimeType: String {
        switch self {
        case .image: return "image/jpeg"
        case .document: return "application/pdf"
        case .video: return "video/mp4"
        case .audio: return "audio/mpeg"
        }
    }
}
