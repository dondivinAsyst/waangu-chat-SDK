
import Foundation
import Combine
import WaanguCoreKit
import UIKit


// MARK: - ENUMS
public enum DiscussionActionType: Equatable {
    case delete
    case toggleBlock
    case togglePin
    case toggleFavorite
    case toggleArchive(_ archived: Bool)
    case toggleMarkAsRead
    case toggleMute
    case showContactInfo
    case toggleLockChat
    case clearChat
    case exitGroup
    
}


@MainActor
public final class ChannelTabViewModel: ObservableObject {
    
    //    let coordinator: ChatMainTabCoordinator
    
    @Published var navigateToChatRoom = false
    @Published var newChannel: ChannelItem?
    @Published var showChatPartnerPickerView = false
    @Published var channels = [ChannelItem]()
    @Published var discussions = [DiscussionChatItem]()
    /// Vrai dès que la première lecture des conversations a abouti (ou a
    /// échoué pour une autre raison qu'une base pas encore prête). Avant, la
    /// liste vide s'affichait comme « aucune conversation » pendant le
    /// chargement — « Tout 0 » au lancement.
    @Published private(set) var hasLoadedDiscussions = false
    @Published var archivedDiscussions = [DiscussionChatItem]()
    @Published var pendingGroups = [GroupChat]()
    @Published var typingUsers = [TypingUser]()
    @Published var retryingGroups = Set<String>()  // ✅ Track groups currently being retried
    @Published var deletionDialog: DeletionDialogContext?
    @Published var postLeaveCleanupDialog: PostLeaveLocalCleanupContext?
    @Published var deletionErrorMessage: String?
    @Published private(set) var isActionLoading = false
    @Published private(set) var actionLoadingMessage: String?
    @Published private(set) var leftGroupDiscussionIds: Set<String> = []
    /// Groups this device's user actually created, as the stored roster says.
    ///
    /// The list only ever claims "You created the group" for one of these. Kept as
    /// a set rather than asked of the row because a `DiscussionChatItem` carries no
    /// creator — assuming one made every member read as the creator of every group.
    @Published private(set) var createdByCurrentUserGroupIds: Set<String> = []
    @Published var selectedDiscussionFilter: DiscussionFilter = .all
    @Published private(set) var customDiscussionLists: [DiscussionCustomList] = []
    @Published var showAddDiscussionListAlert = false
    @Published var newDiscussionListName = ""
    @Published var discussionListToastMessage: String?
    @Published var customListPendingDeletion: DiscussionCustomList?
    
    // ✅ FIX: Cache the visible discussions to prevent re-computation on every view render
    @Published private(set) var visibleDiscussions: [DiscussionChatItem] = []
    /// Bumped whenever the active translation locale changes.
    /// Views that observe this VM will re-render and re-call translator.resolve(…).
    @Published private(set) var translationLocaleToken: Int = 0
    private let logger: any AppLoggerProtocol
    private var cancellables = Set<AnyCancellable>()
    private var listToastDismissTask: Task<Void, Never>?
    
    typealias ChannelId = String
    @Published var channelDict: [ChannelId: ChannelItem] = [:]
    
    private let currentUser: UserItem
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let groupUseCases: GroupUseCasesProtocol
    private let fileUploadUseCases: FileUplaodUseCasesProtocol?
    private var isObservingTyping = false
    let translationService: (any TranslationServiceProtocol)?

    init(_
         currentUser: UserItem = .placeholder,
         discussionsUseCases:DiscussionUseCasesProtocol,
         groupUseCases: GroupUseCasesProtocol,
         typingUsers : [TypingUser] = [],
         translationService: (any TranslationServiceProtocol)? = nil,
         fileUploadUseCases: FileUplaodUseCasesProtocol? = nil,
         logger: any AppLoggerProtocol = AppLogger.shared
    ) {
        self.logger = logger
        self.currentUser = currentUser
        self.discussionUseCases = discussionsUseCases
        self.groupUseCases = groupUseCases
        self.typingUsers = typingUsers
        self.translationService = translationService
        self.fileUploadUseCases = fileUploadUseCases
        self.customDiscussionLists = DiscussionCustomListStore.load()
        
        // Re-render translated strings whenever the locale changes
        NotificationCenter.default.publisher(for: Notification.Name("TranslationKit.localeDidChange"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.translationLocaleToken += 1
            }
            .store(in: &cancellables)
        
        // ✅ FIX: Defer database operations to avoid race condition during initialization
        // Database operations are moved to Task to execute after init completes
        // This prevents "no such table" errors when migrations haven't finished yet
        
        // Enable discussion refresh notifications
        NotificationCenter.default.publisher(for: .discussionsShouldRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateDiscussions()
                }
            }
            .store(in: &cancellables)
        
        // Listen for group activation
        NotificationCenter.default.publisher(for: .groupActivated)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onGroupActivated(notification)
            }
            .store(in: &cancellables)
        
