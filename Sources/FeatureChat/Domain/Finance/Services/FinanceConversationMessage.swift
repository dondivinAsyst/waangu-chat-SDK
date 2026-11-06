import WaanguCoreKit

/// Adapts an already-submitted operation to the existing chat message model.
/// A missing server projection stays missing: the registry renders its pending card.
/// Shared by sending money and requesting money; never executes either operation.
enum FinanceConversationMessage {
    /// - Parameter note: le motif saisi par l'émetteur — « pour le déjeuner ».
    ///
    /// Il voyage comme **le texte du message**, pas comme une donnée de
    /// l'opération : il dit au destinataire à quoi sert l'argent, et le contrat
    /// de paiement n'a pas de champ pour cela. Posé ici, il part sur le fil
    /// (`content.text`) et s'affiche sous la carte, comme la légende d'une photo.
    static func make(reference: FinancialReference, note: String? = nil,
                     payload: FinancialCardPayload?,
                     groupID: String?, receiverID: String) -> MessageDataItem {
        let matching = payload.flatMap {
            $0.reference.id == reference.id && $0.reference.type == reference.type ? $0 : nil
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var message = OutgoingMessageBuilder.buildOutgoingMessage(
            content: MessageContent(text: trimmed, financial: matching,
                                    financialObjectType: reference.type), type: .ISMONEY,
            groupId: groupID, reply: nil, receiverId: receiverID)
        message.isMoney = true
        message.transactionId = reference.id
        return message
    }
}
