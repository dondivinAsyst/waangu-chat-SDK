//
//  JWTValidator.swift
//  AppModules
//
//  Created by Asyst on 3/24/26.
//

import Foundation

// MARK: - JWTValidatorProtocol

public protocol JWTValidatorProtocol: Sendable {
    /// `true` si le token est structurellement valide ET non expiré.
    func isValid(token: String) -> Bool

    /// Décode le payload (segment 1) du JWT sans vérification de signature.
    func decodePayload(_ token: String) -> [String: Any]?
}

// MARK: - JWTValidator

/// Validation et décodage de tokens JWT (header.payload.signature).
///
/// Décode le payload via base64url — ne vérifie PAS la signature
/// (la vérification cryptographique est du ressort du backend).
/// Utilisé côté client pour :
///   - Vérifier l'expiration (`exp`) avant un appel réseau
///   - Extraire des claims (userId, rôles, etc.)
public struct JWTValidator: JWTValidatorProtocol {

    public init() {}

    public func isValid(token: String) -> Bool {
        guard !token.isEmpty,
              let payload = decodePayload(token),
              let exp = payload["exp"] as? TimeInterval
        else { return false }

        return Date(timeIntervalSince1970: exp) > Date()
    }

    public func decodePayload(_ token: String) -> [String: Any]? {
        let segments = token.split(separator: ".")
        guard segments.count == 3 else { return nil }

        let payloadSegment = String(segments[1])
        guard let data = Data(base64Encoded: base64UrlToBase64(payloadSegment)) else { return nil }

        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    // MARK: - Private

    private func base64UrlToBase64(_ value: String) -> String {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return base64
    }
}
