//
//  DynamicBillerRequestDTO.swift
//  AppModules
//
//  Created by Asyst on 4/14/26.
//

import WaanguCoreKit
import Foundation

struct BillerFormRequestDTO: Codable {
    let billerFormId: String
}

/// Corps prêt pour l’appel réseau `fetchFieldForm` (URL + verbe + body résolu côté domaine).
struct FetchFieldFormRequestDTO: Codable, Sendable {
    let url: String
    let method: String
    let body: [String: String]
}

extension FetchFieldFormRequestDTO {
    var httpMethod: HTTPMethod {
        switch method.uppercased().trimmingCharacters(in: .whitespacesAndNewlines) {
        case "GET": return .get
        case "PUT": return .put
        case "PATCH": return .patch
        case "DELETE": return .delete
        default: return .post
        }
    }
}
