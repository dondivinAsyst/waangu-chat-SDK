// FeatureChat/Public/Navigation/ChatRoute.swift

import WaanguNavigationKit

public enum ChatRoute: StackRoute {
    case chats
    case updates
    case communities
    case calls
    case settings
    case share

    /// Une conversation précise.
    ///
    /// Manquait au type, ce qui rendait le lien profond
    /// `waangu://chat/conversation/{id}` inopérant : l'identifiant était analysé,
    /// porté par l'intention, puis **abandonné** par le résolveur, qui ouvrait la
    /// liste. Un lien vers une conversation ouvrait donc l'inbox, et une
    /// notification poussée désignant un message aussi.
    case conversation(id: String)

    /// Un objet financier désigné par un push : type et identifiant opaque,
    /// rien d'autre. Le type est gardé en texte brut, tel que reçu ; c'est le
    /// Chat qui le valide avant toute lecture serveur.
    case financialObject(opaqueId: String, objectType: String)

    /// Un lien de paiement reçu (`waangu://chat/pay-link?token=…&nonce=…`).
    /// Jeton et nonce seulement : le Chat l'inspecte au serveur.
    case paymentLink(token: String, nonce: String)
    
    /// A channel invitation from a shareable link (`waangu://chat/channel/invite/{inviteCode}`).
    /// Only the invite code transits - the Chat validates it with the server
    /// and shows a preview before allowing subscription.
    case channelInvite(inviteCode: String)
    
    /// Direct navigation to a channel by ID (`waangu://chat/channel/{channelId}`).
    /// Used for deep links from notifications or other app sections.
    case channel(channelId: String)
}
