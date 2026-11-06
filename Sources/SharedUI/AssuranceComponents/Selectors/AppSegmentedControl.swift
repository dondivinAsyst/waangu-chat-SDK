import SwiftUI

// MARK: - AppSegmentedControl

struct AppSegmentedControl<Item: Selectable>: View {
    let items: [Item]
    @Binding var selected: Item

    @Namespace private var animation

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                let isSelected = item == selected
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selected = item
                    }
                } label: {
                    Text(item.displayName)
                        .font(.appButtonSmall)
                        .foregroundStyle(isSelected ? Color.white : Color.appSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.xs)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.brandPrimary)
                                    .matchedGeometryEffect(id: "segment", in: animation)
                            }
                        }
                }
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.appSecondaryBackground))
    }
}

// MARK: - Preview

private struct SegmentItem: Selectable {
    let id: String
    let displayName: String
}

#Preview("SegmentedControl") {
    struct Wrapper: View {
        let items = [
            SegmentItem(id: "1", displayName: "Daily"),
            SegmentItem(id: "2", displayName: "Weekly"),
            SegmentItem(id: "3", displayName: "Monthly"),
        ]
        @State private var selected: SegmentItem

        init() {
            let items = [
                SegmentItem(id: "1", displayName: "Daily"),
                SegmentItem(id: "2", displayName: "Weekly"),
                SegmentItem(id: "3", displayName: "Monthly"),
            ]
            _selected = State(initialValue: items[0])
        }

        var body: some View {
            AppSegmentedControl(items: items, selected: $selected)
                .padding()
        }
    }
    return Wrapper()
}
