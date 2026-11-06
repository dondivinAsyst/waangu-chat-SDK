import Foundation

class FileUploadMapper {
    private let dateFormatter: ISO8601DateFormatter
    
    init() {
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }
    
    // MARK: - Response to Domain
    func toDomain(from response: PresignedURLResponse) -> PresignedUpload {
        guard response.isSuccess, let data = response.data else {
            return PresignedUpload(uploadId: "", key: "", totalParts: 0, parts: [])
        }

        let parts = data.parts.map { part in
            PresignedURLPart(
                partNumber: part.partNumber,
                uploadUrl: part.uploadUrl,
                contentLength: part.contentLength,
                start: part.start,
                end: part.end,
                expiresInSeconds: part.expiresInSeconds
            )
        }

        return PresignedUpload(
            uploadId: data.uploadId,
            key: data.key,
            totalParts: data.parts.count,
            parts: parts
        )
    }

    
    // MARK: - Domain to Request
    func toPresignedURLRequest(from fileUploadRequest: FileUploadRequest) -> PresignedURLRequest {
      
      return  PresignedURLRequest(from: fileUploadRequest)
    }
    
    func toUploadCompleteRequest(from CompleteMultiPartUpload: CompleteMultipartUpload) -> CompleteFileUploadRequest {
      
      return  CompleteFileUploadRequest(from: CompleteMultiPartUpload)
    }
    
  
    
    // MARK: - Utilities
    func getMimeType(for fileType: String) -> String {
        switch fileType {
        case "image":
            return "image/jpeg"
        case "document":
            return "application/pdf"
        case "video":
            return "video/mp4"
        case "audio":
            return "audio/mpeg"
        default:
            return "application/octet-stream"
        }
    }
    
    func validateFileSize(_ size: Int, maxSize: Int = 10 * 1024 * 1024) -> Bool {
        return size <= maxSize
    }
    
    func generateFileName(originalName: String, userId: String? = nil) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        let uuid = UUID().uuidString.prefix(8)
        
        if let userId = userId {
            return "\(userId)_\(timestamp)_\(uuid)_\(originalName)"
        } else {
            return "\(timestamp)_\(uuid)_\(originalName)"
        }
    }
}
