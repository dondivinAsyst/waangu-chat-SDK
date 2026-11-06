// MARK: - NetworkKit/Middlewares/Cache/CacheStoreProtocol.swift

import Foundation


public protocol CacheStoreProtocol: Sendable {
    func cachedResponse(for request: URLRequest) -> CachedURLResponse?
    func storeCachedResponse(_ response: CachedURLResponse, for request: URLRequest)
    func removeCachedResponse(for request: URLRequest)
    func removeAllCachedResponses()
}

/// URLCache conforme via extension — zéro changement dans le code appelant.
extension URLCache: CacheStoreProtocol {
    public func removeAllCachedResponses() {
        removeAllCachedResponses()
    }
}
