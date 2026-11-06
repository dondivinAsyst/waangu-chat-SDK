//
//  TransactionHistoryView.swift
//  FeatureChat
//
//  Le relevé des opérations du compte.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Le relevé, tel que le backend le rend.
///
/// **Constate, n'interprète pas.** Chaque ligne porte le statut réel de son
/// opération, y compris quand il n'est pas final ou qu'il est mauvais. Un relevé
/// qui n'afficherait que les réussites laisserait un débit en attente invisible
/// jusqu'à son passage — c'est-à-dire jusqu'à ce qu'il soit trop tard pour le
/// signaler.
struct TransactionHistoryView: View {

    let history: any TransactionHistoryProviding
    let onDismiss: () -> Void

    @State private var entries: [TransactionHistoryEntry] = []
    @State private var cursor: String?
    @State private var phase: Phase = .loading
    /// Distinct de `phase` : la pagination ne doit pas rendre l'écran au
    /// chargement, sinon la liste déjà lue disparaît sous un indicateur.
    @State private var isLoadingMore = false

    private enum Phase: Equatable {
        case loading
        /// Le relevé a répondu, et il n'y a rien. Un compte neuf est dans ce cas.
        case empty
        case loaded
        /// Le service n'a pas répondu. Distinct de `empty` : ne rien avoir fait
        /// et ne pas pouvoir savoir sont deux choses.
        case failed(String)
    }

    private static let pageSize = 20

    var body: some View {
        NavigationStack {
            content
                .financePhase(phase)
                .navigationTitle(FinanceLocalization.string(
                    "wallet_transaction_history", fallback: "Historique des transactions"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(FinanceLocalization.string("common_close", fallback: "Fermer"),
                               action: onDismiss)
                    }
                }
        }
        .task { await loadFirstPage() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .empty:
            emptyState

        case .failed(let message):
            failureState(message)

        case .loaded:
            list
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                    TransactionHistoryRow(entry: entry, showsSeparator: index < entries.count - 1)
                        .onAppear {
                            // Pagination au dernier élément visible plutôt qu'à un
                            // bouton : le relevé se parcourt, il ne se demande pas.
                            if index == entries.count - 1 { Task { await loadMore() } }
                        }
                }

                if isLoadingMore {
                    ProgressView().padding(.vertical, 16)
                }
            }
            .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 15)
            .padding(.vertical, 12)
        }
        .background(AppColors.walletCanvas)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "list.bullet.rectangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(FinanceLocalization.string(
                "wallet_history_empty", fallback: "Aucune opération pour l'instant"))
                .font(.subheadline.weight(.medium))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private func failureState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button(FinanceLocalization.string("common_retry", fallback: "Réessayer")) {
                Task { await loadFirstPage() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Chargement

    private func loadFirstPage() async {
        phase = .loading
        entries = []
        cursor = nil
        await fetch(replacing: true)
    }

    private func loadMore() async {
        // Trois gardes, et chacune ferme un cas réel : pas de page suivante,
        // une requête déjà en vol, un écran qui n'est pas en état de paginer.
        guard cursor != nil, !isLoadingMore, phase == .loaded else { return }
        isLoadingMore = true
        await fetch(replacing: false)
        isLoadingMore = false
    }

    private func fetch(replacing: Bool) async {
        let result = await history.history(cursor: cursor, limit: Self.pageSize)

        switch result {
        case .success(let page):
            let merged = replacing ? page.entries : entries + page.entries
            entries = merged
            cursor = page.nextCursor
            phase = merged.isEmpty ? .empty : .loaded

        case .failure(let error):
            // Un échec de page suivante ne jette pas la liste déjà lue : elle
            // reste vraie. Seule la première page fait basculer l'écran.
            guard replacing else { cursor = nil; return }
            phase = .failed(FinanceLocalization.string(
                "wallet_history_unavailable",
                fallback: "Le relevé n'est pas disponible pour le moment."
            ))
            _ = error
        }
    }
}

// MARK: - Ligne

/// Une opération au relevé — partagée avec l'accueil, qui en montre trois.
struct TransactionHistoryRow: View {

    let entry: TransactionHistoryEntry
    let showsSeparator: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                icon

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.label)
                        .font(.system(size: 17))
                        .tracking(-0.43)
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(subtitle)
                        .font(.system(size: 14))
                        .tracking(-0.154)
                        .foregroundStyle(statusColor)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(amountText)
                    .font(.system(size: 17, weight: .semibold))
                    // Un crédit se distingue par son signe **et** par sa
                    // couleur ; un débit reste neutre. Colorer les deux ferait
                    // du relevé une alternance sans hiérarchie.
                    .foregroundStyle(entry.direction == .credit
                                     ? AppColors.walletCurrency
                                     : AppColors.textPrimary)
                    // Une opération qui n'a pas abouti garde son montant lisible
                    // mais barré : l'effacer ferait disparaître ce qui a été
                    // tenté, et le laisser plein le ferait passer pour débité.
                    .strikethrough(hasFailed)
                    .opacity(hasFailed ? 0.5 : 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            if showsSeparator {
                AppColors.separator
                    .frame(height: 0.33)
                    .padding(.leading, 60)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.label), \(amountText), \(subtitle)")
    }

    private var icon: some View {
        ZStack {
            Circle()
                .fill(AppColors.primary.opacity(0.12))
                .frame(width: 40, height: 40)
            Image(systemName: entry.direction == .credit ? "arrow.down" : "arrow.up")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.primary)
        }
    }

    private var hasFailed: Bool {
        switch entry.status {
        case .failed, .cancelled, .expired, .denied, .reversed: return true
        default: return false
        }
    }

    private var statusColor: Color {
        if hasFailed { return AppColors.subtitleGray }
        return entry.status.isInFlight ? AppColors.primary : AppColors.subtitleGray
    }

    /// Date, et statut **seulement quand il n'est pas l'aboutissement normal**.
    ///
    /// Écrire « terminé » sur chaque ligne aboutie noierait les trois lignes qui
    /// ne le sont pas, qui sont les seules à demander une action.
    private var subtitle: String {
        let date = entry.occurredAt.formatted(date: .abbreviated, time: .shortened)
        switch entry.status {
        case .completed, .confirmed:
            return date
        default:
            return date + " · " + statusLabel
        }
    }

    private var statusLabel: String {
        FinanceLocalization.string(
            "payment_status_" + entry.status.rawValue.lowercased(),
            fallback: entry.status.isInFlight
                ? FinanceLocalization.string("payment_status_pending", fallback: "En cours")
                : FinanceLocalization.string("payment_status_failed", fallback: "Échoué")
        )
    }

    private var amountText: String {
        let sign = entry.direction == .credit ? "+" : "−"
        let parts = WalletAmountText.split(
            entry.amount.majorUnitsForDisplay,
            entry.amount.currency.code
        )
        return sign + parts.prefix + parts.digits + (parts.suffix.isEmpty ? "" : " " + parts.suffix)
    }
}
