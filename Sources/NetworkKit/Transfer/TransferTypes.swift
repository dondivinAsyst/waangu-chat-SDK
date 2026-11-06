// MARK: - NetworkKit/Transfer/TransferPriority.swift

import Foundation

public enum TransferPriority: Int, Comparable, Sendable {
    case low    = 0
    case medium = 1
    case high   = 2

    public static func < (lhs: TransferPriority, rhs: TransferPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

// MARK: - NetworkKit/Transfer/TransferState.swift

public enum TransferState: String, Codable, Sendable {
    case pending
    case running
    case paused
    case completed
    case failed
    case cancelled
}

// MARK: - NetworkKit/Transfer/FileTransferTask.swift

public protocol FileTransferTask: AnyObject {
    var id: UUID { get }
    func cancel()
    func pause()
    func resume()
}

// MARK: - NetworkKit/Transfer/FileTransferProtocol.swift

public protocol FileTransferProtocol: AnyObject {

    @discardableResult
    func upload(
        fileURL: URL,
        request: URLRequest,
        priority: TransferPriority,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<URLResponse, Error>) -> Void
    ) -> any FileTransferTask

    @discardableResult
    func download(
        request: URLRequest,
        destinationURL: URL,
        priority: TransferPriority,
        onProgress: @escaping (Double) -> Void,
        onCompletion: @escaping (Result<URL, Error>) -> Void
    ) -> any FileTransferTask

    func cancelAll()
}
