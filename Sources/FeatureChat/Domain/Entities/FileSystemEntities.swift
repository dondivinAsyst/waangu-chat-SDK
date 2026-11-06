import Photos

// MARK: - Media Type

public enum MediaType: String, Codable {
    case image
    case video
//    case audio
//    case document
}

public struct MediaAssetUI: Identifiable {
    public  let id: String
    public  let phAsset: PHAsset
    public let type: MediaType
    public  let creationDate: Date
    public  let thumbnailBase64: String?
}


public struct MediaMetadata {
    let mimeType: String
    let fileExtension: String

    static func from(uti: String?, data: Data) -> MediaMetadata {

        let map: [String: String] = [
            "public.jpeg": "image/jpeg",
            "public.png": "image/png",
            "public.heic": "image/heic",
            "public.heif": "image/heif",
            "com.compuserve.gif": "image/gif",
            "public.mpeg-4": "video/mp4",
            "public.avi": "video/avi",
            "com.apple.quicktime-movie": "video/quicktime",
            "public.movie": "video/mp4",
            "public.3gpp": "video/3gpp",
            "public.mpeg": "video/mpeg",
        ]

        let extMap: [String: String] = [
            "video/quicktime": "mov",
            "video/3gpp": "3gp",
        ]

        let mime = map[uti ?? ""] ?? "application/octet-stream"
        let ext = extMap[mime] ?? mime.components(separatedBy: "/").last ?? "bin"

        return MediaMetadata(
            mimeType: mime,
            fileExtension: ext
        )
    }
}

public struct MediaAlbum:Identifiable {
    public let id: String
    public let title: String
    public let count: Int
    public let collection: PHAssetCollection
}

public struct MediaAsset {
    public let id: String
    public let asset: PHAsset
    public let creationDate: Date
    public let type: MediaType
    public let fileSizeBytes: Int
}

public struct MediaFile {
    public let uri: String
    public let fileName: String
    public let sizeKb: Int
    public let mimeType: String
    public let type: MediaType
}
