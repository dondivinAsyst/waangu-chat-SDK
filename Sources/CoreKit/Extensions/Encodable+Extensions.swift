//
//  Encodable+Extensions.swift
//  AppModules
//
//  Created by Asyst on 3/23/26.
//

import Foundation

public extension Encodable {

    /// Convertit un `Encodable` en dictionnaire `[String: Any]`.
    /// Utile pour construire des payloads dynamiques ou des logs.
    func toDictionary() throws -> [String: Any] {
        let data = try JSONEncoder().encode(self)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw EncodingError.invalidValue(
                self,
                .init(codingPath: [], debugDescription: "Impossible de convertir en [String: Any]")
            )
        }
        return dictionary
    }

    /// Convertit un `Encodable` en Data JSON.
    /// Raccourci pour éviter la création répétée d'un JSONEncoder.
    func toJSONData(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(self)
    }
}
