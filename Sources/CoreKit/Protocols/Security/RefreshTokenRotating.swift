//
//  RefreshTokenRotating.swift
//  CoreKit
//
//  Bloc 9, §9 (ch. 71) — rotation, détection de réutilisation, révocation de famille.
//

import Foundation

/// Couple de jetons issu d'une rotation.
public struct RotatedTokens: Sendable, Equatable {

    public let accessToken: String
    public let refreshToken: String

    /// Famille à laquelle appartient ce jeton.
    ///
    /// C'est elle qu'on révoque, pas le jeton seul : un attaquant qui détient
    /// une copie possède un descendant de la même famille, et ne révoquer que
    /// le jeton présenté le laisserait en place.
    public let familyID: String

    public let accessExpiresAt: Date

    public init(accessToken: String, refreshToken: String,
                familyID: String, accessExpiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.familyID = familyID
        self.accessExpiresAt = accessExpiresAt
    }
}

/// Échec de rotation.
public enum TokenRotationError: Error, Sendable, Equatable {

    /// Jeton inconnu de l'autorité.
    case unknownToken

    /// **Réutilisation détectée.** Un jeton déjà échangé est représenté, donc
    /// deux porteurs existent. Toute la famille est révoquée, et la session
    /// doit être refaite depuis l'authentification.
    case reuseDetected(familyID: String)

    /// Famille déjà révoquée.
    case familyRevoked(familyID: String)

    case unreachable
}

/// Fait pivoter un refresh token et détecte sa réutilisation.
///
/// **Autorité serveur.** Le mobile ne peut ni décider qu'un jeton est réutilisé
/// ni révoquer une famille : il ne voit que son propre appareil, et c'est
/// précisément l'autre porteur qu'il s'agit d'attraper.
public protocol RefreshTokenRotating: Sendable {

    /// Échange un refresh token contre un couple neuf.
    func rotate(refreshToken: String) async -> Result<RotatedTokens, TokenRotationError>

    /// Ouvre une famille à l'authentification.
    func startFamily(subject: String) async -> Result<RotatedTokens, TokenRotationError>

    /// Révoque une famille entière — déconnexion globale, incident.
    func revokeFamily(_ familyID: String) async
}

/// Ne pivote rien.
public struct UnavailableTokenRotation: RefreshTokenRotating {
    public init() {}
    public func rotate(refreshToken: String) async -> Result<RotatedTokens, TokenRotationError> {
        .failure(.unreachable)
    }
    public func startFamily(subject: String) async -> Result<RotatedTokens, TokenRotationError> {
        .failure(.unreachable)
    }
    public func revokeFamily(_ familyID: String) async {}
}
