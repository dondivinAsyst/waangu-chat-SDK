//
//  ChatEncryptionClaim.swift
//  FeatureChat
//
//  B61 — ce que l'app a le droit d'affirmer sur le chiffrement.
//

/// L'app n'affirme « chiffré de bout en bout » que si c'est vrai.
///
/// Aujourd'hui les messages partent en clair : `ChatRoomView` crée la salle sans
/// les cas d'usage E2EE (« Temporarily disabled »), donc `ChatRoomE2EECoordinator`
/// n'est jamais construit, et le serveur renvoie le texte en clair. Afficher
/// « Your personal messages are end-to-end encrypted » serait une fausse
/// garantie de sécurité (Bloc 7 §22).
///
/// Passer à `true` seulement quand un message capturé côté serveur est un
/// chiffré — toutes les mentions (pied de la liste, en-tête des groupes, infos
/// du groupe, appel entrant, message système `ENCRYPTION_ENABLED`) reviennent.
enum ChatEncryptionClaim {
    static let messagesAreEndToEndEncrypted = false
}
