//
//  ForwardMessagePickerViewModel.swift
//  FeatureChat
//
//  Created by Kiro on 2/12/26.
//

import Foundation
import WaanguCoreKit

@MainActor
final class ForwardMessagePickerViewModel: ObservableObject {

    // MARK: - Published state

    @Published var searchText = ""
    /// The "add a message" field. Sent as its own text message after the
    /// forwarded ones, and used as the caption when posting to status.
    @Published var caption = ""

    @Published private(set) var recentChats: [ForwardTarget] = []
    @Published private(set) var contacts: [ForwardTarget] = []
    /// Nil when the selection holds something a status cannot carry.
    @Published private(set) var statusTarget: ForwardTarget?
    /// Ordered, so the names label and the send order match what was tapped.
    @Published private(set) var selection: [ForwardTarget] = []
    @Published private(set) var isLoading = true
    @Published private(set) var isSending = false
    @Published private(set) var errorMessage: String?

    /// conversationId → truncated member names, filled in after the rows are
    /// already on screen.
    @Published private(set) var groupMemberInfo: [String: String] = [:]

    /// contactId → the conversation id a first message to them would open.
    /// Kept for the life of the sheet so a refresh rebuilds the same targets
    /// and an already-ticked row stays ticked.
    private var mintedConversationIds: [String: String] = [:]

    // MARK: - Dependencies

    private let contactsUseCases: ContactsUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let groupUseCases: GroupUseCasesProtocol?
    private let translationService: (any TranslationServiceProtocol)?

    /// Groups whose roster is fetched for the subtitle. Every one is a lookup,
    /// and the subtitle is a nicety — the rest fall back to "Group".
    private static let groupSubtitleLookupLimit = 25

    init(
        contactsUseCases: ContactsUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        groupUseCases: GroupUseCasesProtocol? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.contactsUseCases = contactsUseCases
        self.discussionUseCases = discussionUseCases
        self.groupUseCases = groupUseCases
        self.translationService = translationService
    }

    // MARK: - Derived state

    var filteredRecentChats: [ForwardTarget] {
        recentChats.filter { $0.matches(searchText) }
    }

    var filteredContacts: [ForwardTarget] {
        contacts.filter { $0.matches(searchText) }
    }

    /// The status row is a destination, not a search result — it disappears
    /// while the user is filtering by name.
    var visibleStatusTarget: ForwardTarget? {
        searchText.isEmpty ? statusTarget : nil
    }

    var isEmpty: Bool {
        !isLoading && errorMessage == nil && recentChats.isEmpty && contacts.isEmpty
    }

    var canSend: Bool { !selection.isEmpty && !isSending }

    var selectedNamesLabel: String {
        selection.map(\.name).joined(separator: ", ")
    }

