import Foundation

struct CompleteFileUploadRequest: Codable {
       let key: String
       let uploadId: String
       let parts: [CompletedPart]
    
    enum CodingKeys: String, CodingKey {
        case key
        case uploadId
        case parts
    }
    
    init(from CompleteMultiParts: CompleteMultipartUpload) {
        self.key = CompleteMultiParts.key
        self.uploadId = CompleteMultiParts.uploadId
        self.parts = CompleteMultiParts.parts
    }
}

