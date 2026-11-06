// MARK: - SharedUI/Components/WSelectableField.swift

import SwiftUI

public struct WSelectableField: View {
    public let label: String
    public let value: String?
    public let items: [String]
    public let onSelect: (String) -> Void

    @State private var showSheet = false

    public init(label: String, value: String?, items: [String], onSelect: @escaping (String) -> Void) {
        self.label = label
        self.value = value
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.gray)

            Button {
                showSheet = true
            } label: {
                HStack {
                    Text(value ?? "Sélectionner…")
                        .foregroundColor(value == nil ? .gray : .primary)

                    Spacer()
                    Image(systemName: "chevron.down")
                        .foregroundColor(.gray)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
        }
        .sheet(isPresented: $showSheet) {
            WSelectableSheet(
                title: label,
                items: items,
                onSelect: { selected in
                    onSelect(selected)
                    showSheet = false
                }
            )
            .presentationDetentsDynamic(itemsCount: items.count)
        }
    }
}

// MARK: - Selection Sheet

public struct WSelectableSheet: View {
    public let title: String
    public let items: [String]
    public let onSelect: (String) -> Void

    public init(title: String, items: [String], onSelect: @escaping (String) -> Void) {
        self.title = title
        self.items = items
        self.onSelect = onSelect
    }

    public var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding()

            Divider()

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(items, id: \.self) { item in
                        Button {
                            onSelect(item)
                        } label: {
                            HStack {
                                Text(item)
                                Spacer()
                            }
                            .padding()
                        }
                        Divider()
                    }
                }
            }
        }
    }
}
