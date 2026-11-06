import PDFKit
import WaanguSharedUI
import SwiftUI

/// Classifies a document attachment for adaptive bubble and list presentation.
enum DocumentPresentationKind: Equatable {
    case pdf
    case image
    case video
    case audio
    case spreadsheet
    case presentation
    case word
    case archive
    case text
    case other

    /// Only PDF uses a rich in-bubble preview. Images/videos sent as files stay compact.
    var usesRichPreview: Bool {
        self == .pdf
    }

    static func from(fileName: String?, mimeType: String? = nil) -> DocumentPresentationKind {
        let ext = extensionFrom(fileName: fileName, mimeType: mimeType)
        switch ext {
        case "pdf":
            return .pdf
        case "jpg", "jpeg", "png", "heic", "heif", "webp", "gif", "bmp", "tiff", "tif":
            return .image
        case "mp4", "mov", "m4v", "avi", "3gp", "mkv", "webm":
            return .video
        case "mp3", "wav", "aac", "m4a", "ogg", "flac", "wma", "opus":
            return .audio
        case "xls", "xlsx", "csv", "numbers":
            return .spreadsheet
        case "ppt", "pptx", "key":
            return .presentation
        case "doc", "docx", "pages", "rtf":
            return .word
        case "zip", "rar", "7z", "tar", "gz":
            return .archive
        case "txt", "md", "json", "xml":
            return .text
        default:
            return .other
        }
    }

    var systemImageName: String {
        switch self {
        case .pdf: return "doc.fill"
        case .image: return "photo.fill"
        case .video: return "video.fill"
        case .audio: return "music.note"
        case .spreadsheet: return "tablecells.fill"
        case .presentation: return "rectangle.fill.on.rectangle.fill"
        case .word: return "doc.text.fill"
        case .archive: return "doc.zipper"
        case .text: return "doc.plaintext.fill"
        case .other: return "doc.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .pdf: return .red
        case .image: return .blue
        case .video: return .purple
        case .audio: return .pink
        case .spreadsheet: return .green
        case .presentation: return .orange
        case .word: return .blue
        case .archive: return .gray
        case .text: return .secondary
        case .other: return .gray
        }
    }

    func metadataLine(
        fileName: String?,
        fileURL: URL?,
        sizeBytes: Int?,
        pagesCount: Int? = nil
    ) -> String {
        let ext = Self.extensionFrom(fileName: fileName, mimeType: nil, fileURL: fileURL).uppercased()
        let sizeText = Self.formattedSize(sizeBytes: sizeBytes)
        let sizeSegment = sizeText.map { "\($0) · \(ext)" } ?? ext

        switch self {
        case .pdf:
            let pages = pagesCount ?? fileURL.flatMap { PDFDocument(url: $0)?.pageCount } ?? 0
            if pages > 0 {
                return "\(pages) Pages · \(sizeSegment)"
            }
            return sizeSegment
        case .spreadsheet:
            if let sizeText {
                return "1 sheet · \(sizeText) · \(ext)"
            }
            return "1 sheet · \(ext)"
        default:
            return sizeSegment
        }
    }

    private static func extensionFrom(
        fileName: String?,
        mimeType: String?,
        fileURL: URL? = nil
    ) -> String {
        if let fileName, !fileName.isEmpty {
            let ext = (fileName as NSString).pathExtension.lowercased()
            if !ext.isEmpty { return ext }
        }
        if let fileURL, !fileURL.pathExtension.isEmpty {
            return fileURL.pathExtension.lowercased()
        }
        if let mimeType, let ext = mimeTypeToExtension[mimeType] {
            return ext
        }
        return ""
    }

    private static func formattedSize(sizeBytes: Int?) -> String? {
        guard let sizeBytes, sizeBytes > 0 else { return nil }
        return sizeBytes.formattedFileSize()
    }

    private static let mimeTypeToExtension: [String: String] = [
        "application/pdf": "pdf",
        "image/jpeg": "jpg",
        "image/png": "png",
        "video/mp4": "mp4",
        "video/quicktime": "mov",
        "audio/mpeg": "mp3",
        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet": "xlsx",
        "application/vnd.ms-excel": "xls",
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document": "docx",
        "application/msword": "doc",
        "application/vnd.openxmlformats-officedocument.presentationml.presentation": "pptx",
        "application/vnd.ms-powerpoint": "ppt",
        "application/zip": "zip",
        "text/plain": "txt",
    ]
}
