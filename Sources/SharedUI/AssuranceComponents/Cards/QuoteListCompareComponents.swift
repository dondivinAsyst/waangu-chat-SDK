import SwiftUI
import Combine

public struct QuoteListSection<Item: Identifiable, RowContent: View>: View {
    let items: [Item]
    let isLoading: Bool
    let loadError: String?
    let emptyIcon: String
    let emptyTitle: String
    let emptyMessage: String
    let onRetry: () -> Void
    let rowContent: (Item) -> RowContent
    
    public init(items: [Item], isLoading: Bool, loadError: String?, emptyIcon: String, emptyTitle: String, emptyMessage: String, onRetry: @escaping () -> Void, rowContent: @escaping (Item) -> RowContent) {
        self.items = items
        self.isLoading = isLoading
        self.loadError = loadError
        self.emptyIcon = emptyIcon
        self.emptyTitle = emptyTitle
        self.emptyMessage = emptyMessage
        self.onRetry = onRetry
        self.rowContent = rowContent
    }

    public var body: some View {
        VStack(spacing: AppSpacing.md) {
            if isLoading {
                ForEach(0..<3, id: \.self) { _ in
                    SkeletonView()
                        .frame(height: 140)
                        .clipShape(RoundedRectangle(cornerRadius: AppCornerRadius.lg))
                }
            } else if let error = loadError {
                ErrorStateView(message: error, onRetry: onRetry)
            } else if items.isEmpty {
                EmptyStateView(icon: emptyIcon, title: emptyTitle, message: emptyMessage)
            } else {
                ForEach(items) { item in
                    rowContent(item)
                }
            }
        }
    }
}

public struct CompareFloatingBar: View {
    let title: String
    let selectedCount: Int
    let maxCount: Int
    let canCompare: Bool
    let onCancel: () -> Void
    let onCompare: () -> Void

    private let borderColor = Color(hex: "#E2E8F4")
    
    public init(title: String, selectedCount: Int, maxCount: Int, canCompare: Bool, onCancel: @escaping () -> Void, onCompare: @escaping () -> Void) {
        self.title = title
        self.selectedCount = selectedCount
        self.maxCount = maxCount
        self.canCompare = canCompare
        self.onCancel = onCancel
        self.onCompare = onCompare
    }

   public var body: some View {
        VStack(spacing: 0) {
            Divider().overlay(borderColor)
            HStack(spacing: AppSpacing.md) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.appSubheadline)
                        .fontWeight(.semibold)
                        .foregroundStyle(Color.appText)
                    Text("\(selectedCount)/\(maxCount) selectionnees")
                        .font(.appCaption1)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Spacer()

                Button(action: onCancel) {
                    Text("Annuler")
                        .font(.appButtonSmall)
                        .foregroundStyle(Color.appSecondaryText)
                }

                Button(action: onCompare) {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.left.arrow.right")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Comparer")
                            .font(.appButtonMedium)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, AppSpacing.md)
                    .padding(.vertical, AppSpacing.sm)
                    .background(
                        RoundedRectangle(cornerRadius: AppCornerRadius.md)
                            .fill(canCompare ? Color.brandPrimary : Color.appDisabled)
                    )
                }
                .disabled(!canCompare)
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.vertical, AppSpacing.sm)
        }
        .background(
            Color.white
                .shadow(color: .black.opacity(0.08), radius: 8, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}
