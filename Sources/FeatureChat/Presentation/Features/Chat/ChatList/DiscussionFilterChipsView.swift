//
//  DiscussionFilterChipsView.swift
//  FeatureChat
//

import SwiftUI
import UIKit
import WaanguSharedUI
import WaanguCoreKit

struct DiscussionFilterChipsView: View {
    let items: [DiscussionFilterItem]
    let selectedFilter: DiscussionFilter
    let onSelect: (DiscussionFilter) -> Void
    let onAddList: () -> Void
    let onDeleteList: (DiscussionFilter) -> Void
    let translationService: (any TranslationServiceProtocol)?
    let localeToken: Int
    /// Faux tant que la liste n'a pas fini sa première lecture : « Tout 0 »
    /// affirmerait qu'il n'y a aucune conversation.
    let showsCounts: Bool

    init(
        items: [DiscussionFilterItem],
        selectedFilter: DiscussionFilter,
        translationService: (any TranslationServiceProtocol)? = nil,
        localeToken: Int = 0,
        showsCounts: Bool = true,
        onSelect: @escaping (DiscussionFilter) -> Void,
        onAddList: @escaping () -> Void,
        onDeleteList: @escaping (DiscussionFilter) -> Void
    ) {
        self.items = items
        self.selectedFilter = selectedFilter
        self.translationService = translationService
        self.localeToken = localeToken
        self.showsCounts = showsCounts
        self.onSelect = onSelect
        self.onAddList = onAddList
        self.onDeleteList = onDeleteList
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    filterChip(item)
                }
                addListChip
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .id(localeToken)
    }

    @ViewBuilder
    private func filterChip(_ item: DiscussionFilterItem) -> some View {
        let isSelected = selectedFilter == item.filter
        let chip = chipLabel(item: item, isSelected: isSelected)
            .contentShape(Capsule())
            .onTapGesture {
                onSelect(item.filter)
            }

        if case .customList = item.filter {
            chip
                .highPriorityGesture(
                    LongPressGesture(minimumDuration: 0.35)
                        .onEnded { _ in
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            onDeleteList(item.filter)
                        }
                )
        } else {
            chip
        }
    }

    private func chipLabel(item: DiscussionFilterItem, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            Text(resolvedTitle(for: item.filter))
                .font(.subheadline.weight(isSelected ? .semibold : .regular))
            if showsCounts {
                Text("\(item.count)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(isSelected ? AppColors.primary : AppColors.subtitleGray)
            }
        }
        .foregroundColor(isSelected ? AppColors.primary : AppColors.textPrimary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(
            Capsule()
                .fill(isSelected ? AppColors.primary.opacity(0.14) : Color(.systemGray6))
        )
        .overlay(
            Capsule()
                .stroke(isSelected ? AppColors.primary.opacity(0.35) : Color.clear, lineWidth: 1)
        )
    }

    private var addListChip: some View {
        Button(action: onAddList) {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(AppColors.subtitleGray)
                .frame(width: 36, height: 36)
                .background(Circle().fill(Color(.systemGray6)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(t(ChatTranslationKeys.FILTER_ADD_LIST))
    }

    private func resolvedTitle(for filter: DiscussionFilter) -> String {
        if let key = filter.translationKey {
            return t(key)
        }
        if case .customList(_, let name) = filter {
            return name
        }
        return filter.title
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
