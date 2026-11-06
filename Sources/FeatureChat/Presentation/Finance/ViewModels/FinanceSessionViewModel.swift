//
//  FinanceSessionViewModel.swift
//  FeatureChat
//
//  État de la session financière pour l'accueil Paiements — Phase 1.
//

import Foundation
import WaanguCoreKit

/// Dit à l'interface si la session permet d'écrire, et sinon pourquoi.
///
/// Ne décide rien : il relaie `FinanceSessionProviding`. L'ordre des motifs est
/// celui où l'utilisateur peut agir le moins — un pays fermé passe avant un
/// verrou qu'une reconnexion lèvera.
@MainActor
final class FinanceSessionViewModel: ObservableObject {

    enum State: Equatable {
        case loading
        case ready(FinanceSessionStatus)
        /// L'amorçage a échoué : rien n'est permis, et on le dit.
        case unavailable
        /// Aucune session à lire — backend simulé. Ni bandeau ni écran
        /// d'indisponibilité : il n'y a rien dont l'absence puisse se constater.
        case notApplicable
    }

    /// Motif affiché quand l'écriture n'est pas permise.
    enum Restriction: Equatable {
        case countryClosed
        case serviceSuspended
        /// `FINANCE_READ` refusé : ni solde ni relevé ne peuvent être consultés.
        case readDenied
        case safeMode
        case sessionLocked
        case paymentsDisabled
        case unavailable
    }

    @Published private(set) var state: State = .loading

    private let provider: (any FinanceSessionProviding)?

    init(provider: (any FinanceSessionProviding)?) {
        self.provider = provider
    }

    /// Une seule revalidation par écran : au-delà, le refus du serveur est sa
    /// réponse, pas un état périmé.
    private var revalidated = false

    func load() async {
        guard let provider else { state = .notApplicable; return }
        switch await provider.status() {
        case .success(let status): state = .ready(status)
        case .failure:             state = .unavailable
        }

        // Instantané pris avant la reprise de session : ouvert depuis les
        // Réglages, l'écran lisait une session encore verrouillée et concluait
        // « pays non ouvert » ou « session verrouillée », là où la conversation
        // — ouverte après la reprise — voyait le Hub. On relit **une fois**,
        // en jetant l'instantané : l'amorçage refait alors la reprise (§1.6).
        if !revalidated, let restriction, Self.mayClearAfterResume(restriction) {
            revalidated = true
            await refresh()
        }
    }

    /// Restrictions qu'une reprise de session peut lever. Un pays fermé pour de
    /// bon, lui, le reste — mais l'instantané pris trop tôt le disait à tort.
    static func mayClearAfterResume(_ restriction: Restriction) -> Bool {
        switch restriction {
        case .countryClosed, .sessionLocked, .paymentsDisabled, .readDenied: return true
        case .serviceSuspended, .safeMode, .unavailable:                     return false
        }
    }

    /// Reconnexion, retour au premier plan, nouvelle tentative : relire la
    /// session après avoir jeté l'instantané précédent.
    func refresh() async {
        await provider?.invalidate()
        await load()
    }

    var restriction: Restriction? {
        switch state {
        case .loading, .notApplicable:       return nil
        case .unavailable:                   return .unavailable
        case .ready(let status):
            if !status.countryOpen           { return .countryClosed }
            if status.serviceSuspended       { return .serviceSuspended }
            if !status.financeReadAllowed    { return .readDenied }
            if status.safeModeActive         { return .safeMode }
            if status.writeLocked            { return .sessionLocked }
            if !status.paymentsAllowed || !status.paymentPrepareAllowed { return .paymentsDisabled }
            return nil
        }
    }

    /// Solde et relevé peuvent être **demandés** — et seulement après l'amorçage.
    ///
    /// Tant que la session est en chargement, la réponse est non : c'est ce qui
    /// empêche la lecture du solde de partir avant que le serveur ait dit si
    /// l'utilisateur y a droit. Backend simulé : aucune session à attendre.
    var canReadAccount: Bool {
        switch state {
        case .notApplicable:       return true
        case .ready(let status):   return status.canReadAccount
        case .loading, .unavailable: return false
        }
    }

    var canWrite: Bool {
        if case .ready(let status) = state { return status.canWrite }
        return false
    }
}
