//
//  CopilotConversationStoring.swift
//  FeatureChat
//
//  La conversation Waangu Copilot, conservée sur l'appareil.
//

import Foundation

/// La conversation de l'utilisateur avec Waangu Copilot — **une seule**, comme
/// celle de Meta AI dans WhatsApp : la liste des discussions la montre, le
/// bouton flottant l'ouvre.
///
/// Sur l'appareil seulement : aucun contrat serveur ne la porte, et son
/// identifiant ne part jamais vers Chat Core. Le contenu est opaque ici —
/// Copilot l'encode, après avoir retiré ce qui ne se garde pas.
protocol CopilotConversationStoring: Sendable {
    /// La conversation existante, ou une nouvelle — après une suppression aussi.
    func conversationID() async throws -> String
    /// Les messages, dans l'ordre.
    func messages(in conversationID: String) async throws -> [Data]
    /// Enregistre un message — ajouté s'il est nouveau, remplacé à sa place
    /// sinon. `preview` : la ligne de la liste d'un nouveau message, `nil` pour
    /// garder la précédente.
    func save(_ payload: Data, messageID: String, preview: String?, to conversationID: String) async throws
    /// Supprime la conversation et son historique.
    func delete(_ conversationID: String) async throws
}
