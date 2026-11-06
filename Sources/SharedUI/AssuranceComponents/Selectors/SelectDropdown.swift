import SwiftUI

// MARK: - Selectable Protocol

protocol Selectable: Identifiable, Hashable {
    var displayName: String { get }
}

// MARK: - Selection Mode

enum SelectionMode {
    case single
    case multi
}

// MARK: - SelectDropdown

struct SelectDropdown1<Item: Selectable>: View {
    let label: String
    let placeholder: String
    let items: [Item]
    let mode: SelectionMode
    var searchable: Bool? = nil
    var errorMessage: String? = nil

    @Binding var selectedItems: Set<Item>
    @State private var isExpanded = false
    @State private var searchText = ""

    private var hasError: Bool { errorMessage != nil }

    private var shouldShowSearch: Bool {
        searchable ?? (items.count > 5)
    }

    private var filteredItems: [Item] {
        if searchText.isEmpty { return items }
        return items.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var displayText: String {
        if selectedItems.isEmpty { return placeholder }
        switch mode {
        case .single:
            return selectedItems.first?.displayName ?? placeholder
        case .multi:
            if selectedItems.count <= 2 {
                return selectedItems.map(\.displayName).joined(separator: ", ")
            }
            return "\(selectedItems.count) selected"
        }
    }

    private let maxListHeight: CGFloat = 400
    private let estimatedRowHeight: CGFloat = 44
    private let searchBarHeight: CGFloat = 52

    private var sheetContentHeight: CGFloat {
        let headerHeight: CGFloat = label.isEmpty ? 0 : 56
        let searchHeight: CGFloat = shouldShowSearch ? searchBarHeight : 0
        let rowsHeight = CGFloat(items.count) * estimatedRowHeight
        let listHeight = min(rowsHeight, maxListHeight)
        let padding: CGFloat = 40
        return headerHeight + searchHeight + listHeight + padding
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xxs) {
            if !label.isEmpty {
                Text(label)
                    .font(.appInputLabel)
                    .foregroundStyle(hasError ? Color.appError : Color.appSecondaryText)
            }

            Button { isExpanded = true } label: {
                HStack {
                    Text(displayText)
                        .font(.appInputText)
                        .foregroundStyle(selectedItems.isEmpty ? Color.appPlaceholder : Color.appText)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: AppIcons.chevronDown)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.appSecondaryText)
                }
                .padding(.horizontal, AppSpacing.sm)
                .frame(height: 48)
                .background(
                    RoundedRectangle(cornerRadius: AppCornerRadius.md)
                        .stroke(
                            hasError ? Color.appError : Color.appBorder,
                            lineWidth: hasError ? 1.5 : 1
                        )
                )
            }

            if mode == .multi && !selectedItems.isEmpty {
                FlowLayout(spacing: AppSpacing.xxs) {
                    ForEach(Array(selectedItems)) { item in
                        chipView(for: item)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.appInputError)
                    .foregroundStyle(Color.appError)
            }
        }
        .sheet(isPresented: $isExpanded, onDismiss: { searchText = "" }) {
            VStack(spacing: 0) {
                if !label.isEmpty {
                    HStack {
                        Text(label)
                            .font(.appTitle3)
                            .foregroundStyle(Color.appText)
                        Spacer()
                        Button { isExpanded = false } label: {
                            Image(systemName: AppIcons.close)
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Color.appSecondaryText)
                                .frame(width: 32, height: 32)
                                .background(Color.appSecondaryBackground)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                }

                if shouldShowSearch {
                    HStack(spacing: AppSpacing.xs) {
                        Image(systemName: AppIcons.search)
                            .foregroundStyle(Color.appPlaceholder)
                        TextField("Search...", text: $searchText)
                            .font(.appSubheadline)
                    }
                    .padding(AppSpacing.sm)
                    .background(Color.appSecondaryBackground)
                    .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.sm))
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.top, AppSpacing.sm)
                }

                if filteredItems.isEmpty {
                    Text("No results found")
                        .font(.appFootnote)
                        .foregroundStyle(Color.appSecondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppSpacing.lg)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredItems) { item in
                                rowView(for: item)
                                if item.id != filteredItems.last?.id {
                                    Divider().padding(.leading, AppSpacing.md)
                                }
                            }
                        }
                    }
                    .padding(.top, AppSpacing.xs)
                }
            }
            .padding(.bottom, AppSpacing.lg)
            .presentationDetents([.height(sheetContentHeight)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(AppCornerRadius.xl)
            .presentationBackground(Color.appBackground)
        }
    }

    // MARK: - Row

    private func rowView(for item: Item) -> some View {
        Button { toggle(item) } label: {
            HStack {
                Text(item.displayName)
                    .font(.appBody)
                    .foregroundStyle(Color.appText)
                Spacer()
                if selectedItems.contains(item) {
                    Image(systemName: mode == .single ? "circle.inset.filled" : "checkmark.square.fill")
                        .foregroundStyle(Color.brandPrimary)
                } else {
                    Image(systemName: mode == .single ? "circle" : "square")
                        .foregroundStyle(Color.appBorder)
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
            .contentShape(Rectangle())
        }
    }

    // MARK: - Chip

    private func chipView(for item: Item) -> some View {
        HStack(spacing: AppSpacing.xxxs) {
            Text(item.displayName)
                .font(.appCaption1)
                .foregroundStyle(Color.brandPrimary)
            Button { toggle(item) } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.brandPrimary.opacity(0.6))
            }
        }
        .padding(.horizontal, AppSpacing.xs)
        .padding(.vertical, AppSpacing.xxxs)
        .background(Capsule().fill(Color.brandPrimary.opacity(0.1)))
    }

    // MARK: - Toggle

    private func toggle(_ item: Item) {
        withAnimation(.easeInOut(duration: 0.2)) {
            switch mode {
            case .single:
                selectedItems = [item]
                isExpanded = false
                searchText = ""
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

// MARK: - FlowLayout (chips wrapping)

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = computeLayout(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private struct LayoutResult {
        var positions: [CGPoint]
        var size: CGSize
    }

    private func computeLayout(proposal: ProposedViewSize, subviews: Subviews) -> LayoutResult {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            totalHeight = currentY + lineHeight
        }
        return LayoutResult(positions: positions, size: CGSize(width: maxWidth, height: totalHeight))
    }
}

// MARK: - Preview Helpers

private struct PreviewItem: Selectable {
    let id: String
    let displayName: String
}

#Preview("SelectDropdown") {
    struct PreviewWrapper: View {
        @State private var single: Set<PreviewItem> = []
        @State private var multi: Set<PreviewItem> = []

        let items = [
            PreviewItem(id: "1", displayName: "Kenya"),
            PreviewItem(id: "2", displayName: "Uganda"),
            PreviewItem(id: "3", displayName: "Tanzania"),
            PreviewItem(id: "4", displayName: "Rwanda"),
            PreviewItem(id: "5", displayName: "Ethiopia"),
            PreviewItem(id: "6", displayName: "Nigeria"),
        ]

        var body: some View {
            ScrollView {
                VStack(spacing: 24) {
                    SelectDropdown1(
                        label: "Country",
                        placeholder: "Select a country",
                        items: items,
                        mode: .single,
                        selectedItems: $single
                    )

                    SelectDropdown1(
                        label: "Countries you've visited",
                        placeholder: "Select countries",
                        items: items,
                        mode: .multi,
                        selectedItems: $multi
                    )
                }
                .padding()
            }
        }
    }
    return PreviewWrapper()
}
