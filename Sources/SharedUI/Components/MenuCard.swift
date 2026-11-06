//
//  MenuItem.swift
//  AppModules
//
//  Created by Asyst on 5/31/26.
//
import SwiftUI


public struct MenuCard<Action: Equatable>: View {
    public let items: [MenuItem<Action>]
    public let destructiveActions: [Action]
    public let onTap: (Action) -> Void

    public init(
        items: [MenuItem<Action>],
        destructiveActions: [Action] = [],
        onTap: @escaping (Action) -> Void
    ) {
        self.items = items
        self.destructiveActions = destructiveActions
        self.onTap = onTap
    }

    public var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                MenuRow(
                    item: item,
                    isDestructive: destructiveActions.contains(item.action),
                    onTap: { onTap(item.action) }
                )

                if index < items.count - 1 {
                    Divider()
                        .padding(.leading, 66)
                }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.06), radius: 10, y: 4)
        )
    }
}

// MARK: - Reusable MenuRow

public struct MenuRow<Action: Equatable>: View {
    let item: MenuItem<Action>
    var isDestructive: Bool = false
    let onTap: () -> Void

    public var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Image(systemName: item.icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color(.systemGray6)))

                Text(item.title)
                    .font(.system(size: 16))
                    .foregroundColor(isDestructive ? Color(red: 0.85, green: 0.25, blue: 0.25) : .primary)

                Spacer()

                if item.showChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color(.tertiaryLabel))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Generic MenuItem

public struct MenuItem<Action: Equatable>: Identifiable {
    public let id: UUID
    public let icon: String
    public let title: String
    public let showChevron: Bool
    public let action: Action

    public init(
        id: UUID = UUID(),
        icon: String,
        title: String,
        showChevron: Bool = true,
        action: Action
    ) {
        self.id = id
        self.icon = icon
        self.title = title
        self.showChevron = showChevron
        self.action = action
    }
}
