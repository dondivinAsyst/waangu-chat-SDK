//
//  DiscussionCustomListStore.swift
//  FeatureChat
//

import Foundation

/// Persists user-created discussion lists locally (WhatsApp-style lists).
enum DiscussionCustomListStore {

    private static let storageKey = "featureChat.discussionCustomLists"
    private static let seededKey = "featureChat.discussionCustomListsSeeded"
    private static let defaultListNames = ["Work"]

    static func load() -> [DiscussionCustomList] {
        if UserDefaults.standard.data(forKey: storageKey) == nil {
            markSeeded()
            return seedDefaultLists()
        }
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let lists = try? JSONDecoder().decode([DiscussionCustomList].self, from: data) else {
            markSeeded()
            return seedDefaultLists()
        }
        if lists.isEmpty && !UserDefaults.standard.bool(forKey: seededKey) {
            markSeeded()
            return seedDefaultLists()
        }
        return lists
    }

    private static func markSeeded() {
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    private static func seedDefaultLists() -> [DiscussionCustomList] {
        let lists = defaultListNames.map { DiscussionCustomList(name: $0) }
        save(lists)
        return lists
    }

    static func save(_ lists: [DiscussionCustomList]) {
        guard let data = try? JSONEncoder().encode(lists) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    @discardableResult
    static func addList(named name: String) -> DiscussionCustomList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var lists = load()
        guard !lists.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else {
            return nil
        }
        let list = DiscussionCustomList(name: trimmed)
        lists.append(list)
        save(lists)
        return list
    }

    static func addConversation(_ conversationId: String, toListId listId: String) -> Bool {
        var lists = load()
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return false }
        guard !lists[index].conversationIds.contains(conversationId) else { return false }
        lists[index].conversationIds.append(conversationId)
        save(lists)
        return true
    }

    static func removeConversation(_ conversationId: String, fromListId listId: String) -> Bool {
        var lists = load()
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return false }
        guard lists[index].conversationIds.contains(conversationId) else { return false }
        lists[index].conversationIds.removeAll { $0 == conversationId }
        save(lists)
        return true
    }

    static func isConversation(_ conversationId: String, inListId listId: String) -> Bool {
        load().first(where: { $0.id == listId })?.conversationIds.contains(conversationId) ?? false
    }

    @discardableResult
    static func deleteList(listId: String) -> String? {
        var lists = load()
        guard let index = lists.firstIndex(where: { $0.id == listId }) else { return nil }
        let name = lists[index].name
        lists.remove(at: index)
        save(lists)
        return name
    }
}
