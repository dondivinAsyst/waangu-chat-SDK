//
//  TransferSubmission.swift
//  FeatureChat
//
//  Confirmation d'un transfert qui survit à un kill — Bloc 8 §4, Bloc 10 §21.E.
//

import Foundation
import WaanguCoreKit

/// Confirme un devis de transfert **sous une clé enregistrée**, et inscrit
/// l'opération avant de l'exécuter.
///
/// Partagé par l'envoi d'argent et le paiement par QR, qui aboutissent tous deux
/// à ``SendMoneyUseCase/confirm(agreed:recipientID:operationID:idempotency:attestation:beforeExecution:)``.
///
/// **Deux défauts fermés ici.**
///
/// 1. *La clé n'était enregistrée nulle part.* Les deux écrans fabriquaient un
///    `IdempotencyContext` dans leur état et passaient sa clé comme identifiant
///    d'opération. Le cas d'usage vérifie cette clé auprès du registre, qui
///    refuse toute opération inconnue : avec le registre réel, chaque
///    confirmation s'arrêtait sur `.duplicate` avant d'exécuter quoi que ce
///    soit. Les tests ne le voyaient pas — ils construisent le cas d'usage sans
///    registre.
///
/// 2. *Un kill en vol ne laissait aucune trace.* La clé vivait dans l'état de la
///    vue, et l'inscription ambiguë n'avait lieu qu'**après** la réponse. Tué
///    pendant l'appel, le client relancé ne savait rien de l'opération :
///    l'utilisateur la refaisait sur un nouveau devis, et si la première était
///    passée, il était débité deux fois.
///
/// **Pourquoi la portée est le devis et non le contenu.** Envoyer deux fois le
/// même montant à la même personne est un geste légitime. Une clé tirée du
/// montant et du bénéficiaire ferait rendre par le serveur le premier envoi à la
/// place du second — une réussite affichée sans argent déplacé. La référence du
/// devis identifie *cette* intention et aucune autre ; c'est l'inscription
/// avant soumission, relue au lancement, qui couvre le kill.
enum TransferSubmission {

    /// Portée de la clé d'une confirmation : la référence du devis accepté.
    static func scope(for quote: TransferQuote) -> String {
        FinanceOperationKeys.scope("transfer.confirm", quote.reference.type.rawValue, quote.reference.id)
    }

    /// Clé de la confirmation de ce devis — créée et enregistrée au premier
    /// appel, rendue à l'identique ensuite.
    static func key(for quote: TransferQuote,
                    operationKeys: FinanceOperationKeys,
                    deviceID: String) async -> IdempotencyContext {
        await operationKeys.key(for: scope(for: quote), deviceID: deviceID)
    }

    /// Confirme, en inscrivant l'opération juste avant son exécution, puis relit
    /// la vérité serveur si une inscription a eu lieu.
    ///
    /// La relecture remplace l'inscription quelle que soit l'issue : réussite,
    /// refus serveur ou issue inconnue. Si elle échoue à son tour, l'inscription
    /// reste ambiguë et le planificateur de réconciliation la reprendra — ce qui
    /// est exactement le comportement voulu quand le réseau vient de manquer.
    static func confirm(
        _ quote: TransferQuote,
        recipientID: String,
        counterpartyName: String?,
        attestation: StepUpAttestation?,
        sendMoney: SendMoneyUseCase,
        operationKeys: FinanceOperationKeys,
        objects: (any FinancialObjectUseCasesProtocol)?,
        deviceID: String
    ) async -> SendMoneyUseCase.Outcome {
        let scope = scope(for: quote)
        let idempotency = await operationKeys.key(for: scope, deviceID: deviceID)
        let recorded = RecordedSubmission()

        let outcome = await sendMoney.confirm(
            agreed: quote,
            recipientID: recipientID,
            // L'identifiant sous lequel `FinanceOperationKeys` a enregistré la
            // clé — jamais la clé elle-même, que le registre ne connaît pas.
            operationID: FinanceOperationKeys.operationID(for: scope),
            idempotency: idempotency,
            attestation: attestation,
            beforeExecution: { executing in
                guard let objects else { return }
                await objects.recordSubmission(FinancialOutcomeRoute.ambiguousPayload(
                    reference: executing.reference,
                    amount: executing.totalAmount ?? executing.amount,
                    currency: executing.totalCurrency ?? executing.currency,
                    counterpartyName: counterpartyName
                ))
                await recorded.mark(executing.reference)
            }
        )

        if let reference = await recorded.reference {
            if case .refused = outcome {
                // Inscrite juste avant l'appel, puis refusée par le serveur :
                // l'opération n'a jamais existé. La garder laisserait une carte
                // « en vérification » que la réconciliation relirait sans fin.
                await objects?.discardSubmission(reference)
            } else {
                _ = await objects?.refresh(reference)
            }
        }
        return outcome
    }
}

/// Trace, entre la fermeture d'inscription et l'appelant, qu'une opération a
/// bien été inscrite — et sous quelle référence.
private actor RecordedSubmission {
    private(set) var reference: FinancialReference?
    func mark(_ reference: FinancialReference) { self.reference = reference }
}
