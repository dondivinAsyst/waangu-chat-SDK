//
//  DirectDiscussionFinder.swift
//  FeatureChat
//
//  Le fil individuel qu'on a déjà avec quelqu'un, retrouvé par son numéro.
//

import Foundation

/// Retrouve la conversation individuelle existante avec un numéro.
///
/// Un numéro écrit de deux façons reste le même numéro : le répertoire porte
/// les espaces du carnet d'adresses, le serveur sa propre forme. Comparer les
/// chaînes brutes rate sur l'espacement seul — et fabrique alors un second fil
/// avec quelqu'un qu'on connaît déjà.
///
/// La liste lue inclut les discussions archivées : c'est l'écran de liste qui
/// les sépare ensuite, et un fil archivé reste le fil de cette personne.
///
/// **À ne pas confondre avec `DirectConversationLookup`** (synchronisation),
/// qui ne retrouve que les fils *non liés* au serveur, pour éviter qu'une
/// synchronisation crée un doublon. Ici on veut au contraire n'importe quel fil
/// existant, lié ou non : s'en tenir aux fils non liés ferait créer une
/// seconde conversation avec quelqu'un qu'on connaît déjà.
struct DirectDiscussionFinder {

    let discussions: any DiscussionUseCasesProtocol

    /// `nil` quand il n'y a pas encore de fil — une première conversation.
    func conversationId(forPhone phone: String) async throws -> String? {
        let all = try await discussions.getDiscussions.execute() ?? []
        return Self.match(phone: phone, in: all)?.conversationId
    }

    /// Par l'utilisateur d'abord, puis par le numéro. L'utilisateur est le même
    /// quel que soit le format du numéro : avec ou sans indicatif, les chiffres
    /// diffèrent, et un fil existant passerait pour une première conversation.
    func conversationId(forUserId userId: String, phone: String) async throws -> String? {
        let all = try await discussions.getDiscussions.execute() ?? []
        return Self.match(userId: userId, phone: phone, in: all)?.conversationId
    }

    static func match(userId: String, phone: String, in discussions: [DiscussionChatItem]) -> DiscussionChatItem? {
        if !userId.isEmpty,
           let byUser = discussions.first(where: { $0.contact?.isGroup == false && $0.contact?.userId == userId }) {
            return byUser
        }
        return match(phone: phone, in: discussions)
    }

    static func match(phone: String, in discussions: [DiscussionChatItem]) -> DiscussionChatItem? {
        let digits = phone.filter(\.isWholeNumber)
        guard !digits.isEmpty else { return nil }
        return discussions.first {
            $0.contact?.isGroup == false && $0.contact?.phone.filter(\.isWholeNumber) == digits
        }
    }
}

extension ContactChannel {

    /// Le contact d'une discussion individuelle, à partir d'un contact connu.
    static func direct(_ contact: UserContactProps) -> ContactChannel {
        ContactChannel(
            userName: contact.name,
            phone: contact.phone,
            image: contact.avatar,
            isBlocked: contact.isBlocked,
            isGroup: false,
            isChannel: false,
            id: contact.idContact ?? "",
            userId: contact.userId
        )
    }
}
