//
//  FinancialObjectStateMachine.swift
//  CoreKit
//
//  Transitions licites d'un objet financier — Bloc 2 §9.4.
//

import Foundation

/// Décide si une transition d'état est possible.
///
/// Le garde de version (`FinancialReference.supersedes`) répond à « est-ce plus
/// récent ? ». Il ne répond pas à « est-ce possible ? ». Les deux questions sont
/// indépendantes, et seule la première était posée : un événement strictement
/// plus récent décrivant `completed -> processing` était appliqué, faisant
/// repasser en « en cours » une opération close.
///
/// Cette machine ne remplace pas le garde de version, elle s'y ajoute. Une
/// révision périmée est rejetée avant d'arriver ici.
public enum FinancialObjectStateMachine {

    public enum Verdict: Equatable, Sendable {

        case allowed

        /// Transition refusée. L'objet **garde son état** et une réconciliation
        /// est demandée : on ne devine pas lequel des deux états est le bon,
        /// c'est au backend de trancher.
        case forbidden(reason: String)

        /// Transition qu'aucune règle de cette version ne décrit.
        ///
        /// Ni appliquée, ni rejetée : requêtée. Un client déployé ne doit pas
        /// bloquer un état que le backend a introduit après lui — c'est la même
        /// règle que le décodage défensif de `PaymentStatus`.
        case unknown
    }

    /// Transitions autorisées **depuis un état terminal**.
    ///
    /// Un état terminal ne se rouvre que par un événement d'après-finalité :
    /// remboursement, annulation par le rail, litige. Tout le reste est refusé.
    private static let terminalReopenings: [PaymentStatus: Set<PaymentStatus>] = [
        .confirmed:         [.completed, .refundRequested, .refunded, .partiallyRefunded,
                             .reversed, .disputed, .reconciling],
        .completed:         [.refundRequested, .refunded, .partiallyRefunded,
                             .reversed, .disputed, .reconciling],
        .partiallyRefunded: [.refunded, .disputed, .reversed],
        .refunded:          [.disputed],
        .reversed:          [.disputed],
        // Échec, annulation, expiration et refus ne se rouvrent pas : une
        // nouvelle tentative est un nouvel objet, avec sa propre clé.
        .failed:            [],
        .cancelled:         [],
        .expired:           [],
        .denied:            [],
        .restricted:        []
    ]

    /// - Parameters:
    ///   - current: état connu de ce client.
    ///   - next: état porté par la révision entrante, déjà reconnue plus récente.
    public static func verdict(
        from current: PaymentStatus,
        to next: PaymentStatus
    ) -> Verdict {

        // Réappliquer le même état ne change rien et ne casse rien.
        if current == next { return .allowed }

        // Avouer son ignorance (`unknown`) ou celle du serveur (`inDoubt`) est
        // toujours licite, depuis n'importe quel état.
        // C'est ce qui permet à un timeout de dégrader proprement un objet en
        // cours sans que la machine ne s'y oppose.
        if next.requiresReconciliation { return .allowed }

        // Sortir de `unknown` vers n'importe quoi est licite : c'est exactement
        // ce que produit une réconciliation réussie.
        if current.requiresReconciliation { return .allowed }

        // Un devis périmé ne devient jamais un succès sans nouvelle proposition.
        // Le montant, le taux et les frais du devis expiré ne sont plus ceux que
        // l'utilisateur a acceptés.
        if current == .expired, next == .confirmed || next == .completed {
            return .forbidden(reason: "expired_to_paid_without_new_quote")
        }

        if current.isTerminal {
            guard let allowed = terminalReopenings[current] else {
                // État terminal que cette version ne sait pas classer.
                return .unknown
            }
            return allowed.contains(next)
                ? .allowed
                : .forbidden(
                    reason: "terminal_reopen(\(current.rawValue)->\(next.rawValue))"
                  )
        }

        // Objet encore en vol : le backend fait avancer son cycle comme il
        // l'entend. Le client n'a pas de modèle du rail assez fin pour arbitrer
        // entre `pending` et `processing`, et prétendre le contraire refuserait
        // des transitions légitimes.
        return .allowed
    }
}
