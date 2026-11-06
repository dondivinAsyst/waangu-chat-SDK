//
//  FinanceDetailRows.swift
//  FeatureChat
//
//  Lignes de détail des écrans financiers, sans décor.
//

import SwiftUI
import UIKit
import WaanguSharedUI

/// Un libellé et sa valeur, sur une ligne.
///
/// Sans fond ni carte : les lignes se séparent par des filets, et la hiérarchie
/// vient de la typographie — libellé gris, valeur en noir.
struct FinanceDetailRow: View {

    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(size: 15))
                .foregroundStyle(AppColors.subtitleGray)
            Spacer(minLength: 8)
            Text(value)
                .font(monospaced ? .system(size: 15, design: .monospaced) : .system(size: 15))
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}

/// La référence d'une opération, tronquée au milieu, avec son bouton de copie.
///
/// Tronquée plutôt que coupée sur deux lignes : un identifiant se reconnaît à
/// son début et à sa fin, et la copie en donne l'intégralité — c'est ce que le
/// support demandera.
struct FinanceReferenceRow: View {

    let reference: String

    @State private var copied = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(FinanceStrings.receiptReference)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)
                Text(reference)
                    .font(.system(size: 15, design: .monospaced))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 8)

            Button {
                UIPasteboard.general.string = reference
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation(.easeOut(duration: 0.15)) { copied = false }
                }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 16))
                    .foregroundStyle(copied ? AppColors.primary : AppColors.subtitleGray)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(copied ? FinanceStrings.referenceCopied : FinanceStrings.referenceCopy)
        }
        .padding(.vertical, 6)
    }
}

/// Une action secondaire : icône grise, titre, chevron. Sans pastille ni carte.
struct FinanceLinkRow: View {

    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17))
                    .foregroundStyle(AppColors.subtitleGray)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 16))
                    .foregroundStyle(AppColors.textPrimary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColors.subtitleGray.opacity(0.6))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Filet de séparation entre lignes.
struct FinanceHairline: View {
    var body: some View {
        AppColors.separator.frame(height: 0.5)
    }
}
