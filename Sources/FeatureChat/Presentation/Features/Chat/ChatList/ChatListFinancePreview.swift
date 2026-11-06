//
//  ChatListFinancePreview.swift
//  FeatureChat
//
//  L'aperçu d'une opération financière dans la liste des conversations.
//

import WaanguCoreKit

/// Ce qu'une ligne de conversation affiche quand le dernier message est une
/// opération financière : sa nature et son montant.
///
/// Un message financier n'a pas de texte. La ligne tombait donc sur son cas par
/// défaut et n'affichait rien — seule l'icône de livraison restait, comme si le
/// fil était vide.
///
/// Le montant n'apparaît que si la carte est reconstruite depuis le serveur :
/// une référence seule, encore en attente, n'en porte aucun, et en inventer un
/// afficherait un chiffre que personne n'a validé.
struct ChatListFinancePreview: Equatable {

    /// Clé de traduction de la nature de l'opération.
    let titleKey: String
    let systemImage: String
    /// Montant déjà formaté, ou `nil` tant que la carte est en attente.
    let amount: String?

    init(message: MessageDataItem) {
        let payload = message.message.financial
        switch payload?.reference.type {
        case .moneyRequest:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_MONEY_REQUEST
            systemImage = "hand.raised.fill"
        case .splitBill:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_SPLIT_BILL
            systemImage = "person.2.fill"
        case .bill:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_BILL
            systemImage = "doc.text.fill"
        case .airtime, .dataBundle:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_RECHARGE
            systemImage = "iphone"
        case .refund:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_REFUND
            systemImage = "arrow.uturn.backward.circle.fill"
        case .dispute:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_DISPUTE
            systemImage = "exclamationmark.bubble.fill"
        case .fxQuote:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_FX_QUOTE
            systemImage = "arrow.left.arrow.right.circle.fill"
        // Paiement et ce qui s'y apparente — marchand, dépôt, retrait, envoi
        // international… — et la carte encore en attente, dont la nature n'est
        // pas connue localement : un message financier sans projection est
        // d'abord un paiement annoncé.
        default:
            titleKey = ChatTranslationKeys.MEDIA_TYPE_PAYMENT
            systemImage = "banknote.fill"
        }
        amount = payload?.formattedAmount
    }

    /// « Paiement · 50 000 BIF », ou la nature seule sans montant connu.
    func subtitle(translate: (String) -> String) -> String {
        let title = translate(titleKey)
        guard let amount else { return title }
        return "\(title) · \(amount)"
    }
}
