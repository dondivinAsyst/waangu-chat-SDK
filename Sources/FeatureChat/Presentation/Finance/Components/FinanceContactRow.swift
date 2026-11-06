//
//  FinanceContactRow.swift
//  FeatureChat
//
//  Une carte de contact, pour choisir un bénéficiaire ou des participants.
//

import SwiftUI
import WaanguSharedUI

/// Un contact présenté en carte : avatar, nom, numéro, et un accessoire.
///
/// Partagée par le choix d'un bénéficiaire et par celui des participants d'un
/// partage — deux listes qui posent la même question, « qui ? », et qui ne
/// doivent pas se dessiner différemment.
///
/// Toutes les teintes viennent de `AppColors`, qui porte leurs variantes
/// sombres : aucune couleur n'est fixée ici.
struct FinanceContactRow<Accessory: View>: View {

    let contact: UserContactProps
    var isHighlighted = false
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        HStack(spacing: 14) {
            avatar

            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                Text(contact.isBlocked ? FinanceStrings.recipientBlocked : contact.phone)
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.subtitleGray)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            accessory()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(isHighlighted ? AppColors.primary : AppColors.separator.opacity(0.5),
                              lineWidth: isHighlighted ? 1.5 : 0.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // Un contact bloqué reste visible mais non sélectionnable : le masquer
        // laisserait croire à une erreur d'annuaire.
        .opacity(contact.isBlocked ? 0.5 : 1)
        .accessibilityElement(children: .combine)
    }

    private var avatar: some View {
        ZStack {
            Circle().fill(AppColors.primary.opacity(0.14))
            if let url = contact.avatar.flatMap(URL.init(string:)), contact.avatar?.isEmpty == false {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    initial
                }
                .clipShape(Circle())
            } else {
                initial
            }
        }
        .frame(width: 46, height: 46)
    }

    private var initial: some View {
        Text(String(contact.name.prefix(1)).uppercased())
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(AppColors.primary)
    }
}

/// Le chevron d'une ligne qui ouvre la suite.
struct FinanceContactChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(AppColors.subtitleGray)
    }
}

/// La liste de cartes, sur le fond des écrans financiers.
///
/// Une `ScrollView` plutôt qu'une `List` : la liste imposait ses séparateurs
/// pleine largeur et son fond blanc, sans marge ni coins — c'est ce qui donnait
/// à ces écrans l'air d'un tableau brut.
struct FinanceContactList<Row: View>: View {

    let contacts: [UserContactProps]
    @ViewBuilder let row: (UserContactProps) -> Row

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(contacts, id: \.userId) { contact in
                    row(contact)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(AppColors.walletCanvas)
    }
}

/// L'état vide d'une liste de contacts : icône, phrase, et une piste.
struct FinanceContactsEmptyState: View {
    let icon: String
    let title: String
    var hint: String?

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(AppColors.primary.opacity(0.12))
                Image(systemName: icon)
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(AppColors.primary)
            }
            .frame(width: 72, height: 72)

            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            if let hint {
                Text(hint)
                    .font(.subheadline)
                    .foregroundStyle(AppColors.subtitleGray)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.walletCanvas)
    }
}