        NotificationCenter.default.publisher(for: .groupDeleted)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.updateDiscussions()
                }
            }
            .store(in: &cancellables)
        
        // Listen for group sync failures
        NotificationCenter.default.publisher(for: .groupSyncFailed)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onGroupSyncFailed(notification)
            }
            .store(in: &cancellables)
        
        // ✅ Listen for sync status changes to update pending groups
        NotificationCenter.default.publisher(for: .groupSyncStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                self?.onGroupSyncStatusChanged(notification)
            }
            .store(in: &cancellables)
        
        // ✅ Perform database operations after initialization completes
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            
            // ✅ Add a small delay to ensure migration has time to complete
            // This prevents "database not ready" warnings on first launch
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms delay
            
            // ✅ NEW: Reset groups stuck in syncing state (from interrupted requests)
            // This fixes the issue where groups appear as "syncing" on app launch with no actual request
            do {
                try await self.groupUseCases.resetStuckSyncingGroups.execute()
            } catch {
                debugLog("⚠️ Failed to reset stuck syncing groups: \(error)")
            }
            
            // Load data in sequence to avoid overwhelming the database during migration
            await self.updateDiscussions()
            self.fetchCurrentUserChannels()
            await self.loadPendingGroups()
            
            // Clean up orphaned group discussions
            self.cleanupOrphanedGroupDiscussions()
        }
        //    }
        //
        //    private func observeTypingEvents() {
        //        EventBus.shared.publisher(for: UserTypingEvent.self)
        //            .receive(on: DispatchQueue.main)
        //            .sink { [weak self] event in
        //                guard let self = self else { return }
        //                switch event.status {
        //                case .typing, .recording:
        //                    let typingUser = TypingUser(
        //                        id: event.senderId,
        //                        msg: event.status == .recording ? "recording" : "typing",
        //                        senderId: event.senderId,
        //                        conversationId: event.conversationId,
        //                        messageType: event.status == .recording ? .AUDIO : .TEXT
        //                    )
        //                    if !self.typingUsers.contains(where: { $0.senderId == event.senderId }) {
        //                        self.typingUsers.append(typingUser)
        //                    }
        //                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
        //                        self?.typingUsers.removeAll { $0.senderId == event.senderId }
        //                    }
        //                case .stopped:
        //                    self.typingUsers.removeAll { $0.senderId == event.senderId }
        //                }
        //            }
        //            .store(in: &cancellables)
        //    }
        
        //    private func observeCallHistory() {
        //        NotificationCenter.default.publisher(for: .callHistoryPersisted)
        //            .receive(on: DispatchQueue.main)
        //            .sink { [weak self] _ in
        //                self?.updateDiscussions()
        //            }
        //            .store(in: &cancellables)
            }
        
        func archiveDiscussion(_ chat: DiscussionChatItem) {
            guard let index = discussions.firstIndex(where: { $0.id == chat.id }) else { return }
            
            var updatedChat = discussions.remove(at: index)
            if updatedChat.setting == nil {
                updatedChat.setting = UserConversationSetting()
            }
            updatedChat.setting?.isArchived = true
            updatedChat.setting?.conversation = updatedChat.conversationId
            updatedChat.setting?.archivedAt = Date()
            
            archivedDiscussions.append(updatedChat)
            // ✅ FIX: Update visible discussions after archiving
            updateVisibleDiscussions()
            Task { @MainActor in
                do {
                    try await discussionUseCases.updateDiscussionSetting.execute(discussion: updatedChat)
                    debugLog("about updating discussion setting : \(updatedChat.setting?.isArchived)")
                } catch {
                    debugLog("something went wrong while updating discussion setting : \(error)")
                }
            }
        }
        
        
        
        func unarchiveDiscussion(_ chat: DiscussionChatItem) {
            guard let index = archivedDiscussions.firstIndex(where: { $0.id == chat.id }) else { return }
            
            var updatedChat = archivedDiscussions.remove(at: index)
            if updatedChat.setting == nil {
                updatedChat.setting = UserConversationSetting()
            }
            updatedChat.setting?.isArchived = false
            updatedChat.setting?.conversation = updatedChat.conversationId
            updatedChat.setting?.archivedAt = nil
            
            discussions.append(updatedChat)
            // ✅ FIX: Update visible discussions after unarchiving
            updateVisibleDiscussions()
            Task { @MainActor in
                do {
                    try await discussionUseCases.updateDiscussionSetting.execute(discussion: updatedChat)
                } catch {
                    debugLog("something went wrong while updating discussion setting : \(error)")
                }
            }
        }
        
        
        //    func updateDiscussions(_ newDiscussions: [DiscussionChatItem]) {
        //
        //        let (archived, active) = newDiscussions.reduce(into: ([DiscussionChatItem](), [DiscussionChatItem]())) { result, item in
        //            if item.setting?.isArchived == true {
        //                result.0.append(item)
        //            } else {
        //                result.1.append(item)
        //            }
        //        }
        //
        //        self.archivedDiscussions = archived
        //        self.discussions = active
        //    }
        func updateDiscussions() async {
            do {
                // Broadcast channels are conversations, but they are not chats:
                // they are read in the Updates tab, and the fetch is shared with
                // it, so they are dropped here rather than at the source.
                let newDiscussions = (try await self.discussionUseCases.getDiscussions.execute() ?? [])
                    .filter { $0.contact?.isChannel != true }
                debugLog("discussions updated — count \(newDiscussions.count)", category: "chat-list")
                let (archived, active) = newDiscussions.reduce(into: ([DiscussionChatItem](), [DiscussionChatItem]())) { result, item in
                    if item.setting?.isArchived == true {
                        result.0.append(item)
                    } else {
                        result.1.append(item)
                    }
                }
                
                // ✅ FIX: Only update arrays if the content has actually changed
                // This preserves SwiftUI's internal array identity and prevents unnecessary jumps
                let newArchivedSorted = archived.sorted(by: { (lhs: DiscussionChatItem, rhs: DiscussionChatItem) -> Bool in
                    let lDate = lhs.lastMessage.createdAt
                    let rDate = rhs.lastMessage.createdAt
                    return lDate > rDate
                })
                let newActiveSorted = active.sorted(by: { (lhs: DiscussionChatItem, rhs: DiscussionChatItem) -> Bool in
                    let lDate = lhs.lastMessage.createdAt
                    let rDate = rhs.lastMessage.createdAt
                    return lDate > rDate
                })
                
                // Only update if arrays are actually different (content-wise, not just order)
                if !arraysHaveSameContent(self.archivedDiscussions, newArchivedSorted) {
                    self.archivedDiscussions = newArchivedSorted
                }
                if !arraysHaveSameContent(self.discussions, newActiveSorted) {
                    self.discussions = newActiveSorted
                }
                
                // ✅ FIX: Update visible discussions after discussions change
                updateVisibleDiscussions()
                hasLoadedDiscussions = true
                await refreshGroupMembershipState(from: newDiscussions)
            } catch {
                let errorDescription = "\(error)"
                // Only log if it's not a "table doesn't exist" error during initialization
                if !errorDescription.contains("no such table") {
                    // Une vraie erreur termine le chargement : sinon l'indicateur
                    // tournerait indéfiniment.
                    hasLoadedDiscussions = true
                    debugLog("❌ discussion was updated failed: \(error)")
                } else {
                    debugLog("⚠️ Database not ready yet for discussions, will retry later")
                }
            }
        }
        
        private func refreshGroupMembershipState(from discussions: [DiscussionChatItem]) async {
            var leftIds = Set<String>()
            var createdIds = Set<String>()
            for discussion in discussions where discussion.contact?.isGroup == true {
                let groupId = discussion.conversationId
                guard let group = try? await groupUseCases.getGroup.execute(groupId: groupId) else {
                    continue
                }
                let member = group.members.first { matchesCurrentUser($0.userId) }
                if member?.isActive != true {
                    leftIds.insert(groupId)
                }
                if matchesCurrentUser(group.createdBy) {
                    createdIds.insert(groupId)
                }
            }
            leftGroupDiscussionIds = leftIds
            createdByCurrentUserGroupIds = createdIds
        }

        /// Everyone to ring when calling a group from the inbox.
        ///
        /// A group carries no phone number of its own, so it cannot be dialled the
        /// way a contact is — the offer has to name the members. Same roster rule
        /// as the group info screen: active members, never this device.
        func groupCallInvitees(conversationId: String) async -> [CallInvitee] {
            guard let group = try? await groupUseCases.getGroup.execute(groupId: conversationId) else {
                return []
            }
            let selfPhone = CurrentSessionInfo.shared.userPhoneNumber
            return group.members
                .filter { $0.isActive && !matchesCurrentUser($0.userId) && $0.phone != selfPhone }
                .prefix(VoipManager.maxParticipants)
                .map { CallInvitee(userId: $0.userId, name: $0.name, phone: $0.phone) }
        }

        func updateTypingUsers(_ new: [TypingUser]) {
            self.typingUsers = new
        }

        // MARK: - Discussion filters

        var discussionFilterItems: [DiscussionFilterItem] {
            DiscussionFilterCoordinator.filterItems(
                discussions: discussions,
                customLists: customDiscussionLists
            )
        }

        func filteredDiscussions(from source: [DiscussionChatItem]) -> [DiscussionChatItem] {
            DiscussionFilterCoordinator.apply(
                selectedDiscussionFilter,
                to: source,
                customLists: customDiscussionLists
            )
        }

        // ✅ FIX: Remove computed property and replace with cached value
        // The visibleDiscussions array is now updated only when data actually changes
        private func updateVisibleDiscussions() {
            visibleDiscussions = filteredDiscussions(from: discussions)
        }
        
        // ✅ FIX: Helper function to check if arrays have the same content
        // This prevents unnecessary array replacements that cause SwiftUI list jumping
        private func arraysHaveSameContent(_ lhs: [DiscussionChatItem], _ rhs: [DiscussionChatItem]) -> Bool {
            guard lhs.count == rhs.count else { return false }

            let rhsById = Dictionary(uniqueKeysWithValues: rhs.map { ($0.id, $0) })
            for lhsItem in lhs {
                guard let rhsItem = rhsById[lhsItem.id] else { return false }
                if lhsItem.lastMessage.codeMessage != rhsItem.lastMessage.codeMessage ||
                   lhsItem.lastMessage.createdAt != rhsItem.lastMessage.createdAt ||
                   lhsItem.lastMessage.status != rhsItem.lastMessage.status ||
                   lhsItem.lastMessage.isEdited != rhsItem.lastMessage.isEdited ||
                   lhsItem.lastMessage.message.text != rhsItem.lastMessage.message.text ||
                   lhsItem.count != rhsItem.count ||
                   // The row renders the contact's name and avatar, so a change to
                   // either has to count as a change. A freshly created group is
                   // named after its conversation row is first read, and comparing
                   // only the message left the list showing the unnamed row until
                   // something unrelated happened to the thread.
                   lhsItem.contact?.userName != rhsItem.contact?.userName ||
                   lhsItem.contact?.image != rhsItem.contact?.image ||
                   // A draft stands in for the last message in the row, so a draft
                   // that appeared, changed, or was sent is a visible change even
                   // when the message underneath it is untouched.
                   lhsItem.draft != rhsItem.draft ||
                   lhsItem.contact?.isGroup != rhsItem.contact?.isGroup {
                    return false
                }
            }
            return true
        }

        func selectDiscussionFilter(_ filter: DiscussionFilter) {
            if filter == .all {
                selectedDiscussionFilter = .all
            } else if selectedDiscussionFilter == filter {
                selectedDiscussionFilter = .all
            } else {
                selectedDiscussionFilter = filter
            }
            // ✅ FIX: Update visible discussions when filter changes
            updateVisibleDiscussions()
        }

        func reloadCustomDiscussionLists() {
            customDiscussionLists = DiscussionCustomListStore.load()
            // ✅ FIX: Update visible discussions when custom lists change
            updateVisibleDiscussions()
        }

        func createCustomDiscussionList() {
            let name = newDiscussionListName
            newDiscussionListName = ""
            guard let list = DiscussionCustomListStore.addList(named: name) else { return }
            reloadCustomDiscussionLists()
            selectedDiscussionFilter = .customList(id: list.id, name: list.name)
            // ✅ FIX: Update visible discussions when creating new list and selecting it
            updateVisibleDiscussions()
        }

        func requestDeleteCustomList(listId: String, listName: String) {
            customListPendingDeletion = DiscussionCustomList(id: listId, name: listName)
        }

        func confirmDeleteCustomList() {
            guard let list = customListPendingDeletion else { return }
            guard DiscussionCustomListStore.deleteList(listId: list.id) != nil else {
                customListPendingDeletion = nil
                return
            }
            if case .customList(let id, _) = selectedDiscussionFilter, id == list.id {
                selectedDiscussionFilter = .all
            }
            reloadCustomDiscussionLists()
            showDiscussionListToast(
                t(ChatTranslationKeys.CHAT_LIST_DELETED_LIST, args: [list.name])
            )
            customListPendingDeletion = nil
            // ✅ FIX: Update visible discussions after deleting custom list
            updateVisibleDiscussions()
        }

        func cancelDeleteCustomList() {
            customListPendingDeletion = nil
        }

        func isDiscussionInList(_ conversationId: String, listId: String) -> Bool {
            DiscussionCustomListStore.isConversation(conversationId, inListId: listId)
        }

        func toggleDiscussionInList(_ conversationId: String, listId: String, listName: String) {
            if DiscussionCustomListStore.isConversation(conversationId, inListId: listId) {
                guard DiscussionCustomListStore.removeConversation(conversationId, fromListId: listId) else { return }
                reloadCustomDiscussionLists()
                showDiscussionListToast(
                    t(ChatTranslationKeys.CHAT_LIST_REMOVED_FROM_LIST, args: [listName])
                )
            } else {
                guard DiscussionCustomListStore.addConversation(conversationId, toListId: listId) else { return }
                reloadCustomDiscussionLists()
                showDiscussionListToast(
                    t(ChatTranslationKeys.CHAT_LIST_ADDED_TO_LIST, args: [listName])
                )
            }
            // ✅ FIX: Update visible discussions when toggling discussion in lists
            updateVisibleDiscussions()
        }

        func showDiscussionListToast(_ message: String) {
            listToastDismissTask?.cancel()
            discussionListToastMessage = message
            listToastDismissTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                self?.discussionListToastMessage = nil
            }
        }

        func toggleFavorite(_ chat: DiscussionChatItem) {
            Task { @MainActor in
                var updated = chat
                if updated.setting == nil {
                    updated.setting = UserConversationSetting()
                }
                let isFavorite = updated.setting?.isMyFavority == true
                updated.setting?.isMyFavority = !isFavorite
                updated.setting?.favorityAt = isFavorite ? nil : Date()
                updated.setting?.conversation = updated.conversationId

                if let index = discussions.firstIndex(where: { $0.id == chat.id }) {
                    discussions[index] = updated
                }
                // ✅ FIX: Update visible discussions after toggling favorite
                updateVisibleDiscussions()

                do {
                    try await discussionUseCases.updateDiscussionSetting.execute(discussion: updated)
                } catch {
                    debugLog("Failed to update favorite: \(error)")
                }
            }
        }
        
        func isTyping(for item: DiscussionChatItem) -> Bool {
            !item.lastMessage.isSentByMe &&
            typingUsers.contains(where: { $0.senderId == item.contact?.id })
        }
        
        
        func getTypingUser(for senderId: String) -> TypingUser? {
            typingUsers.first(where: { $0.senderId == senderId })
        }

        func getTypingUser(forDiscussion discussion: DiscussionChatItem) -> TypingUser? {
            typingUsers.first { $0.conversationId == discussion.conversationId }
        }

        /// Mirrors the session-wide typing feed into `typingUsers`.
        ///
        /// It holds no subscription of its own and runs no expiry: the previous
        /// version slept 4s inside the `for await` loop, which stalled the very
        /// stream it was consuming and then removed the entry unconditionally,
        /// wiping a refresh that had landed during the sleep. `TypingStore`
        /// expires entries on its own clock, for the room and the list alike.
        func startInboxTypingObservation() {
            guard !isObservingTyping else { return }
            isObservingTyping = true

            TypingStore.shared.$byConversation
                .map { byConversation in
                    // Sorted so an unordered dictionary does not look like a
                    // change to `removeDuplicates` on every publish.
                    byConversation.keys.sorted().flatMap { byConversation[$0] ?? [] }
                }
                .removeDuplicates()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] users in
                    self?.typingUsers = users
                }
                .store(in: &cancellables)
        }
        
        func onNewChannelCreation(_ channel: ChannelItem) {
            showChatPartnerPickerView = false
            newChannel = channel
            navigateToChatRoom = true
        }
        
        func createGroupDiscussion(groupName: String, members: [UserContactProps], image: UIImage?, settings: GroupSettings = GroupSettings()) {
            Task { @MainActor in
                do {
                    var avatarUrl: String? = nil
                    if let image = image, let fileUploadUseCases = fileUploadUseCases {
                        // Resized and compressed like every other avatar: the
                        // cropper hands back the picked photo at full
                        // resolution, and a raw PNG of that is tens of MB.
                        let imageData = ChatImageSendEncoder.encodeAvatar(image)
                        let request = FileUploadRequest(
                            fileName: "group_avatar_\(UUID().lowercasedString).jpg",
                            fileType: "image",
                            fileSize: imageData.count,
                            folder: .profilePicture
                        )
                        let result = await fileUploadUseCases.uploadFileUseCase.execute(
                            for: request,
                            fileData: imageData
                        )
                        switch result {
                        case .success(let url):
                            avatarUrl = url
                            debugLog("✅ Group avatar uploaded")
                        case .failure(let error):
                            debugLog("❌ Group avatar upload failed: \(error)")
                        }
                    }

                    let input = CreateGroupWithDiscussionInput(
                        groupName: groupName,
                        invitedMembers: members,
                        avatarUrl: avatarUrl,
                        settings: settings
                    )
                    let result = try await groupUseCases.createGroup.execute(input)

                    // ✅ Immediately show in pending list with loading state
                    pendingGroups.append(result.group)
                    
                    await updateDiscussions()
                    onNewChannelCreation(GroupChannelItemMapper.makeChannel(from: result))
                } catch {
                    debugLog("❌ Failed to create group: \(error)")
                }
            }
        }
        
        func loadPendingGroups() async {
            do {
                let pending = try await groupUseCases.getPendingGroups.execute()
                self.pendingGroups = pending
            } catch {
                let errorDescription = "\(error)"
                // Only log if it's not a "table doesn't exist" error during initialization
                if !errorDescription.contains("no such table") {
                    debugLog("❌ Failed to load pending groups: \(error)")
                } else {
                    debugLog("⚠️ Database not ready yet for pending groups, will retry later")
                }
            }
        }
        
        private func onGroupActivated(_ notification: Notification) {
            guard let localId = notification.userInfo?["localId"] as? String,
                  let serverId = notification.userInfo?["serverId"] as? String else {
                return
            }
            
            // Remove from pending groups
            pendingGroups.removeAll { $0.localId == localId }
            
            // ✅ NEW APPROACH: No need to delete/recreate discussion
            // The conversationId stays as localId permanently
            // Just refresh the discussions list to show updated sync status
            
            debugLog("✅ Group activated: localId=\(localId), serverId=\(serverId)")
            debugLog("✅ Discussion conversationId remains: \(localId)")
            
            Task { @MainActor [weak self] in
                await self?.updateDiscussions()
            }
        }
        
        private func onGroupSyncFailed(_ notification: Notification) {
            debugLog("group sync failed notification received", category: "chat-list")
            guard let localId = notification.userInfo?["localId"] as? String,
                  let error = notification.userInfo?["error"] as? String else {
                return
            }
            
            // ✅ Add to pending groups only when sync fails
            Task { @MainActor in
                do {
                    if let failedGroup = try await groupUseCases.getGroup.execute(groupId: localId) {
                        if !pendingGroups.contains(where: { $0.localId == localId }) {
                            pendingGroups.append(failedGroup)
                        }
                    }
                } catch {
                    debugLog("❌ Failed to load failed group: \(error)")
                }
            }
            
            // ✅ Removed redundant loadPendingGroups() call
            // The Task above already updates the pending list
            
            debugLog("❌ Group sync failed for \(localId): \(error)")
        }
        
        /// Updates the sync status of a pending group in real-time
        private func onGroupSyncStatusChanged(_ notification: Notification) {
            debugLog("this was called while waiting for the group to sync")
            guard let localId = notification.userInfo?["localId"] as? String else {
                return
            }
            
            Task { @MainActor in
                do {
                    if let updatedGroup = try await groupUseCases.getGroup.execute(groupId: localId),
                       let index = pendingGroups.firstIndex(where: { $0.localId == localId }) {
                        pendingGroups[index] = updatedGroup
                    }
                } catch {
                    debugLog("❌ Failed to update group status: \(error)")
                }
                
                await updateDiscussions()
            }
        }
        
        func retryGroupCreation(_ group: GroupChat) async {
            // ✅ Prevent duplicate retry attempts
            guard !retryingGroups.contains(group.localId) else {
                debugLog("⚠️ Group \(group.localId) is already being retried")
                return
            }
            
            retryingGroups.insert(group.localId)
            defer { retryingGroups.remove(group.localId) }
            
            debugLog("🔄 Retrying group creation for: \(group.name)")
            
            do {
                // Retry only the specific group that was clicked
                try await groupUseCases.retrySingleGroup.execute(group)
            
                await loadPendingGroups()
            } catch {
                debugLog("❌ Failed to retry group creation: \(error)")
                
                // ✅ FIX: When retry fails, reset the group status back to failed
                // This ensures the UI shows the retry button again instead of staying stuck in "syncing" state
                await loadPendingGroups()
                if !pendingGroups.contains(where: { $0.localId == group.localId }) {
                    pendingGroups.append(group)
                }
            }
        }
        
        func fetchCurrentUserChannels() {
            
        }
        
        func getChannel(with channelId: String) {
            
            
        }
        
        //    func onPressDiscussionChatItem(_ item: DiscussionChatItem) {
        //
        //        coordinator.onPressItem([
        //            "id": item.id,
        //            "senderId" : item.contact?.id ?? "",
        //            "title" : item.contact?.userName ?? "",
        //            "subtitle": "",
        //            "unreadCount": item.count,
        //            "image": item.contact?.image ?? "",
        //            "messageType": item.lastMessage.typeMessage,
        //            "isMe": item.lastMessage.isSentByMe,
        //            "messageStatus": item.lastMessage.status
        //        ])
        //    }
        
        func onPressAction(action:DiscussionActionType, chat: DiscussionChatItem)  {
            
            let discussionId = chat.id
            
            switch action {
            case .delete:
                beginDeletion(for: chat, intent: .deleteFromList)
                
                
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "delete"])
            case .toggleBlock:
                debugLog("discussion actions  \(action)")
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "toggleBlock"])
            case .togglePin:
                debugLog("discussion actions  \(action)")
            case .toggleFavorite:
                toggleFavorite(chat)
            case .toggleArchive(let isArchived):
                if isArchived {
                    self.archiveDiscussion(chat)
                }else{
                    self.unarchiveDiscussion(chat)
                }
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "toggleArchive"])
            case .toggleMarkAsRead:
                debugLog("discussion actions  \(action)")
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "toggleMarkAsRead"])
            case .toggleMute:
                debugLog("discussion actions  \(action)")
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "toggleMute"])
            case .showContactInfo:
                debugLog("discussion actions info \(action)")
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "showContactInfo"])
            case .toggleLockChat:
                debugLog("discussion actions  \(action)")
                //            coordinator.onPressAction(dic: ["id" : discussionId, "action" : "toggleLockChat"])
            case .clearChat:
                if chat.contact?.isGroup == true, hasLeftGroupDiscussion(chat) {
                    beginDeletion(for: chat, intent: .deleteFromList)
                } else {
                    Task { @MainActor in
                        await clearDiscussionMessages(
                            discussionId: discussionId,
                            isGroup: chat.contact?.isGroup == true
                        )
                    }
                }
            case .exitGroup:
                beginDeletion(for: chat, intent: .exitGroup)
            }
            
        }
        
        // MARK: - Group membership (discussion list)
        
        func hasLeftGroupDiscussion(_ discussion: DiscussionChatItem) -> Bool {
            guard discussion.contact?.isGroup == true else { return false }
            return leftGroupDiscussionIds.contains(discussion.conversationId)
        }
        
        func hasLeftGroupDiscussion(id: String) -> Bool {
            leftGroupDiscussionIds.contains(id)
        }

        func isGroupCreatedByCurrentUser(_ discussion: DiscussionChatItem) -> Bool {
            guard discussion.contact?.isGroup == true else { return false }
            return createdByCurrentUserGroupIds.contains(discussion.conversationId)
        }
        
        // MARK: - Deletion Validation
        
        func beginDeletion(for chat: DiscussionChatItem, intent: DeletionDialogIntent) {
            Task { @MainActor in
                do {
                    let eligibility = try await freshDeletionEligibility(discussionId: chat.id)
                    deletionDialog = DeletionDialogContext(
                        discussionId: chat.id,
                        eligibility: eligibility,
                        intent: intent
                    )
                } catch {
                    deletionErrorMessage = String(format: ChatErrorStrings.deletionEligibilityFailed, error.localizedDescription)
                }
            }
        }
        
        private func freshDeletionEligibility(discussionId: String) async throws -> DeletionEligibility {
            _ = try? await groupUseCases.getGroup.execute(groupId: discussionId)
            return try await groupUseCases.getDiscussionDeletionEligibility.execute(
                discussionId: discussionId,
                currentUserId: currentUserId
            )
        }
        
        private func withActionLoading<T>(
            message: String,
            _ operation: () async throws -> T
        ) async rethrows -> T {
            isActionLoading = true
            actionLoadingMessage = message
            defer {
                isActionLoading = false
                actionLoadingMessage = nil
            }
            return try await operation()
        }
        
        private func clearDiscussionMessages(discussionId: String, isGroup: Bool) async {
            do {
                try await withActionLoading(message: "Clearing messages...") {
                    if isGroup {
                        GroupIntroDismissalStore.markDismissed(conversationId: discussionId)
                    }
                    try await discussionUseCases.deleteAllDiscussionMessages.execute(converationId: discussionId)
                    await updateDiscussions()
                }
            } catch {
                deletionErrorMessage = String(format: ChatErrorStrings.clearMessagesFailed, error.localizedDescription)
            }
        }
        
        func confirmDeletionPrimaryAction() {
            guard let context = deletionDialog else { return }
            let discussionId = context.discussionId
            
            Task { @MainActor in
                do {
                    try await withActionLoading(message: "Deleting...") {
                        switch context.intent {
                        case .exitGroup:
                            break
                        case .deleteFromList, .deleteFromGroupInfo:
                            try await performValidatedDelete(
                                discussionId: discussionId,
                                eligibility: context.eligibility
                            )
                            deletionDialog = nil
                            await updateDiscussions()
                        }
                    }
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        func confirmDeleteLocalContent() {
            guard let context = deletionDialog else { return }
            let discussionId = context.discussionId
            
            Task { @MainActor in
                do {
                    let eligibility = try await freshDeletionEligibility(discussionId: discussionId)
                    if eligibility.metadata.isMember {
                        await clearDiscussionMessages(
                            discussionId: discussionId,
                            isGroup: eligibility.metadata.isGroup
                        )
                        deletionDialog = nil
                    } else {
                        try await withActionLoading(message: "Deleting...") {
                            try await groupUseCases.deleteLocalGroupCopy.execute(groupId: discussionId)
                            deletionDialog = nil
                            await updateDiscussions()
                        }
                    }
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        func confirmLeaveGroupFromDialog() {
            guard let context = deletionDialog else { return }
            let discussionId = context.discussionId
            
            Task { @MainActor in
                var groupName = context.eligibility.metadata.groupName
                if groupName == nil {
                    groupName = try? await groupUseCases.getGroup.execute(groupId: discussionId)?.name
                }
                let resolvedGroupName = groupName ?? "this group"
                do {
                    try await withActionLoading(message: "Leaving group...") {
                        try await performServerLeave(discussionId: discussionId)
                        deletionDialog = nil
                        await updateDiscussions()
                    }
                    postLeaveCleanupDialog = PostLeaveLocalCleanupContext(
                        discussionId: discussionId,
                        groupName: resolvedGroupName
                    )
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        func confirmPostLeaveKeepLocally() {
            postLeaveCleanupDialog = nil
            Task { @MainActor in
                await updateDiscussions()
            }
        }
        
        func confirmPostLeaveDeleteLocally() {
            guard let context = postLeaveCleanupDialog else { return }
            
            Task { @MainActor in
                do {
                    try await withActionLoading(message: "Deleting...") {
                        try await groupUseCases.deleteLocalGroupCopy.execute(groupId: context.discussionId)
                        postLeaveCleanupDialog = nil
                        await updateDiscussions()
                    }
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        func confirmExitAndKeepLocally() {
            guard let context = deletionDialog else { return }
            
            Task { @MainActor in
                do {
                    try await withActionLoading(message: "Leaving group...") {
                        try await performServerLeave(discussionId: context.discussionId)
                        deletionDialog = nil
                        await updateDiscussions()
                    }
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        func confirmExitAndDeleteLocally() {
            guard let context = deletionDialog else { return }
            
            Task { @MainActor in
                do {
                    try await withActionLoading(message: "Leaving group...") {
                        try await performServerLeave(discussionId: context.discussionId)
                        try await groupUseCases.deleteLocalGroupCopy.execute(groupId: context.discussionId)
                        deletionDialog = nil
                        await updateDiscussions()
                    }
                } catch {
                    deletionErrorMessage = error.localizedDescription
                }
            }
        }
        
        private var currentUserId: String {
            let sessionUid = CurrentSessionInfo.shared.currentUid
            if !sessionUid.isEmpty {
                return sessionUid
            }
            return currentUser.uid
        }
        
        private func matchesCurrentUser(_ memberUserId: String) -> Bool {
            // An unknown id is nobody, least of all this device: the session id is
            // itself empty until `AppSettings` is injected, and `"" == ""` would
            // otherwise make every anonymous roster entry read as the current user.
            guard !memberUserId.isEmpty else { return false }
            if memberUserId == currentUserId {
                return true
            }
            let sessionUid = CurrentSessionInfo.shared.currentUid
            if !sessionUid.isEmpty, memberUserId == sessionUid {
                return true
            }
            if !currentUser.uid.isEmpty, memberUserId == currentUser.uid {
                return true
            }
            return false
        }
        
        private func performValidatedDelete(
            discussionId: String,
            eligibility: DeletionEligibility
        ) async throws {
            switch eligibility.suggestedAction {
            case .deleteNow, .deleteLocalContent:
                let result = try await groupUseCases.validateAndDeleteDiscussion.execute(
                    discussionId: discussionId,
                    currentUserId: currentUserId
                )
                switch result {
                case .success:
                    return
                case .blocked(let reason):
                    throw NSError(domain: "Deletion", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
                case .requiresLeave(let groupId):
                    throw NSError(
                        domain: "Deletion",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Leave group \(groupId) before deleting."]
                    )
                case .requiresLeaveAndDelete:
                    try await performServerLeave(discussionId: discussionId)
                    return
                case .error(let message):
                    throw NSError(domain: "Deletion", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
                }
            case .leaveAndDelete:
                try await performServerLeave(discussionId: discussionId)
                return
            case .leaveGroupFirst, .cannotDelete:
                throw NSError(
                    domain: "Deletion",
                    code: 4,
                    userInfo: [NSLocalizedDescriptionKey: eligibility.userMessage]
                )
            }
        }
        
        private func performServerLeave(discussionId: String) async throws {
            _ = try await groupUseCases.leaveGroup.execute(
                groupId: discussionId,
                userId: currentUserId
            )
        }
        
        func getChannelMembers(_ channel: ChannelItem, completion: @escaping (_ members: [UserItem]) -> Void) {
            
        }
        
        func reloadData() {
            self.channels = Array(channelDict.values)
            self.channels.sort { $0.lastMessageTimestamp > $1.lastMessageTimestamp }
        }
        
        // MARK: - Cleanup Functions
        
        /// Removes orphaned group discussions that don't have a corresponding CDGroup entry
        /// This cleans up test data and failed group creations
        private func cleanupOrphanedGroupDiscussions() {
            Task { @MainActor in
                do {
                    let discussions = try await discussionUseCases.getDiscussions.execute() ?? []

                    // `isGroup` alone does not mean "is a group": a channel sets
                    // it too (see `ContactChannel.isChannel`'s doc), and a
                    // channel's conversation id was never going to be found in
                    // `groupUseCases.getGroup` — that registry is `/groups`,
                    // which a broadcast channel was never part of. Without this
                    // exclusion every followed channel looked "orphaned" and was
                    // deleted the moment this ran.
                    for discussion in discussions
                    where discussion.contact?.isGroup == true && discussion.contact?.isChannel != true {
                        let groupId = discussion.conversationId
                        
                        // Check if group exists in local store
                        let groupExists = (try? await groupUseCases.getGroup.execute(groupId: groupId)) != nil
                        
                        if !groupExists {
                            debugLog("🧹 Cleaning up orphaned group discussion: \(discussion.contact?.userName ?? "Unknown") (\(groupId))")
                            try? await discussionUseCases.deleteDiscussion.execute(converationId: groupId)
                        }
                    }
                    
                    await updateDiscussions()
                } catch {
                    let errorDescription = "\(error)"
                    // Only log if it's not a "table doesn't exist" error during initialization
                    if !errorDescription.contains("no such table") {
                        debugLog("❌ Failed to cleanup orphaned discussions: \(error)")
                    } else {
                        debugLog("⚠️ Database not ready yet for cleanup, will retry later")
                    }
                }
            }
        }

        private func t(_ key: String, args: [String] = []) -> String {
            translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
        }
    }