    var trimmedCaption: String? {
        let trimmed = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func isSelected(_ target: ForwardTarget) -> Bool {
        selection.contains { $0.id == target.id }
    }

    /// Prefers the group's member list once it has loaded.
    func subtitle(for target: ForwardTarget) -> String {
        if target.isGroup,
           let conversationId = target.conversationId,
           let members = groupMemberInfo[conversationId],
           !members.isEmpty {
            return members
        }
        return target.fallbackSubtitle
    }

    // MARK: - Selection

    func toggle(_ target: ForwardTarget) {
        guard target.isSelectable else { return }
        if let index = selection.firstIndex(where: { $0.id == target.id }) {
            selection.remove(at: index)
        } else {
            selection.append(target)
        }
    }

    func clearSearch() {
        searchText = ""
    }

    func beginSending() {
        isSending = true
    }

    func endSending() {
        isSending = false
    }

    // MARK: - Loading

    /// Decides whether "My status" is offered for this selection, before the
    /// lists load — the row sits above them and shouldn't pop in late.
    func prepareStatusTarget(for messages: [MessageDataItem]) {
        guard ForwardStatusMapper.canPost(messages) else {
            statusTarget = nil
            return
        }
        statusTarget = ForwardTarget(
            kind: .myStatus,
            name: translate(ChatTranslationKeys.FORWARD_MY_STATUS),
            avatar: CurrentSessionInfo.shared.userProfile,
            fallbackSubtitle: "",
            isBlocked: false,
            receiver: nil
        )
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        await loadTargets()
        isLoading = false
    }

    func refresh() async {
        errorMessage = nil
        await loadTargets()
    }

    private func loadTargets() async {
        let discussions = await loadDiscussions()
        recentChats = discussions.compactMap { discussionTarget(for: $0) }
        contacts = await loadContacts(excluding: discussions)

        // Rows are on screen by now; the group subtitles fill in behind them.
        await loadGroupMemberInfo(for: discussions)
    }

    private func loadDiscussions() async -> [DiscussionChatItem] {
        do {
            guard let discussions = try await discussionUseCases.getDiscussions.execute() else {
                return []
            }
            // Copilot n'est pas un destinataire : rien ne s'y transfère.
            return discussions
                .filter { $0.contact?.isCopilotChat != true }
                .sorted { $0.lastMessage.createdAt > $1.lastMessage.createdAt }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func loadContacts(excluding discussions: [DiscussionChatItem]) async -> [ForwardTarget] {
        do {
            let persisted = try await contactsUseCases.getPersistedContacts.execute()
            guard let waanguContacts = persisted?.waanguContacts else { return [] }

            // A contact that already has a conversation is reachable through the
            // recent list; listing them twice makes the same person two rows
            // with two different ids.
            let knownUserIds = Set(discussions.compactMap { $0.contact?.userId }.filter { !$0.isEmpty })
            let knownPhones = Set(discussions.compactMap { $0.contact?.phone }.filter { !$0.isEmpty })

            return waanguContacts
                .filter { !$0.isBlocked }
                .filter { !knownUserIds.contains($0.userId) && !knownPhones.contains($0.phone) }
                .compactMap { contactTarget(for: $0) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            errorMessage = error.localizedDescription
            return []
        }
    }

    private func loadGroupMemberInfo(for discussions: [DiscussionChatItem]) async {
        guard let groupUseCases else { return }

        let groups = discussions
            .filter { $0.contact?.isGroup == true }
            .prefix(Self.groupSubtitleLookupLimit)

        for discussion in groups {
            guard let group = try? await groupUseCases.getGroup.execute(
                groupId: discussion.conversationId
            ) else { continue }

            let activeMembers = group.members.filter(\.isActive)
            guard !activeMembers.isEmpty else { continue }

            let names = activeMembers.prefix(3).map(\.name).joined(separator: ", ")
            groupMemberInfo[discussion.conversationId] = activeMembers.count <= 3
                ? names
                : translate(
                    ChatTranslationKeys.FORWARD_GROUP_MEMBERS_MORE,
                    args: [names, "\(activeMembers.count - 3)"]
                  )
        }
    }

    // MARK: - Target building

    private func discussionTarget(for discussion: DiscussionChatItem) -> ForwardTarget? {
        guard let contact = discussion.contact else { return nil }
        let isGroup = contact.isGroup

        let receiver = UserRoom(
            // For a group the conversation is the address; for a direct chat it
            // is the contact record the discussion was opened against.
            idContact: isGroup ? discussion.conversationId : contact.id,
            userId: contact.userId,
            phone: contact.phone,
            name: contact.userName,
            avatar: contact.image,
            description: nil,
            isOnline: false,
            onlineStatus: UserOnline(status: .offline, lastSeen: "", userId: contact.userId),
            isBlocked: contact.isBlocked
        )

        return ForwardTarget(
            kind: .discussion(conversationId: discussion.conversationId, isGroup: isGroup),
            name: contact.userName.isEmpty ? contact.phone : contact.userName,
            avatar: contact.image,
            fallbackSubtitle: fallbackSubtitle(for: discussion, isGroup: isGroup),
            isBlocked: contact.isBlocked,
            receiver: receiver
        )
    }

    private func contactTarget(for contact: WaanguContact) -> ForwardTarget? {
        guard !contact.id.isEmpty else { return nil }

        let conversationId = mintedConversationIds[contact.id] ?? {
            let minted = UUID().uuidString.lowercased()
            mintedConversationIds[contact.id] = minted
            return minted
        }()

        let receiver = UserRoom(
            idContact: contact.id,
            userId: contact.userId,
            phone: contact.phone,
            name: contact.name,
            avatar: contact.image,
            description: contact.bio,
            isOnline: contact.onlineStatus.status == .online,
            onlineStatus: contact.onlineStatus,
            isBlocked: contact.isBlocked
        )

        let bio = (contact.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ForwardTarget(
            kind: .contact(contactId: contact.id, conversationId: conversationId),
            name: contact.name.isEmpty ? contact.phone : contact.name,
            avatar: contact.image,
            fallbackSubtitle: bio.isEmpty ? contact.phone : bio,
            isBlocked: contact.isBlocked,
            receiver: receiver
        )
    }

    private func fallbackSubtitle(for discussion: DiscussionChatItem, isGroup: Bool) -> String {
        if isGroup { return translate(ChatTranslationKeys.FORWARD_GROUP) }
        if let phone = discussion.contact?.phone, !phone.isEmpty { return phone }
        let lastText = discussion.lastMessage.message.text
        return lastText.isEmpty ? translate(ChatTranslationKeys.FORWARD_WAANGU_USER) : lastText
    }

    private func translate(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
}
