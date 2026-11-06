//
//  ReactionEmojiPickerSheet.swift
//  FeatureChat
//
//  Full emoji grid for choosing a custom reaction (opened from the reaction bar + button).
//

import SwiftUI
import WaanguCoreKit
import WaanguSharedUI

struct ReactionEmojiPickerSheet: View {
    let translationService: (any TranslationServiceProtocol)?
    let onSelect: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedCategory: EmojiCategory = .smileys
    @State private var searchText = ""
    @State private var recentEmojis: [String] = []

    private var filteredCategories: [EmojiCategory] {
        EmojiCategory.allCases.filter { category in
            if category == .recent { return !recentEmojis.isEmpty }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                emojiScroll
                Divider()
                categoryTabs
            }
            .background(Color(.systemBackground))
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onAppear {
            if let saved = UserDefaults.standard.array(forKey: "recentEmojis") as? [String] {
                recentEmojis = saved
            }
            if recentEmojis.isEmpty {
                selectedCategory = .smileys
            } else {
                selectedCategory = .recent
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(searchPlaceholder, text: $searchText)
                .font(.system(size: 16))

            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var searchPlaceholder: String {
        translationService?
            .resolve(key: ChatTranslationKeys.STORIES_SEARCH, module: ChatTranslationKeys.MODULE)
            .value ?? "Search"
    }

    private var emojiScroll: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if searchText.isEmpty {
                        ForEach(filteredCategories, id: \.self) { category in
                            categorySection(category)
                                .id(category)
                        }
                    } else {
                        searchResultsSection
                    }
                }
                .padding(.vertical, 16)
            }
            .onChange(of: selectedCategory) { _, newCategory in
                withAnimation {
                    proxy.scrollTo(newCategory, anchor: .top)
                }
            }
        }
    }

    private func categorySection(_ category: EmojiCategory) -> some View {
        let emojis = category == .recent ? recentEmojis : category.emojis
        return VStack(alignment: .leading, spacing: 12) {
            Text(category.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                spacing: 12
            ) {
                ForEach(emojis, id: \.self) { emoji in
                    emojiButton(emoji)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private var searchResultsSection: some View {
        let all = Array(Set(EmojiCategory.allCases.flatMap(\.emojis))).sorted()
        let filtered = searchText.isEmpty
            ? all
            : all.filter { emojiMatchesSearch($0, query: searchText) }

        return VStack(alignment: .leading, spacing: 12) {
            Text("Results")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8),
                spacing: 12
            ) {
                ForEach(filtered, id: \.self) { emoji in
                    emojiButton(emoji)
                }
            }
            .padding(.horizontal, 12)
        }
    }

    private func emojiButton(_ emoji: String) -> some View {
        Button {
            Haptic.impact(.medium)
            rememberRecent(emoji)
            onSelect(emoji)
            dismiss()
        } label: {
            Text(emoji)
                .font(.system(size: 32))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

    private var categoryTabs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(filteredCategories, id: \.self) { category in
                    Button {
                        selectedCategory = category
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: category.icon)
                                .font(.system(size: 16))
                                .foregroundStyle(selectedCategory == category ? AppColors.primary : .secondary)

                            Rectangle()
                                .fill(selectedCategory == category ? AppColors.primary : Color.clear)
                                .frame(height: 2)
                        }
                        .frame(width: 38)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(height: 50)
        .background(Color(.systemBackground))
    }

    private func rememberRecent(_ emoji: String) {
        var updated = recentEmojis
        updated.removeAll { $0 == emoji }
        updated.insert(emoji, at: 0)
        if updated.count > 20 {
            updated = Array(updated.prefix(20))
        }
        recentEmojis = updated
        UserDefaults.standard.set(updated, forKey: "recentEmojis")
    }

    private func emojiMatchesSearch(_ emoji: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return true }
        // Direct paste / exact emoji
        if emoji == query || emoji.contains(query) { return true }
        return false
    }
}
