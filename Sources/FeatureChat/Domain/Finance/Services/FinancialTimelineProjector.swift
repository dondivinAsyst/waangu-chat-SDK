//
//  FinancialTimelineProjector.swift
//  FeatureChat
//
//  Bloc 1, lot 1.4 — chaque révision acceptée par le store rejoint les bulles.
//

import Foundation
import WaanguCoreKit

/// Recopie dans les messages chaque révision que le store accepte.
///
/// Avant lui, `FinancialObjectStore.changes()` n'avait aucun abonné : une
/// révision lue au serveur mettait à jour la mémoire, jamais la bulle, et la
/// conversation relue de la base montrait encore l'état d'origine.
///
/// Séquentiel, dans l'ordre d'émission du store : c'est l'ordre des révisions
/// acceptées, et le respecter évite qu'une ancienne écriture passe après une
/// récente.
struct FinancialTimelineProjector: Sendable {

    private let store: FinancialObjectStore
    private let projection: any FinancialMessageProjecting
    private let logger: any AppLoggerProtocol

    init(
        store: FinancialObjectStore,
        projection: any FinancialMessageProjecting,
        logger: any AppLoggerProtocol
    ) {
        self.store = store
        self.projection = projection
        self.logger = logger
    }

    /// Consomme le flux jusqu'à l'annulation de la tâche appelante.
    func run() async {
        for await payload in await store.changes() {
            guard !Task.isCancelled else { break }
            do {
                try await projection.project(payload)
            } catch {
                // La bulle garde sa révision précédente jusqu'à la prochaine
                // lecture serveur, qui repassera par ici. Rien n'est affiché
                // de faux : l'état plus ancien reste marqué comme tel.
                await logger.log(
                    "Projection financière impossible (\(payload.reference.type.rawValue)) : \(error.localizedDescription)",
                    level: .warning
                )
            }
        }
    }
}
