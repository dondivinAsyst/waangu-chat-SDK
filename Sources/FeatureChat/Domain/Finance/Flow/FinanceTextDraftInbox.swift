//
//  FinanceTextDraftInbox.swift
//  FeatureChat
//
//  Le brouillon du Hub, de l'accueil au parcours — §2.2.
//

import Foundation
import WaanguCoreKit

/// Porte **un** brouillon lu par le Hub (« envoie 5000 à Jean ») de l'accueil
/// jusqu'au parcours qu'il ouvre.
///
/// L'hôte ne transmet que l'entrée du catalogue à `PaymentsDestination` — trois
/// hôtes, trois chemins. L'accueil et la destination partagent en revanche la
/// même surface : le brouillon y attend, et le premier parcours ouvert le prend.
///
/// **À usage unique, et court.** Ouvrir n'importe quel parcours vide la boîte :
/// un montant tapé il y a dix minutes ne doit pas réapparaître dans un envoi
/// ouvert depuis un raccourci. Le brouillon ne propose qu'un montant ; il ne
/// désigne personne et n'engage rien.
public actor FinanceTextDraftInbox {

    /// Le temps de choisir un bénéficiaire, pas davantage.
    static let lifetime: TimeInterval = 120

    private var pending: (draft: FinanceTextDraft, storedAt: Date)?

    public init() {}

    func put(_ draft: FinanceTextDraft, now: Date = Date()) {
        pending = (draft, now)
    }

    /// Le brouillon, s'il est pour ce parcours et encore frais. La boîte est
    /// vidée dans tous les cas.
    func take(for kind: FinanceEntryKind, now: Date = Date()) -> FinanceTextDraft? {
        defer { pending = nil }
        guard let pending, pending.draft.kind == kind,
              now.timeIntervalSince(pending.storedAt) < Self.lifetime else { return nil }
        return pending.draft
    }
}
