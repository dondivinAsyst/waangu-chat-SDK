//
//  CopilotMessageModel.swift
//  FeatureChat
//
//  Un message de la conversation Waangu Copilot, sur l'appareil.
//

import Foundation
import WaanguCoreKit

/// Un message de la conversation Copilot.
///
/// À part de `MessageModel` : rien ici n'est un message de messagerie — aucun
/// envoi, aucun accusé, aucune synchronisation ne doit jamais le voir. Le
/// contenu, déjà nettoyé par Copilot (devis fermés, code de retrait absent),
/// est chiffré comme les autres champs sensibles du chat.
public struct CopilotMessageModel: Storable {

    public static let namespace = "chat"
    public static let schemaVersion = 1
    public static let indexedFields = ["conversationId"]

    public let id: String
    public let conversationId: String
    /// Ordre dans le fil.
    public let position: Int
    /// Le message encodé par Copilot, chiffré.
    public let payload: String
    public let createdAt: Date

    public init(id: String, conversationId: String, position: Int, payload: String, createdAt: Date) {
        self.id = id
        self.conversationId = conversationId
        self.position = position
        self.payload = payload
        self.createdAt = createdAt
    }
}
