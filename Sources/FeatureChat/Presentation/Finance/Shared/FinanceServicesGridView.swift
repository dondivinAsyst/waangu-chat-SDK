//
//  FinanceServicesGridView.swift
//  FeatureChat
//
//  Le reste du catalogue financier, en grille.
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

/// Tous les services que la page d'accueil ne met pas en avant.
///
/// En grille et non en liste : ces entrées ne se hiérarchisent pas entre elles.
/// Une liste impose un ordre de lecture — la première ligne paraît la plus
/// importante — alors que « Cash out » et « Facture » se valent. La grille les
/// donne d'un coup d'œil, ce qu'une liste de quinze lignes ne fait pas.
///
/// La feuille s'ouvre à **mi-hauteur** et se redimensionne au contenu. Une
/// version précédente occupait l'écran entier pour six tuiles, laissant les deux
/// tiers inférieurs vides : la feuille annonçait un contenu qu'elle n'avait pas.
struct FinanceServicesGridView: View {

    let entries: [FinanceCatalogEntry]
    let onSelect: (FinanceCatalogEntry) -> Void
    let onDismiss: () -> Void

    /// Trois colonnes **fixes**, et non adaptatives.
    ///
    /// `.adaptive` recalcule le nombre de colonnes selon la largeur : la grille
    /// passait de trois à deux colonnes entre deux tailles d'écran, et les
    /// tuiles changeaient de proportion avec elle. Trois colonnes tiennent de
    /// l'iPhone SE au Max, et gardent la même tuile partout.
    private static let columns = Array(
        repeating: GridItem(.flexible(), spacing: Metrics.gutter),
        count: 3
    )

    private enum Metrics {
        /// Gouttière un peu plus large depuis que les tuiles n'ont plus de
        /// pastille : sans le cercle, les glyphes se touchaient visuellement
        /// d'une colonne à l'autre.
        static let gutter: CGFloat = 12
        static let margin: CGFloat = 16
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            if entries.isEmpty { emptyState } else { grid }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(AppColors.walletCanvas)
        // Mi-hauteur d'abord : six tuiles n'occupent pas un écran, et une
        // feuille pleine pour un contenu court se lit comme un écran cassé.
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - En-tête

    /// Titre centré, fermeture en pastille à droite.
    ///
    /// Écrit plutôt que confié à `toolbar` : la barre système rend son bouton
    /// en capsule pleine largeur de texte, calée à gauche — elle pesait plus que
    /// le titre et déséquilibrait la feuille vers la gauche.
    private var header: some View {
        ZStack {
            Text(FinanceLocalization.string(
                "wallet_more_services", fallback: "Plus de services"))
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .accessibilityAddTraits(.isHeader)

            HStack {
                Spacer()
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(AppColors.subtitleGray)
                        .frame(width: 30, height: 30)
                        .background(AppColors.separator.opacity(0.3), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(FinanceLocalization.string(
                    "common_close", fallback: "Fermer"))
            }
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 18)
        .padding(.bottom, 16)
    }

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: Metrics.gutter) {
                ForEach(entries) { entry in
                    FinanceServiceTile(entry: entry) {
                        guard entry.isActionable() else { return }
                        onSelect(entry)
                    }
                }
            }
            .padding(.horizontal, Metrics.margin)
            .padding(.bottom, 24)
        }
    }

    /// Vide et **expliqué**.
    ///
    /// Un catalogue vide n'est pas une panne : c'est un marché où rien n'est
    /// ouvert, ou une session sans droits financiers. Afficher une erreur
    /// inviterait à réessayer sans fin.
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "creditcard.trianglebadge.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text(FinanceStrings.hubEmptyTitle)
                .font(.subheadline.weight(.medium))
            Text(FinanceStrings.hubEmptyDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 48)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Tuile

