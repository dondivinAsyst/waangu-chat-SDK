// MARK: - NetworkKit/Transfer/MultipartBuilder.swift

import Foundation

public struct MultipartFile {
    public let name: String
    public let fileName: String
    public let mimeType: String
    public let data: Data

    public init(name: String, fileName: String, mimeType: String, data: Data) {
        self.name = name
        self.fileName = fileName
        self.mimeType = mimeType
        self.data = data
    }

    public static func imageFile(name: String, fileName: String, imageData: Data) -> MultipartFile {
        MultipartFile(name: name, fileName: fileName, mimeType: "image/jpeg", data: imageData)
    }
}

public struct MultipartBuilder {

    public let boundary: String

    public init(boundary: String = UUID().uuidString) {
        self.boundary = boundary
    }

    public func build(parameters: [String: Any]? = nil, files: [MultipartFile]) -> Data {
        var body = Data()

        parameters?.forEach { key, value in
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        files.forEach { file in
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(file.name)\"; filename=\"\(file.fileName)\"\r\n")
            body.append("Content-Type: \(file.mimeType)\r\n\r\n")
            body.append(file.data)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        return body
    }
}
