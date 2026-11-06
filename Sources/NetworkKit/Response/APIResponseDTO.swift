// MARK: - NetworkKit/Response/APIResponseDTO.swift

import Foundation

/// Enveloppe générique des réponses API du backend Waangu.
///
/// Format JSON attendu :
/// ```json
/// { "err": 200, "message": "OK", "data": { ... } }
/// ```
///
/// `T` est le type métier décodé depuis le champ `data`.
/// Quand le backend ne renvoie pas de data, utiliser `EmptyDTO`.
public struct APIResponseDTO<T: Codable>: Codable, Sendable where T: Sendable {
    public let err: Int
    public let message: String
    public let data: T?

    public init(err: Int, message: String, data: T?) {
        self.err = err
        self.message = message
        self.data = data
    }
}

/// Placeholder pour les réponses sans champ `data`.
public struct EmptyDTO: Codable, Sendable {
    public init() {}
}

/// Alternate envelope used by some backends (e.g. Doctor service).
/// Format JSON expected:
/// ```json
/// { "statusCode": 200, "message": "OK", "data": { ... } }
/// ```
///
/// This type is intentionally added separately so existing code relying on
/// `APIResponseDTO` is not changed. Use `StatusAPIResponseDTO<T>` in features
/// that talk to backends returning `statusCode` instead of `err`.
public struct StatusAPIResponseDTO<T: Codable>: Codable, Sendable where T: Sendable {
    public let statusCode: Int?
    public let message: String?
    public let data: T?

    public init(statusCode: Int? = nil, message: String? = nil, data: T? = nil) {
        self.statusCode = statusCode
        self.message = message
        self.data = data
    }
}
