// MARK: - NetworkKit/APIClient/URLRequest+Endpoint.swift
//
// Extension pour associer un APIEndpoint à une URLRequest via objc_setAssociatedObject.
// Utilisé par CacheMiddleware pour récupérer les policies depuis la request.

import Foundation

private var endpointAssociationKey: UInt8 = 0

extension URLRequest {

    /// Endpoint associé à cette requête.
    /// Stocké via associated objects pour traverser le pipeline de middlewares
    /// sans modifier la signature de URLRequest.
    var endpoint: Any? {
        get { objc_getAssociatedObject(self, &endpointAssociationKey) }
        set { objc_setAssociatedObject(self, &endpointAssociationKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}
