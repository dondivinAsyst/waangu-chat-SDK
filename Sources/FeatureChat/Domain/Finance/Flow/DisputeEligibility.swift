//
//  DisputeEligibility.swift
//  FeatureChat
//
//  Quand « Signaler un problème » est offert.
//

import Foundation

/// Le serveur décide : `OPEN_DISPUTE` dans les `allowedActions` de la carte, qu'il
/// ne pose que sur une opération `COMPLETED` (réponse du backend, Q7).
///
/// **Provisoire, Debug seulement.** Le serveur de dev ne termine aucun paiement :
/// tous restent `PENDING`, et l'option n'apparaîtrait sur aucun. En Debug, elle
/// est donc offerte sans l'action serveur — le POST ne vérifie pas encore la
/// carte, il l'accepte. À retirer dès que le dev complète des paiements, ou que
/// le POST s'aligne. Absent des builds Release.
enum DisputeEligibility {

    /// Les tests le passent à `false` pour éprouver la règle du serveur.
    nonisolated(unsafe) static var bypassesServerAction: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static func allows(_ allowedActions: [String]?) -> Bool {
        bypassesServerAction || allowedActions?.contains("OPEN_DISPUTE") == true
    }
}

/// Quand le remboursement et l'extourne sont offerts : le serveur dit `COMPLETED`
/// (réponses du backend, Q16/Q17). **Provisoire, Debug seulement**, pour la même
/// raison que ci-dessus : le dev ne termine aucun paiement. Le prepare du serveur
/// refuse de toute façon un original non `COMPLETED` (`CF_047`) — le contournement
/// montre le parcours, pas un remboursement qui aboutit. Absent des builds Release.
enum ReversalEligibility {

    nonisolated(unsafe) static var bypassesCompletedStatus: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    static func allows(_ payload: FinancialCardPayload?) -> Bool {
        guard let payload else { return false }
        return bypassesCompletedStatus || payload.status == .completed
    }
}
