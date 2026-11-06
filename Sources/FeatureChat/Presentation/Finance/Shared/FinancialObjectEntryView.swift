//
//  FinancialObjectEntryView.swift
//  FeatureChat
//
//  Ouvre un objet financier désigné de l'extérieur — push ou lien.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Écran d'un objet financier dont on ne connaît **que l'identité**.
///
/// Un push financier ne transporte qu'un type et un identifiant opaque. La route
/// existait, puis s'arrêtait sur la liste des discussions : toucher la
/// notification n'ouvrait rien. Ici, l'identité est relue auprès du serveur, et
/// seul ce que le serveur rend est affiché — Bloc 12, TEST-NOTIF-001 : un push
/// n'est jamais une preuve financière.
struct FinancialObjectEntryView: View {

    let reference: FinancialReference
    let surface: ChatFinanceSurface
    let onDismiss: () -> Void

    @State private var phase: Phase = .loading

    private enum Phase: Equatable {
        case loading
        case loaded(FinancialCardPayload)
        /// Lecture impossible : **aucun** statut n'est affiché, pas même un
        /// statut en cache — il pourrait appartenir à un état dépassé.
        case unavailable(String)
    }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                FinanceNavigationScope {
                    FinanceProgress(label: FinanceStrings.flowCheckStatus)
                        .toolbar { closeButton }
                }
            case .loaded(let payload):
                FinancialObjectActionsView(payload: payload, surface: surface,
                                           conversationID: nil, onDismiss: onDismiss)
            case .unavailable(let message):
                FinanceNavigationScope {
                    VStack(spacing: 14) {
                        FinanceMessage(icon: "questionmark.circle", text: message)
                        Button(FinanceStrings.flowCheckStatus) { Task { await load() } }
                            .buttonStyle(.bordered)
                    }
                    .toolbar { closeButton }
                }
            }
        }
        .financePhase(phase)
        .task { await load() }
    }

    private var closeButton: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button(FinanceStrings.close, action: onDismiss)
        }
    }

    @MainActor
    private func load() async {
        guard let reader = surface.objectReader else {
            phase = .unavailable(FinanceStrings.financialObjectUnavailable)
            return
        }
        phase = .loading
        switch await reader.refresh(reference) {
        case .success(let payload):
            phase = .loaded(payload)
        case .failure(let error):
            phase = .unavailable(FinanceStrings.errorMessage(error))
        }
    }
}
