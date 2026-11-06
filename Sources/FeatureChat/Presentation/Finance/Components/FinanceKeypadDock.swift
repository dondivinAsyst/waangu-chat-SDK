//
//  FinanceKeypadDock.swift
//  FeatureChat
//
//  Un pavé numérique que le clavier système recouvre, sans jamais le retirer.
//

import SwiftUI
import UIKit

/// Contenu défilant au-dessus d'un socle fixe — le bouton et le pavé.
///
/// **Le clavier recouvre le socle ; il ne le fait pas disparaître.** Les écrans
/// retiraient le pavé dès que le motif prenait le focus : la mise en page sautait
/// à l'ouverture comme à la fermeture du clavier, et le pavé semblait perdu.
///
/// L'évitement automatique du clavier ne convient pas ici : il rétrécit tout
/// l'écran, socle compris, et écrasait le montant pour loger le pavé au-dessus
/// du clavier. Le socle ignore donc le clavier, et seul le contenu lui cède la
/// place — de la hauteur mesurée du chevauchement, ce qui reste juste avec un
/// clavier matériel (aucun chevauchement) comme sur iPad.
struct FinanceKeypadDock<Content: View, Dock: View>: View {

    @ViewBuilder let content: () -> Content
    @ViewBuilder let dock: () -> Dock

    @State private var dockHeight: CGFloat = 0
    @State private var keyboardOverlap: CGFloat = 0
    /// Bas de cette vue en coordonnées globales — celles du cadre du clavier.
    @State private var bottomY: CGFloat = 0
    @State private var keyboardTopY: CGFloat?

    /// Le contenu s'arrête au plus haut des deux : le haut du socle, ou le haut
    /// du clavier.
    private var contentInset: CGFloat { max(dockHeight, keyboardOverlap) }

    var body: some View {
        ZStack(alignment: .bottom) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.bottom, contentInset)
                .environment(\.financeKeyboardOverlap, keyboardOverlap)

            dock()
                // Hauteur idéale, jamais celle de l'écran : un `ZStack` propose
                // tout l'espace à chaque enfant, et un socle qui s'y étire
                // mesurait tout l'écran — le contenu, décalé d'autant, disparaissait.
                .fixedSize(horizontal: false, vertical: true)
                .background(
                    GeometryReader { proxy in
                        Color.clear
                            .onAppear { dockHeight = proxy.size.height }
                            .onChange(of: proxy.size.height) { _, height in dockHeight = height }
                    }
                )
        }
        .background(
            GeometryReader { proxy in
                Color.clear
                    .onAppear { bottomY = proxy.frame(in: .global).maxY; recomputeOverlap() }
                    .onChange(of: proxy.frame(in: .global).maxY) { _, maxY in
                        bottomY = maxY
                        recomputeOverlap()
                    }
            }
        )
        // Ni le contenu ni le socle ne suivent le clavier d'eux-mêmes : le
        // chevauchement est appliqué à la main, au seul contenu.
        .ignoresSafeArea(.keyboard, edges: .bottom)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) {
            keyboardTopY = ($0.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.minY
            recomputeOverlap()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardTopY = nil
            recomputeOverlap()
        }
    }

    private func recomputeOverlap() {
        let overlap = keyboardTopY.map { max(0, bottomY - $0) } ?? 0
        guard overlap != keyboardOverlap else { return }
        withAnimation(.easeOut(duration: 0.25)) { keyboardOverlap = overlap }
    }
}

// MARK: - Environnement

private struct FinanceKeyboardOverlapKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// Hauteur du clavier au-dessus du bas de la zone de saisie. `0` sans clavier.
    var financeKeyboardOverlap: CGFloat {
        get { self[FinanceKeyboardOverlapKey.self] }
        set { self[FinanceKeyboardOverlapKey.self] = newValue }
    }
}

// MARK: - Fermeture du clavier

extension View {

    /// Ferme le clavier quand on touche une zone **vide** de ce conteneur.
    ///
    /// Posé en arrière-plan plutôt qu'en geste sur la vue entière : un geste
    /// global se déclencherait aussi en touchant le champ lui-même, et le focus
    /// clignoterait — pris par le champ, aussitôt retiré par le geste. En
    /// arrière-plan, le champ et les boutons reçoivent leurs propres touches.
    func financeDismissesKeyboardOnBackgroundTap(_ dismiss: @escaping () -> Void) -> some View {
        background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: dismiss)
        )
    }

    /// Fait défiler `id` au-dessus du clavier une fois celui-ci en place.
    ///
    /// Déclenché sur le chevauchement et non sur le focus : au moment où le
    /// focus change, le contenu n'a pas encore cédé la place, et le défilement
    /// viserait une zone que le clavier va recouvrir.
    func financeScrollsIntoView<ID: Hashable>(
        _ id: ID,
        whileFocused isFocused: Bool,
        using proxy: ScrollViewProxy
    ) -> some View {
        modifier(FinanceScrollFocusedIntoView(id: id, isFocused: isFocused, proxy: proxy))
    }

    /// « OK » au-dessus du clavier, pour un champ multiligne : sa touche Retour
    /// insère une ligne, et sans ce bouton le clavier ne se fermerait jamais.
    func financeKeyboardDoneButton(_ dismiss: @escaping () -> Void) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(FinanceStrings.keyboardDone, action: dismiss)
                    .fontWeight(.semibold)
            }
        }
    }
}

private struct FinanceScrollFocusedIntoView<ID: Hashable>: ViewModifier {
    let id: ID
    let isFocused: Bool
    let proxy: ScrollViewProxy

    @Environment(\.financeKeyboardOverlap) private var overlap

    func body(content: Content) -> some View {
        content.onChange(of: overlap) { _, newOverlap in
            guard isFocused, newOverlap > 0 else { return }
            withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(id, anchor: .bottom) }
        }
    }
}