/// Une entrée du catalogue, en tuile de grille.
///
/// Contenu **centré** dans une tuile presque carrée. La version précédente
/// alignait en haut avec un ressort en pied : chaque tuile portait la moitié de
/// sa surface en vide sous le libellé, et la grille paraissait inachevée.
///
/// Une entrée fermée reste **visible et grisée**, avec son motif. La masquer
/// laisserait l'utilisateur la chercher puis conclure que l'application est
/// cassée ; lui dire pourquoi elle est fermée coûte une ligne.
private struct FinanceServiceTile: View {

    let entry: FinanceCatalogEntry
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    private var isActionable: Bool { entry.isActionable() }

    /// Presque carrée aux corps de texte courants, et libre de s'étirer au-delà.
    ///
    /// Une hauteur fixe couperait le libellé aux grandes tailles de caractères ;
    /// une hauteur uniquement dictée par le contenu ferait une grille de tuiles
    /// inégales. Un minimum, donc, et pas un maximum.
    private var minHeight: CGFloat {
        typeSize.isAccessibilitySize ? 146 : 104
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 7) {
                icon

                Text(FinanceLocalization.entryShortTitle(entry))
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.1)
                    .foregroundStyle(isActionable ? AppColors.textPrimary : AppColors.subtitleGray)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)

                if !isActionable, let reason = entry.unavailableReasonKey {
                    Text(FinanceLocalization.entryReason(reason))
                        .font(.system(size: 11))
                        .foregroundStyle(AppColors.subtitleGray)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: minHeight)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(AppColors.cardBackground)
            )
            // Un liseré et une ombre courte : la carte blanche sur fond gris
            // clair ne se détachait pas, et les tuiles flottaient sans support.
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(AppColors.separator.opacity(0.45), lineWidth: 0.5)
            )
            // Ombre réduite à un souffle : posée plus franchement, elle
            // détachait chaque tuile comme un bouton flottant, là où une grille
            // de services se lit mieux à plat.
            .shadow(color: .black.opacity(0.03), radius: 3, y: 1)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(FinanceTilePressStyle())
        .disabled(!isActionable)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(isActionable ? .isButton : [])
    }

    /// Le glyphe **nu**, sans pastille derrière lui.
    ///
    /// Le médaillon teinté qui l'entourait donnait à la grille l'aspect
    /// générique d'un gabarit : neuf ronds bleu pâle identiques, où seule
    /// l'icône changeait. Sans lui, c'est le dessin qui distingue les services,
    /// et la tuile respire — le trait passe de 22 à 26 pt pour tenir la place
    /// que le cercle occupait.
    ///
    /// Une entrée fermée garde son cadenas, en petit, contre le glyphe : le gris
    /// seul se confond avec une icône peu contrastée et ne dit pas qu'elle est
    /// fermée.
    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Image(systemName: entry.iconName)
                .font(.system(size: 26, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isActionable ? AppColors.primary : AppColors.subtitleGray)
                .frame(width: 44, height: 40)

            if !isActionable {
                Image(systemName: "lock.fill")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(AppColors.subtitleGray, in: Circle())
                    .overlay(Circle().stroke(AppColors.cardBackground, lineWidth: 2))
                    .offset(x: 2, y: 2)
            }
        }
    }

    /// VoiceOver doit annoncer l'indisponibilité **et son motif** : un bouton
    /// annoncé sans mention de son état laisse l'utilisateur le tapoter en vain.
    private var accessibilityLabel: String {
        let title = FinanceLocalization.entryTitle(entry)
        guard !isActionable else { return title }
        let reason = entry.unavailableReasonKey.map(FinanceLocalization.entryReason)
            ?? FinanceLocalization.string("entry_unavailable", fallback: "indisponible")
        return "\(title), \(reason)"
    }
}

// MARK: - Retour tactile

/// Enfoncement léger à l'appui.
///
/// `.plain` ne donne aucun retour sur une tuile : l'appui restait sans effet
/// visible jusqu'à l'ouverture de l'écran suivant, ce qui fait retaper.
private struct FinanceTilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
