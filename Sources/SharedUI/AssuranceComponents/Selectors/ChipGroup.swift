import SwiftUI

// MARK: - ChipGroup

struct ChipGroup<Item: Selectable>: View {
    let items: [Item]
    let mode: SelectionMode
    var scrollable: Bool = true

    @Binding var selectedItems: Set<Item>

    var body: some View {
        Group {
            if scrollable {
                ScrollView(.horizontal, showsIndicators: false) {
                    chipStack
                }
            } else {
                FlowLayout(spacing: AppSpacing.xs) {
                    chipContent
                }
            }
        }
    }

    private var chipStack: some View {
        HStack(spacing: AppSpacing.xs) {
            chipContent
        }
    }

    @ViewBuilder
    private var chipContent: some View {
        ForEach(items) { item in
            let isSelected = selectedItems.contains(item)
            Button { toggle(item) } label: {
                Text(item.displayName)
                    .font(.appButtonSmall)
                    .foregroundStyle(isSelected ? Color.white : Color.appText)
                    .padding(.horizontal, AppSpacing.sm)
                    .padding(.vertical, AppSpacing.xs)
                    .background(
                        Capsule()
                            .fill(isSelected ? Color.brandPrimary : Color.appSecondaryBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(isSelected ? Color.clear : Color.appBorder, lineWidth: 1)
                    )
            }
        }
    }

    private func toggle(_ item: Item) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch mode {
            case .single:
                selectedItems = [item]
            case .multi:
                if selectedItems.contains(item) {
                    selectedItems.remove(item)
                } else {
                    selectedItems.insert(item)
                }
            }
        }
    }
}

// MARK: - Preview

private struct PreviewChip: Selectable {
    let id: String
    let displayName: String
}

#Preview("ChipGroup") {
    struct Wrapper: View {
        @State private var single: Set<PreviewChip> = []
        @State private var multi: Set<PreviewChip> = []
        let items = ["Swift", "Kotlin", "Flutter", "React Native", "Dart"].enumerated().map {
            PreviewChip(id: "\($0.offset)", displayName: $0.element)
        }
        var body: some View {
            VStack(alignment: .leading, spacing: 24) {
                Text("Single Select").font(.appHeadline)
                ChipGroup(items: items, mode: .single, selectedItems: $single)

                Text("Multi Select (wrap)").font(.appHeadline)
                ChipGroup(items: items, mode: .multi, scrollable: false, selectedItems: $multi)
            }
            .padding()
        }
    }
    return Wrapper()
}
