//
//  FinanceConfirmRetry.swift
//  FeatureChat
//

import Foundation
import WaanguCoreKit

/// Reprise d'une confirmation refusée par une session verrouillée.
///
/// Au moment de confirmer, la session peut être verrouillée (`PAYMENT_CONFIRM:
/// DENY`, « Reconnect revalidation required ») ; l'application la reprend
/// aussitôt (`POST /session/resume`). Le refus a eu lieu **dans l'application,
/// avant tout envoi** : `capabilityUnavailable` n'est jamais rendu après un
/// execute. Reconfirmer le même devis, sous la même clé, ne peut donc rien
/// débiter deux fois — et évite de demander à l'utilisateur de reconfirmer
/// une opération qu'il vient d'accepter.
///
/// Une seule reprise : si la session refuse encore, l'erreur s'affiche.
enum FinanceConfirmRetry {

    static func sessionNowAllowsConfirm(after error: FinanceError,
                                        session: (any FinanceSessionProviding)?) async -> Bool {
        guard error == .capabilityUnavailable,
              let session,
              case .success(let status) = await session.status() else { return false }
        return status.canConfirm
    }
}
