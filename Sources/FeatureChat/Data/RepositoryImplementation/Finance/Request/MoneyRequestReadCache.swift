//
//  MoneyRequestReadCache.swift
//  FeatureChat
//

import Foundation

/// Une seule lecture de `GET /request-money/{ref}` pour tous ceux qui la
/// demandent au même moment.
///
/// À l'ouverture d'une conversation, la carte (ses boutons) et le magasin (son
/// statut) lisaient la même demande chacun de leur côté : deux requêtes
/// identiques à quelques millisecondes. Les lectures simultanées sont
/// regroupées, et la réponse sert trois secondes — assez pour une ouverture,
/// trop peu pour qu'un état périmé s'installe.
///
/// **Vidée après toute action** (payer, refuser, relancer, annuler) : la
/// relecture qui suit doit voir l'effet de l'action, pas la réponse d'avant.
actor MoneyRequestReadCache {

    private struct Entry {
        let value: RequestViewDTO
        let at: Date
    }

    private var entries: [String: Entry] = [:]
    private var inFlight: [String: (token: UUID, task: Task<RequestViewDTO, Error>)] = [:]
    private let ttl: TimeInterval

    init(ttl: TimeInterval = 3) {
        self.ttl = ttl
    }

    func read(_ ref: String,
              fetch: @escaping @Sendable () async throws -> RequestViewDTO) async throws -> RequestViewDTO {
        if let entry = entries[ref], Date().timeIntervalSince(entry.at) < ttl {
            return entry.value
        }
        if let running = inFlight[ref] {
            return try await running.task.value
        }
        let token = UUID()
        let task = Task { try await fetch() }
        inFlight[ref] = (token, task)
        do {
            let value = try await task.value
            // Une invalidation survenue pendant la lecture l'emporte : sa
            // réponse ne doit pas être resservie.
            if inFlight[ref]?.token == token {
                entries[ref] = Entry(value: value, at: Date())
                inFlight[ref] = nil
            }
            return value
        } catch {
            if inFlight[ref]?.token == token { inFlight[ref] = nil }
            throw error
        }
    }

    func invalidate(_ ref: String) {
        entries[ref] = nil
        inFlight[ref] = nil
    }
}
