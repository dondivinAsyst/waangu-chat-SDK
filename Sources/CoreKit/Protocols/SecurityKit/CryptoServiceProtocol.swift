import Foundation

public protocol CryptoServiceProtocol: Sendable {
    func encrypt(_ text: String) async throws -> Data
    func decrypt(_ data: Data) async throws -> String
}