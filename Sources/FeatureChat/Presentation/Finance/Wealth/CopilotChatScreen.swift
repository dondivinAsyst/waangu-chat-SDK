//
//  CopilotChatScreen.swift
//  FeatureChat
//
//  Waangu Copilot ouvert depuis la liste des discussions, comme une conversation.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// La conversation Waangu Copilot, poussée dans la pile des discussions.
///
/// Hors de tout fil, comme le portefeuille : les actions du Hub sont celles du
/// dossier personnel (§5.1.1), un bénéficiaire est payé dans son propre fil, et
/// la conversation se garde sur l'appareil. Une opération que Copilot ne mène
/// pas s'ouvre en feuille, comme depuis l'accueil des paiements.
struct CopilotChatScreen: View {

    let surface: ChatFinanceSurface
    let store: any CopilotConversationStoring

    @StateObject private var messaging: WalletPaymentFlowViewModel
    @State private var entries: [FinanceCatalogEntry]?
    @State private var selfFolderID = ""
    @State private var presentedEntry: FinanceCatalogEntry?
    @State private var showsUnavailable = false

    init(surface: ChatFinanceSurface,
         store: any CopilotConversationStoring,
         discussions: any DiscussionUseCasesProtocol,
         publisher: any PublishFinanceMessageUseCaseProtocol) {
        self.surface = surface
        self.store = store
        _messaging = StateObject(wrappedValue: WalletPaymentFlowViewModel(discussions: discussions,
                                                                          publisher: publisher))
    }

    var body: some View {
        Group {
            if let entries {
                CopilotConversationView(
                    surface: surface,
                    host: nil,
                    hubKinds: entries.filter { $0.isActionable() }.map(\.kind),
                    closedHubActions: Dictionary(entries.filter { !$0.isActionable() && $0.unavailableReasonKey != nil }
                    .map { ($0.kind, FinanceLocalization.entryReason($0.unavailableReasonKey ?? "")) },
                    uniquingKeysWith: { first, _ in first }),
                    directMessaging: messaging,
                    conversationStore: store,
                    isPushed: true,
                    onOpen: { draft in Task { await open(draft) } },
                    onDismiss: {}
                )
            } else {
                FinanceLoaderView()
            }
        }
        // Déjà dans la pile des discussions : pas de seconde pile.
        .environment(\.financeHasNavigationStack, true)
        .toolbar(.hidden, for: .tabBar)
        .task {
            guard entries == nil else { return }
            selfFolderID = await surface.catalog.personalFolder()?.conversationID ?? ""
            entries = await surface.catalog.entries(for: ChatFinanceContext(
                conversationID: selfFolderID, conversationKind: .selfChat, participantCount: 1))
        }
        .chatAppearanceSheet(item: $presentedEntry) { entry in
            FinanceNavigationScope {
                PaymentsDestination(
                    entry: entry,
                    surface: surface,
                    conversationID: selfFolderID,
                    onDismiss: { presentedEntry = nil }
                )
            }
            .environment(\.financeFlowSurface, surface)
            .environment(\.financeOperationKeys, surface.operationKeys)
        }
        .alert(FinanceStrings.draftActionUnavailable, isPresented: $showsUnavailable) {
            Button(FinanceStrings.close, role: .cancel) {}
        }
    }

    /// Le parcours de la carte « ouvrir et vérifier », avec ce que Copilot a
    /// compris — après l'élévation que le Hub exige, comme depuis l'accueil.
    private func open(_ draft: FinanceTextDraft) async {
        guard let kind = draft.kind,
              let entry = entries?.first(where: { $0.kind == kind }), entry.isActionable() else {
            showsUnavailable = true
            return
        }
        if entry.requiresStepUp == true {
            if await surface.stepUp.currentLevel < .pin {
                _ = try? await surface.stepUp.elevate(to: .pin)
            }
            guard await surface.stepUp.currentLevel >= .pin else { return }
        }
        await surface.textDrafts.put(draft)
        presentedEntry = entry
    }
}
