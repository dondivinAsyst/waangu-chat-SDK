//
//  FinanceEntryAdmission.swift
//  FeatureChat
//
//  Peut-on ouvrir ce parcours ? — Bloc 5 §16, Bloc 12 TEST-KILL-001.
//

import Foundation
import WaanguCoreKit

/// Verdict d'ouverture d'un parcours financier.
///
/// **Le défaut corrigé.** Le coupe-circuit opérationnel était injecté jusque dans
/// la surface financière, et lu nulle part : suspendre un produit, un
/// fournisseur ou toute la couche financière ne fermait aucun parcours.
///
/// **L'ordre compte.** La suspension passe avant les portes de capacité : c'est
/// le levier d'incident, il doit fermer même un parcours que le catalogue
/// déclare ouvert — et même un parcours sans identifiant de capacité, que les
/// portes laissent passer.
enum FinanceEntryAdmission: Equatable, Sendable {
    case open
    /// Suspendu par le coupe-circuit. La clé vient du backend, `nil` ⇒ message générique.
    case suspended(reasonKey: String?)
    case closed(CapabilityClosure)

    static func decide(kind: FinanceEntryKind,
                       suspensions: KillSwitchState,
                       closure: CapabilityClosure?) -> FinanceEntryAdmission {
        // Produit = le type d'entrée, parcours = la capacité qu'il met en œuvre.
        // Ces identifiants doivent être ceux que publie le backend du
        // coupe-circuit ; la coupure totale, elle, n'en dépend pas.
        guard suspensions.allows(productID: kind.rawValue, workflowID: kind.capabilityID) else {
            return .suspended(reasonKey: suspensions.reasonKey)
        }
        if let closure { return .closed(closure) }
        return .open
    }
}
