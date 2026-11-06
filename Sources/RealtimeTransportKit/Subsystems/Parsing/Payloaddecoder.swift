//
//  Payloaddecoder.swift
//  AppModules
//
//  Created by Asyst on 6/4/26.
//

// MARK: - RealtimeKit/Parsing/PayloadDecoder.swift
//
// Module  : RealtimeKit (internal)
// Rôle    : Encodage/décodage JSON centralisé pour tous les payloads.
//           Remplace l'implémentation minimale de l'Assembly.
//           Mappe les erreurs Foundation vers RealtimeError.

import Foundation
import WaanguCoreKit

// MARK: - PayloadDecoder (complete implementation)

/// Encodeur/décodeur JSON centralisé.
///
/// Toutes les sérialisations passent par ici — un seul endroit
/// à modifier si le format change (ex: passage à Protobuf).
struct PayloadDecoder: Sendable {

    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    // MARK: - Init

    init(
        dateDecodingStrategy: JSONDecoder.DateDecodingStrategy = .iso8601,
        keyDecodingStrategy: JSONDecoder.KeyDecodingStrategy = .useDefaultKeys
    ) {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = dateDecodingStrategy
        dec.keyDecodingStrategy = keyDecodingStrategy
        dec.allowsJSON5 = false

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = {
            switch dateDecodingStrategy {
            case .iso8601:              return .iso8601
            case .secondsSince1970:     return .secondsSince1970
            case .millisecondsSince1970:return .millisecondsSince1970
            default:                    return .iso8601
            }
        }()
        enc.outputFormatting = []

        self.decoder = dec
        self.encoder = enc
    }

    // MARK: - Decode

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch let decodingError as DecodingError {
            throw RealtimeError.decodingFailed(
                topic: String(describing: T.self),
                underlyingDescription: decodingError.localizedDescription
            )
        }
    }

    // MARK: - Encode

    func encode<T: Encodable>(_ value: T) throws -> Data {
        do {
            return try encoder.encode(value)
        } catch {
            throw RealtimeError.encodingFailed(
                type: String(describing: T.self),
                underlyingDescription: error.localizedDescription
            )
        }
    }

    // MARK: - Validation

    /// Vérifie que le payload est du JSON valide sans le décoder complètement.
    func validate(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data)) != nil
    }
}
