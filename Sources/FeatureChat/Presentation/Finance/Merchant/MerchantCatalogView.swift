//
//  MerchantCatalogView.swift
//  FeatureChat
//
//  Catalogue marchand — Bloc 1, chapitre 7.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Le catalogue d'un marchand, article par article.
///
/// Rien n'est calculé ici. L'écran envoie « ajoute une unité de cet article »
/// et affiche le panier que le serveur renvoie : c'est ce qui garantit que le
/// total affiché est celui qui sera débité.
struct MerchantCatalogView: View {

    let merchantID: String
    let commerce: any CommerceOrdering
    let deviceID: String

    /// Clés d'idempotence, une par opération et par charge utile — Bloc 10, §4.
    /// Voir `FinanceOperationKeys` : une clé fabriquée dans l'appel faisait de
    /// chaque nouvelle tentative une seconde opération côté serveur.
    @Environment(\.financeOperationKeys) private var operationKeys
    let onDismiss: () -> Void

    @State private var items: [CommerceItem] = []
    @State private var nextCursor: String?
    @State private var cart: CommerceCart?
    @State private var phase: Phase = .loading
    @State private var showsCart = false
    /// Articles dont la mise à jour est en vol, pour ne pas empiler deux
    /// ajouts sur un double tap.
    @State private var pendingItemIDs: Set<String> = []

    private enum Phase {
        case loading
        case loaded
        case empty
        case failed(String)
    }

    private var flowIsBusy: Bool {
        false
    }

    private var flowIsDirty: Bool {
        false
    }

    private var flowBack: (() -> Void)? {
        nil
    }

    var body: some View {
        FinanceNavigationScope {
            Group {
                switch phase {
                case .loading: FinanceProgress(label: FinanceStrings.catalogLoading)
                case .empty:   FinanceMessage(icon: "shippingbox", text: FinanceStrings.catalogEmpty)
                case .failed(let message): FinanceMessage(icon: "exclamationmark.triangle", text: message)
                case .loaded:  list
                }
            }
            .financePhase(phase)
            .navigationTitle(FinanceStrings.catalogTitle)
            .navigationBarTitleDisplayMode(.inline)
            .financeTaskControls(isBusy: flowIsBusy, isDirty: flowIsDirty, back: flowBack, onClose: onDismiss)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let cart, !cart.lines.isEmpty {
                        Button { showsCart = true } label: {
                            Label("\(cart.lines.count)", systemImage: "cart")
                        }
                        .accessibilityLabel(FinanceStrings.cartOpen)
                    }
                }
            }
            .financeDestination(isPresented: $showsCart) {
                CartView(
                    merchantID: merchantID, commerce: commerce, deviceID: deviceID,
                    onDismiss: { showsCart = false; Task { await reloadCart() } }
                )
            }
        }
        .financeLoadOnce { await load() }
    }

    // MARK: - Chargement

    private func load() async {
        phase = .loading
        switch await commerce.catalog(merchantID: merchantID, cursor: nil) {
        case .success(let page):
            items = page.items
            nextCursor = page.nextCursor
            phase = page.items.isEmpty ? .empty : .loaded
            await reloadCart()
        case .failure(let error):
            phase = .failed(FinanceStrings.errorMessage(error))
        }
    }

    /// Charge la page suivante. Un échec de pagination **ne vide pas** la liste
    /// déjà affichée : perdre trente articles parce que le trente-et-unième n'a
    /// pas chargé serait une régression visible.
    private func loadMore() async {
        guard let cursor = nextCursor else { return }
        if case .success(let page) = await commerce.catalog(merchantID: merchantID, cursor: cursor) {
            items.append(contentsOf: page.items)
            nextCursor = page.nextCursor
        }
    }

    private func reloadCart() async {
        if case .success(let current) = await commerce.cart(merchantID: merchantID) {
            cart = current
        }
    }

    private func add(_ item: CommerceItem) async {
        guard !pendingItemIDs.contains(item.id) else { return }
        pendingItemIDs.insert(item.id)
        defer { pendingItemIDs.remove(item.id) }

        let current = quantity(of: item.id)
        let submissionKey126 = await operationKeys.key(for: FinanceOperationKeys.scope("cart.update", merchantID, item.id, current + 1), deviceID: deviceID)
        let result = await commerce.updateCart(
            merchantID: merchantID, itemID: item.id, quantity: current + 1,
            idempotency: submissionKey126
        )
        if case .success(let updated) = result { cart = updated }
    }

    private func quantity(of itemID: String) -> Int {
        cart?.lines.first { $0.itemID == itemID }?.quantity ?? 0
    }

    // MARK: - Vues

    private var list: some View {
        List {
            ForEach(items) { item in
                row(item)
            }
            if nextCursor != nil {
                HStack { Spacer(); ProgressView(); Spacer() }
                    .financeLoadOnce { await loadMore() }
            }
        }
        .listStyle(.plain)
    }

    private func row(_ item: CommerceItem) -> some View {
        HStack(spacing: 12) {
            thumbnail(item)

            VStack(alignment: .leading, spacing: 3) {
                Text(item.nameKey).font(.subheadline.weight(.medium))
                Text(AmountEntry.format(item.unitPrice.majorUnitsForDisplay, item.unitPrice.currency.code))
                    .font(.caption).monospacedDigit()
                if let note = item.priceNoteKey {
                    Text(note).font(.caption2).foregroundStyle(.secondary)
                }
                // Un article épuisé reste visible avec son motif : le masquer
                // ferait croire qu'il n'a jamais existé.
                if !item.isOrderable {
                    Text(item.unavailableReasonKey ?? FinanceStrings.catalogUnavailable)
                        .font(.caption2).foregroundStyle(AppColors.statusWarning)
                } else if let stock = item.remainingStock, stock <= 5 {
                    Text(String(format: FinanceStrings.catalogLowStock, stock))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }

            Spacer()

            let inCart = quantity(of: item.id)
            if inCart > 0 {
                Text("×\(inCart)").font(.caption.weight(.semibold)).monospacedDigit()
            }
            Button { Task { await add(item) } } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.plain)
            .disabled(!item.isOrderable || pendingItemIDs.contains(item.id))
            .accessibilityLabel(FinanceStrings.catalogAdd)
        }
        .opacity(item.isOrderable ? 1 : 0.55)
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func thumbnail(_ item: CommerceItem) -> some View {
        if let url = item.imageURL {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.secondary.opacity(0.15)
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "shippingbox")
                .font(.title3).foregroundStyle(.secondary)
                .frame(width: 48, height: 48)
        }
    }
}
