//
//  FundingSourcePicker.swift
//  SharedUI
//
//  Choix de la source d'un paiement.
//

import SwiftUI

/// Ligne indiquant d'où part l'argent, dépliable en menu.
///
/// **Toujours visible, même quand il n'y a qu'une source.** Un paiement sans
/// source affichée laisse deviner lequel de ses comptes sera débité, et
/// l'utilisateur ne s'en aperçoit qu'au relevé. La ligne répond à la question
/// avant qu'elle se pose.
///
/// Les sources indisponibles restent **listées et grisées**, avec leur motif :
/// une source absente se cherche, une source expliquée se comprend.
public struct FundingSourcePicker<Source: Identifiable & Equatable>: View {

    /// Ce que la vue a besoin de savoir d'une source, sans connaître son type.
    ///
    /// Un descripteur plutôt qu'un import de CoreKit : `SharedUI` n'en dépend
    /// pas, et ce composant n'a pas de raison d'être le premier à l'exiger.
    public struct Descriptor {
        public let title: String
        public let subtitle: String?
        public let symbol: String
        public let isUsable: Bool

        public init(title: String, subtitle: String?, symbol: String, isUsable: Bool) {
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.isUsable = isUsable
        }
    }

    public let label: String
    public let sources: [Source]
    @Binding public var selection: Source?
    public let describe: (Source) -> Descriptor

    public init(label: String,
                sources: [Source],
                selection: Binding<Source?>,
                describe: @escaping (Source) -> Descriptor) {
        self.label = label
        self.sources = sources
        self._selection = selection
        self.describe = describe
    }

    public var body: some View {
        Menu {
            ForEach(sources) { source in
                let descriptor = describe(source)
                Button {
                    guard descriptor.isUsable else { return }
                    selection = source
                } label: {
                    // Le motif d'indisponibilité passe en second libellé du
                    // menu : c'est le seul endroit où l'utilisateur le lira
                    // avant de comprendre pourquoi rien ne se passe.
                    Label {
                        Text(descriptor.subtitle.map { "\(descriptor.title) — \($0)" }
                             ?? descriptor.title)
                    } icon: {
                        Image(systemName: descriptor.symbol)
                    }
                }
                .disabled(!descriptor.isUsable)
            }
        } label: {
            row
        }
        // Une seule source : la ligne informe sans prétendre qu'on peut choisir.
        .disabled(sources.count <= 1)
        .accessibilityLabel(label)
        .accessibilityValue(selection.map { describe($0).title } ?? "")
    }

    private var row: some View {
        HStack(spacing: 10) {
            Image(systemName: selection.map { describe($0).symbol } ?? "wallet.bifold")
                .font(.system(size: 17))
                .foregroundStyle(AppColors.primary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.subtitleGray)

                Text(selection.map { describe($0).title } ?? "—")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if let subtitle = selection.flatMap({ describe($0).subtitle }) {
                Text(subtitle)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)
            }

            if sources.count > 1 {
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.subtitleGray)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(AppColors.cardBackground,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
}
