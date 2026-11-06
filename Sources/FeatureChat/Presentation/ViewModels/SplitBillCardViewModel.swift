//
//  SplitBillCardViewModel.swift
//  FeatureChat
//
//  Lecture serveur d'un partage pour sa carte de conversation.
//

import Foundation
import WaanguCoreKit

/// Charge le partage qu'une carte de conversation représente.
///
/// La carte ne montre l'avancement de chacun **qu'après lecture serveur** ;
/// jusque-là, ou si la lecture échoue, elle garde ce que le message portait —
/// le montant et le statut — sans rien inventer.
@MainActor
final class SplitBillCardViewModel: ObservableObject {

    enum Phase: Equatable {
        case idle
        case loading
        case loaded(SplitBillCardSnapshot)
        case unavailable
    }

    @Published private(set) var phase: Phase = .idle

    func load(splitID: String, splits: any SplitBillManaging, viewerID: String) async {
        guard !splitID.isEmpty, !viewerID.isEmpty else {
            phase = .unavailable
            return
        }
        if case .loaded = phase {} else { phase = .loading }

        switch await splits.split(id: splitID) {
        case .success(let split):
            phase = .loaded(SplitBillCardSnapshot(split: split, viewerID: viewerID))
        case .failure(let error):
            // Une lecture ratée n'efface pas une lecture réussie : la carte
            // garde le dernier état connu plutôt que de retomber au montant seul.
            if case .loaded = phase { return }
            phase = .unavailable
            await AppLogger.shared.log(
                "Split card load failed split=\(splitID): \(error)",
                level: .warning
            )
        }
    }
}
