import Foundation

public struct PresignedURLResponse: Codable {
    let statusCode: Int?
    let message: String?
    let data: PresignedURLData?

    var isSuccess: Bool {
        if let statusCode { return statusCode >= 200 && statusCode < 300 }
        return data != nil
    }
}

public struct PresignedURLData: Codable {
    let uploadId: String
    let key: String
    let filename: String?
    let location: String?
    let tenantId: String?
    let parts: [PresignedURLPart]
    let expiresInSeconds: Int?
}

public struct PresignedURLPart: Codable, Equatable {
    let partNumber: Int
    let uploadUrl: String
    let contentLength: Int
    let start: Int
    let end: Int
    let expiresInSeconds: Int?
}

public struct PresignedUpload: Codable, Equatable {
    let uploadId: String
    let key: String
    let totalParts: Int
    let parts: [PresignedURLPart]
}
public struct CompleteMultipartUpload: Codable {
    let key: String
    let uploadId: String
    let parts: [CompletedPart]
}

public struct CompletedPart: Codable {
    let etag: String
    let partNumber: Int
}
//public struct CompleteUploadResponse : Codable {
//    let status: Int
//    let message: String?
//    let data: completeDataResponseData?
//    
//    var isSuccess: Bool {
//        status >= 200 && status < 300
//    }
//}
//public struct completeDataResponseData: Codable {
//    let fileUrl: String?
//}
public struct CompleteUploadResponse: Codable {
    let message: String?
    let statusCode: Int?
    let data: CompleteUploadData?

    var isSuccess: Bool {
        guard let statusCode else { return false }
        return statusCode >= 200 && statusCode < 300
    }
}

public struct CompleteUploadData: Codable {
    let key: String?
    let downloadUrl: String?
    let downloadUrlExpiresInSeconds: Int?
}


//struct PresignedURLData: Codable {
//    let url: String
//    let fileUrl: String
//    let expiresAt: String?
//    
//    enum CodingKeys: String, CodingKey {
//        case url
//        case fileUrl = "file_url"
//        case expiresAt = "expires_at"
//    }
//}


// 1️⃣ Generic JSON enum to decode any type
public enum JSONValue: Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([JSONValue])
    case dictionary([String: JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int.self) { self = .int(value) }
        else if let value = try? container.decode(Double.self) { self = .double(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .dictionary(value) }
        else if let value = try? container.decode([JSONValue].self) { self = .array(value) }
        else { throw DecodingError.typeMismatch(JSONValue.self, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unknown JSON type")) }
    }

    public  func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dictionary(let d): try container.encode(d)
        case .null: try container.encodeNil()
        }
    }
}

// 2️⃣ API Response using JSONValue
public struct APIResponse: Codable {
    let status: Int
    let message: String
    let data: JSONValue?

    var isSuccess: Bool { status >= 200 && status < 300 }

    public init(status: Int, message: String, data: JSONValue? = nil) {
        self.status = status
        self.message = message
        self.data = data
    }

    /// Used when the chat-core stories API returns the resource body directly (no envelope).
    public static func success(message: String = "OK", data: JSONValue? = nil) -> APIResponse {
        APIResponse(status: 200, message: message, data: data)
    }
}
public struct APIContactResponse: Codable {
    let status: Int
    let message: String
    let data: [ContactResponse]?

    var isSuccess: Bool { status >= 200 && status < 300 }
}


