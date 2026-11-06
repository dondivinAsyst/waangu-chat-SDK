import SwiftUI

public struct WizardReviewStep: View {
    let items: [WizardReviewItem]
    let onEditStep: (String) -> Void

    private let primaryLight = Color(hex: "#EEF4FF")
    private let borderColor  = Color(hex: "#E2E8F4")
    private let valueBg      = Color(hex: "#F4F7FC")

    private var sections: [(title: String, stepID: String, items: [WizardReviewItem])] {
        var result: [(title: String, stepID: String, items: [WizardReviewItem])] = []
        var currentStepID: String?

        for item in items {
            if item.stepID != currentStepID {
                result.append((
                    title: item.sectionTitle.isEmpty ? item.stepID : item.sectionTitle,
                    stepID: item.stepID,
                    items: [item]
                ))
                currentStepID = item.stepID
            } else {
                result[result.count - 1].items.append(item)
            }
        }
        return result
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.lg) {
            headerView
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionCard(section)
            }
        }
    }

    // MARK: - Header

    private var headerView: some View {
        VStack(spacing: AppSpacing.md) {
            ZStack {
                Circle()
                    .fill(primaryLight)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.brandPrimary, Color.brandPrimary.opacity(0.75)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
            }

            VStack(spacing: AppSpacing.xxxs) {
                Text("Récapitulatif")
                    .font(.appTitle2)
                    .foregroundStyle(Color.appText)
                Text("Vérifiez vos informations avant de continuer")
                    .font(.appSubheadline)
                    .foregroundStyle(Color.appSecondaryText)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Section Card

    private func sectionCard(_ section: (title: String, stepID: String, items: [WizardReviewItem])) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.md) {
            HStack(spacing: AppSpacing.xs) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppCornerRadius.xs)
                        .fill(primaryLight)
                        .frame(width: 32, height: 32)
                    Image(systemName: sectionIcon(for: section.stepID))
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                }

                Text(section.title)
                    .font(.appHeadline)
                    .foregroundStyle(Color.appText)

                Spacer()

                Button {
                    onEditStep(section.stepID)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "pencil")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Modifier")
                            .font(.appCaption2)
                            .fontWeight(.semibold)
                    }
                    .foregroundStyle(Color.brandPrimary)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xxs)
                    .background(primaryLight)
                    .clipShape(Capsule())
                }
            }

            let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.sm), count: 2)
            LazyVGrid(columns: columns, spacing: AppSpacing.sm) {
                ForEach(section.items) { item in
                    valueCard(item)
                }
            }
        }
        .padding(AppSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                .fill(Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppCornerRadius.lg)
                .stroke(borderColor, lineWidth: 1)
        )
        .appShadow(.sm)
    }

    // MARK: - Value Card

    private func valueCard(_ item: WizardReviewItem) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            HStack(spacing: AppSpacing.xxxs) {
                Image(systemName: fieldIcon(for: item.label))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.brandPrimary.opacity(0.6))
                Text(item.label)
                    .font(.appCaption1)
                    .foregroundStyle(Color.appSecondaryText)
            }

            Text(item.value.isEmpty ? "—" : item.value)
                .font(.appSubheadline)
                .fontWeight(.semibold)
                .foregroundStyle(Color.appText)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AppCornerRadius.md)
                .fill(valueBg)
        )
    }

    // MARK: - Icon Helpers

    private func sectionIcon(for stepID: String) -> String {
        switch stepID {
        case "plate_lookup": return "car.fill"
        case "mark_model": return "building.2.fill"
        case "vehicle_details": return "doc.text.fill"
        case "characteristics": return "slider.horizontal.3"
        case "owner": return "person.fill"
        case "vehicle_id": return "number.circle.fill"
        case "vehicle": return "car.side.fill"
        default: return "folder.fill"
        }
    }

    private func fieldIcon(for label: String) -> String {
        switch label {
        case "Plaque": return "car.fill"
        case "Marque": return "building.2"
        case "Modèle": return "car.side"
        case "N° de châssis": return "number"
        case "N° de moteur": return "engine.combustion"
        case "Valeur": return "banknote"
        case "Année": return "calendar"
        case "Places": return "person.2"
        case "Usage": return "road.lanes"
        case "Couleur": return "paintpalette"
        case "Catégorie": return "square.grid.2x2"
        case "Carburant": return "fuelpump"
        case "Nom": return "person"
        case "Prénom": return "person.text.rectangle"
        case "N° d'identité": return "creditcard"
        default: return "info.circle"
        }
    }
}
