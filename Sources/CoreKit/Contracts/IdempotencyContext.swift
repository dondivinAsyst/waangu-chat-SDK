//
//  IdempotencyContext.swift
//  CoreKit
//
//  Identité d'une opération financière à travers tous ses retries.
//
//  Voir BLOC1-CHAT-FINANCE-INTEGRATION.md §3.3.

import Foundation

/// Contexte d'idempotence d'une opération sensible.
///
/// La règle tient en une phrase : **la clé est écrite une fois, à la création de
/// l'intention, et ne change jamais** — ni au retry, ni à la reconnexion, ni après
/// un kill de l'application. Un `UUID()` régénéré à chaque tentative transforme un
/// retry en second paiement.
///
/// C'est pourquoi ce type est `Codable` : il doit survivre au disque. Un contexte
/// qui ne vit qu'en mémoire ne protège pas du cas qu'il est censé couvrir.
public struct IdempotencyContext: Codable, Sendable, Hashable {

    /// Clé transmise au backend. Immuable pour toute la durée de vie de l'opération.
    public let key: String

    /// Identifie la tentative côté client, indépendamment de la clé.
    ///
    /// Distincte de `key` à dessein : elle permet de tracer *quelle* tentative a
    /// produit une réponse donnée, sans jamais servir d'identité d'opération.
    public let clientRequestID: UUID

    /// Corrèle l'opération à travers les services.
    public let correlationID: CorrelationId

    /// Lie l'opération à l'appareil qui l'a initiée.
    ///
    /// Le backend s'en sert pour distinguer un retry légitime du même appareil
    /// d'une tentative concurrente depuis un second appareil.
    public let deviceID: String

    /// Instant de création de la clé — pas de la tentative courante.
    ///
    /// Permet de détecter une clé rejouée bien au-delà de la fenêtre de rétention
    /// backend, cas où le retry doit être refusé plutôt que tenté.
    public let createdAt: Date

    public init(
        key: String,
        clientRequestID: UUID,
        correlationID: CorrelationId,
        deviceID: String,
        createdAt: Date = Date()
    ) {
        self.key = key
        self.clientRequestID = clientRequestID
        self.correlationID = correlationID
        self.deviceID = deviceID
        self.createdAt = createdAt
    }
}

// MARK: - Création

public extension IdempotencyContext {

    /// Crée le contexte d'une **nouvelle** opération.
    ///
    /// À n'appeler qu'une fois par intention utilisateur. Tout retry réutilise le
    /// contexte persisté — voir `IdempotencyKeyPreserving`.
    ///
    /// La clé dérive de l'appareil et d'un UUID afin que deux appareils ne
    /// puissent pas produire la même clé pour deux opérations distinctes.
    static func new(
        deviceID: String,
        correlationID: CorrelationId = CorrelationId()
    ) -> IdempotencyContext {
        let requestID = UUID()
        return IdempotencyContext(
            key: "\(deviceID)-\(requestID.uuidString)",
            clientRequestID: requestID,
            correlationID: correlationID,
            deviceID: deviceID
        )
    }

    /// Prépare la tentative suivante de la **même** opération.
    ///
    /// `key`, `correlationID`, `deviceID` et `createdAt` sont conservés à
    /// l'identique ; seul `clientRequestID` change, pour que les tentatives
    /// restent distinguables en observabilité.
    ///
    /// Il n'existe volontairement aucune API capable de modifier `key`.
    func nextAttempt() -> IdempotencyContext {
        IdempotencyContext(
            key: key,
            clientRequestID: UUID(),
            correlationID: correlationID,
            deviceID: deviceID,
            createdAt: createdAt
        )
    }

    /// Âge de la clé. Au-delà de la fenêtre de rétention backend, un rejeu n'est
    /// plus garanti idempotent et doit être refusé, pas retenté.
    func age(asOf now: Date = Date()) -> TimeInterval {
        now.timeIntervalSince(createdAt)
    }

    /// En-tête HTTP standard porteur de la clé.
    static let headerName = "Idempotency-Key"
}
