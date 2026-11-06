import Foundation

struct PresignedURLRequest: Codable {
    let fileName: String
    let fileType: String
    let fileSize: Int?
    let folder: String
    
    enum CodingKeys: String, CodingKey {
        case fileName = "filename"
        case fileType = "mimeType"
        case fileSize = "size"
        case folder = "location"
    }
    
    init(from fileUploadRequest: FileUploadRequest) {
        self.fileName = fileUploadRequest.fileName
        self.fileType = fileUploadRequest.fileType
        self.fileSize = fileUploadRequest.fileSize
        self.folder = fileUploadRequest.folder
    }
}

