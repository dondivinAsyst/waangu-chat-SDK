//
//  FinanceParticipantsPicker.swift
//  FeatureChat
//
//  Choix de plusieurs contacts — les participants d'un partage.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Sélection multiple parmi les contacts qu'on peut joindre.
///
/// Remplace la saisie d'identifiants séparés par des virgules : un identifiant
/// tapé ne dit pas à qui il appartient, et une faute de frappe invitait un
/// inconnu — ou personne — sans que rien ne le signale.
struct FinanceParticipantsPicker: View {

    let sharing: any ShareSplitBillUseCaseProtocol
    /// Rendue par « OK » ; « Annuler » laisse le partage tel qu'il était.
    let onDone: ([UserContactProps]) -> Void
    let onCancel: () -> Void

    /// Sélection en cours, **détachée** de celle du partage jusqu'à « OK » :
    /// fermer la feuille ne doit pas valider à moitié un choix abandonné.
    @State private var selection: [UserContactProps]
    private let initialIDs: Set<String>
    @State private var candidates: [UserContactProps] = []
    @State private var search = ""
    @State private var isLoading = true

    init(
        sharing: any ShareSplitBillUseCaseProtocol,
        initialSelection: [UserContactProps],
        onDone: @escaping ([UserContactProps]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sharing = sharing
        self.onDone = onDone
        self.onCancel = onCancel
        _selection = State(initialValue: initialSelection)
        initialIDs = Set(initialSelection.map(\.userId))
    }

    private var filtered: [UserContactProps] {
        guard !search.isEmpty else { return candidates }
        let needle = search.lowercased()
        return candidates.filter {
            $0.name.lowercased().contains(needle) || $0.phone.contains(needle)
        }
    }

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppColors.walletCanvas)
            } else if candidates.isEmpty {
                FinanceContactsEmptyState(icon: "person.2.slash", title: FinanceStrings.splitParticipantsNone)
            } else if filtered.isEmpty {
                FinanceContactsEmptyState(icon: "magnifyingglass", title: FinanceStrings.recipientNoResults)
            } else {
                FinanceContactList(contacts: filtered) { contact in
                    row(contact)
                }
            }
        }
        .searchable(text: $search, prompt: Text(FinanceStrings.recipientSearch))
        // Le titre dit ce qu'on choisit, et combien sont déjà choisis.
        .navigationTitle(FinanceStrings.splitParticipantsChoose)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(FinanceStrings.cancel, action: onCancel)
            }
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(FinanceStrings.splitParticipantsChoose)
                        .font(.headline)
                        .foregroundStyle(AppColors.textPrimary)
                    if !selection.isEmpty {
                        Text(FinanceStrings.splitParticipantsSelected(selection.count))
                            .font(.caption)
                            .foregroundStyle(AppColors.subtitleGray)
                    }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(FinanceStrings.splitParticipantsDone) { onDone(selection) }
                    .fontWeight(.semibold)
                    .disabled(selection.isEmpty)
            }
        }
        // Un choix modifié ne se perd pas d'un glissement ; « Annuler » reste là.
        .interactiveDismissDisabled(Set(selection.map(\.userId)) != initialIDs)
        .task {
            candidates = await sharing.participantCandidates()
            isLoading = false
        }
    }

    private func row(_ contact: UserContactProps) -> some View {
        let isSelected = selection.contains { $0.userId == contact.userId }
        return Button {
            if isSelected {
                selection.removeAll { $0.userId == contact.userId }
            } else {
                selection.append(contact)
            }
        } label: {
            FinanceContactRow(contact: contact, isHighlighted: isSelected) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? AppColors.primary : AppColors.subtitleGray)
            }
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
