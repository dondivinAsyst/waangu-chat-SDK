//
//  FinancialMessageProjecting.swift
//  FeatureChat
//
//  Bloc 1, lot 1.4 — raccorder le store financier à la timeline.
//

import Foundation
import WaanguCoreKit

/// Écrit l'état d'un objet financier dans **chaque message** qui l'affiche.
///
/// Le message persisté est ce que la conversation relit et observe : tant qu'il
/// garde l'ancienne révision, la bulle aussi, et un relancement de l'application
/// la ramène même après que le store a reçu la nouvelle. Ce contrat ne crée
/// **pas** de seconde source d'état : le store décide de la révision retenue,
/// la projection ne fait que la recopier.
protocol FinancialMessageProjecting: Sendable {

    /// Met à jour tous les messages portant la référence de `payload`.
    ///
    /// - Returns: le nombre de messages réécrits. Zéro est normal : un objet
    ///   ouvert hors conversation n'a aucune bulle.
    @discardableResult
    func project(_ payload: FinancialCardPayload) async throws -> Int
}
