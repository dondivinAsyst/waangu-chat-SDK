//
//  SplitParticipantProgress.swift
//  FeatureChat
//
//  Où en est chaque participant d'un partage, tel qu'une carte peut le montrer.
//

import WaanguCoreKit

/// L'avancement d'un participant, **tel que le serveur le décrit**.
///
/// Dérivé d'un `SplitBill` lu au serveur, jamais d'événements comptés dans le
/// fil : un événement manqué ferait mentir le chiffre que les participants se
/// citent entre eux.
enum SplitParticipantProgress: Equatable {
    /// A versé toute sa part.
    case paid
    /// A accepté, n'a pas encore tout versé. Accepter n'est pas payer.
    case awaitingPayment
    /// Invité, n'a pas encore répondu.
    case awaitingApproval
    case declined
    case expired
    /// Retiré du partage par l'organisateur : ne doit rien.
    case excluded
    /// État que cette version ne connaît pas. Jamais présenté comme un refus.
    case unknown

    init(_ participant: SplitParticipant) {
        if participant.isExcluded {
            self = .excluded
            return
        }
        // Le versement prime : quelqu'un qui a tout payé a payé, quelle que soit
        // la trace de son consentement.
        if participant.share.isComparable(to: participant.contributed),
           participant.share.minorUnits > 0,
           !participant.hasOutstandingAmount {
            self = .paid
            return
        }
        switch participant.consent {
        case .accepted: self = .awaitingPayment
        case .pending:  self = .awaitingApproval
        case .declined: self = .declined
        case .expired:  self = .expired
        case .unknown:  self = .unknown
        }
    }
}

/// Ce qu'un spectateur donné a le droit de voir d'un partage.
///
/// La portée de confidentialité est **appliquée ici, une fois**, plutôt que
/// dans la vue : une carte qui filtrerait elle-même finirait par afficher la
/// part d'un autre dans un cas oublié.
struct SplitBillCardSnapshot: Equatable {

    struct Row: Equatable, Identifiable {
        let id: String
        let displayName: String
        let isViewer: Bool
        let share: Money
        let progress: SplitParticipantProgress
    }

    let total: Money
    /// `nil` quand la portée masque l'avancement global à ce spectateur.
    let collected: Money?
    /// Les lignes visibles : toutes, ou seulement celle du spectateur.
    let rows: [Row]
    /// `true` si des participants existent mais sont masqués à ce spectateur.
    let hidesOthers: Bool

    init(split: SplitBill, viewerID: String) {
        let isOrganizer = split.isOrganizer(viewerID)
        let seesOthers = split.privacyScope.canSeeOtherShares(isOrganizer: isOrganizer)

        let visible = split.participants.filter { seesOthers || $0.userID == viewerID }

        total = split.total
        collected = split.privacyScope.canSeeAggregate(isOrganizer: isOrganizer) ? split.collected : nil
        rows = visible.map {
            Row(
                id: $0.userID,
                displayName: $0.displayName,
                isViewer: $0.userID == viewerID,
                share: $0.share,
                progress: SplitParticipantProgress($0)
            )
        }
        hidesOthers = visible.count < split.participants.count
    }
}
