//  RenderNativeView.swift
//  Pods
//
//  Created by Asyst on 6/3/25.
//

import SwiftUI
import SDWebImageSwiftUI
import UIKit
import WaanguSharedUI
import WaanguCoreKit

/// Owns the chat list's scroll position and decides when it's safe to follow
/// the list to a new "top" item after the underlying data changes (e.g. a new
/// message bumps a chat to the top of the inbox).
///
/// The previous implementation did this inline with a plain `@State` var and
/// an `onChange` that compared the *current* scroll position against the
/// *new* top item's id. That comparison is only true by coincidence (when the
/// top item happens not to change), so in practice the scroll position kept
/// following whatever item used to be on top as it slid down the list —
/// which is the "jumping" behavior being chased here.
///
/// The fix: compare against the *old* top item's id instead. If the user was
/// looking at the old top item, follow the list to the new top item. If they
/// were scrolled down reading something else, leave their position alone.
@available(iOS 16.0, *)
@MainActor
private final class ChatListScrollTracker: ObservableObject {
    @Published var scrollPosition: String?

    /// Call this whenever the underlying `visibleDiscussions` array changes.
    /// - Parameters:
    ///   - oldTopID: `id` of the first item *before* the update.
    ///   - newTopID: `id` of the first item *after* the update.
    func handleDataChange(oldTopID: String?, newTopID: String?) {
        let wasPinnedToTop = scrollPosition == nil || scrollPosition == oldTopID
        if wasPinnedToTop {
            scrollPosition = newTopID
        }
        // else: leave scrollPosition as-is. It still points at whatever item
        // the user was reading, and SwiftUI's `scrollPosition(id:)` binding
        // will keep that item in view as long as it's still present in the
        // (possibly reordered) array — which is exactly what we want when the
        // user isn't at the top.
    }
}

@available(iOS 16.0, *)
struct ChatListNativeView:  View {
    
    @ObservedObject var viewModel: ChannelTabViewModel
    @ObservedObject var chatPartnerPickerViewModel: ChatPartnerPickerViewModel
    let navigationCoord: ChatsTabCoordinator
    @ObservedObject var messageSearchViewModel: MessageSearchViewModel
    @State private var showSheetOption: Bool = false
    @State private var searchText = ""
    @State private var isSearchFocused = false
    @FocusState private var isSearchFieldFocused: Bool
    @State private var selectedDiscussion:DiscussionChatItem? = nil
    @State private var isConfirmDelete: Bool = false
    @State private var profileSheetDiscussion: DiscussionChatItem? = nil
    /// Waangu Copilot : le bouton flottant, quand le Hub publie ses outils.
    @State private var copilotAvailable = false
    /// La conversation Copilot dont l'utilisateur a demandé la suppression.
    @State private var copilotPendingDeletion: DiscussionChatItem?

    // Scroll position lives in `ChatListScrollTracker` now (see above) instead
    // of a raw @State var — the bug was in the decision logic, not in needing
    // state at all, so that logic is isolated there and unit-testable on its
    // own instead of being buried in an onChange closure.
    @StateObject private var scrollTracker = ChatListScrollTracker()

    private var baseDiscussions: [DiscussionChatItem] {
        viewModel.visibleDiscussions
    }

    private var filteredDiscussions: [DiscussionChatItem] {
        guard !searchText.isEmpty else { return baseDiscussions }
        let query = searchText.lowercased()
        return baseDiscussions.filter { item in
            (item.contact?.userName ?? "").lowercased().contains(query) ||
            (item.contact?.phone ?? "").contains(query) ||
            (item.lastMessage.message.text ?? "").lowercased().contains(query)
        }
    }

    private var filterEmptyStateTitle: String? {
        guard viewModel.hasLoadedDiscussions,
              viewModel.selectedDiscussionFilter != .all,
              viewModel.visibleDiscussions.isEmpty else { return nil }
        let filterName = resolvedFilterTitle(viewModel.selectedDiscussionFilter)
        return t(ChatTranslationKeys.CHAT_LIST_EMPTY_FILTER, args: [filterName])
    }

    private var searchPlaceholder: String {
        if case .customList(_, let name) = viewModel.selectedDiscussionFilter {
            return t(ChatTranslationKeys.CHAT_LIST_SEARCH_IN_LIST, args: [name])
        }
        return t(ChatTranslationKeys.CHAT_LIST_SEARCH_PLACEHOLDER)
    }

    private func resolvedFilterTitle(_ filter: DiscussionFilter) -> String {
        if let key = filter.translationKey {
            return t(key)
        }
        if case .customList(_, let name) = filter {
            return name
        }
        return filter.title
    }
    
    var body: some View {
        if #available(iOS 16.0, *) {

            ZStack {
                // Normal chat list
                if !isSearchFocused {
                    VStack(spacing: 0) {
                        searchTapTarget
                            .padding(.horizontal, 16)
                            .padding(.top, 4)
                            .padding(.bottom, 4)

                        discussionFilterChips
                            .padding(.bottom, 4)

                        List {
                        // Rien d'affiché tant que la première lecture n'a pas
                        // abouti : une liste vide n'est pas « aucune conversation ».
                        if !viewModel.hasLoadedDiscussions && viewModel.visibleDiscussions.isEmpty {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .padding(.vertical, 24)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        if let emptyTitle = filterEmptyStateTitle {
                            filterEmptyRow(title: emptyTitle)
                        }

                        if viewModel.archivedDiscussions.count > 0 {
                            archivedButton()
                        }
                        
                        if !viewModel.pendingGroups.isEmpty {
                            Section(header: Text(viewModel.translationService?.resolve(key: ChatTranslationKeys.CREATING_GROUPS_HEADER, module: ChatTranslationKeys.MODULE).value ?? "Creating Groups").font(.caption).foregroundColor(.secondary)) {
                                ForEach(viewModel.pendingGroups) { group in
                                    PendingGroupRow(
                                        group: group,
                                        translationService: viewModel.translationService
                                    ) {
                                        Task { @MainActor in
                                            debugLog("PendingGroupRow retry")
                                            await viewModel.retryGroupCreation(group)
                                        }
                                    }
                                }
                            }
                        }

                        ForEach(viewModel.visibleDiscussions, id: \.id) { item in
                            DiscussionChat(
                                discussion: item,
                                hasLeftGroup: viewModel.hasLeftGroupDiscussion(item),
                                isGroupCreatedByCurrentUser: viewModel.isGroupCreatedByCurrentUser(item),
                                typingUser: viewModel.getTypingUser(forDiscussion: item),
                                onShowMoreAction: {
                                    selectedDiscussion = item
                                    showSheetOption = true
                                }, onPressAction: { action in
                                    // Copilot vit sur l'appareil : sa suppression aussi.
                                    if item.contact?.isCopilotChat == true, case .delete = action {
                                        copilotPendingDeletion = item
                                    } else {
                                        viewModel.onPressAction(action: action, chat: item)
                                    }
                                },
                                onProfileTap: { discussion in
                                    guard discussion.contact?.isCopilotChat != true else { return }
                                    profileSheetDiscussion = discussion
                                },
                                navigationCoord: navigationCoord,
                                translator: viewModel.translationService,
                                localeToken: viewModel.translationLocaleToken
                            )
                            .equatable()  // ✅ FIX: Prevent unnecessary re-renders using Equatable protocol
                            .listRowSeparator(.hidden) // row draws its own inset divider now
                            .accessibilityAddTraits(.isButton)
                            .onTapGesture {
                                navigationCoord.push(Self.route(for: item))
                            }
                        }

                        // B61 — pas de mention E2EE tant que les messages partent en clair.
                        if ChatEncryptionClaim.messagesAreEndToEndEncrypted {
                            inboxFooterView()
                                .listRowSeparator(.hidden)
                        }
                        }
                        .listStyle(.plain)
                        .scrollIndicators(.hidden)
                        .scrollPosition(id: $scrollTracker.scrollPosition)
                        .contentMargins(.bottom, 80, for: .scrollContent)
                        .onChange(of: viewModel.visibleDiscussions) { oldValue, newValue in
                            // Compare against the OLD top item — this is the bug fix.
                            // Comparing against the new top item (the previous
                            // implementation) only matched by coincidence.
                            scrollTracker.handleDataChange(
                                oldTopID: oldValue.first?.id,
                                newTopID: newValue.first?.id
                            )
                        }
                    }
                    .transition(.opacity)
                }

                // Search mode
                if isSearchFocused {
                    VStack(spacing: 0) {
                        searchOverlayBar
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)

                        Divider()

                        List {
                            if !searchText.isEmpty && filteredDiscussions.isEmpty && messageSearchViewModel.results.isEmpty && !messageSearchViewModel.isSearching {
                                HStack {
                                    Spacer()
                                    Text(t(ChatTranslationKeys.CHAT_LIST_NO_RESULTS, args: [searchText]))
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 40)
                                    Spacer()
                                }
                                .listRowSeparator(.hidden)
                            }

                            ForEach(displayedDiscussions, id: \.id) { item in
                                DiscussionChat(
                                    discussion: item,
                                    hasLeftGroup: viewModel.hasLeftGroupDiscussion(item),
                                    isGroupCreatedByCurrentUser: viewModel.isGroupCreatedByCurrentUser(item),
                                    typingUser: viewModel.getTypingUser(forDiscussion: item),
                                    onShowMoreAction: {},
                                    onPressAction: { _ in },
                                    navigationCoord: navigationCoord,
                                    translator: viewModel.translationService,
                                localeToken: viewModel.translationLocaleToken
                                )
                                .equatable()  // ✅ FIX: Prevent unnecessary re-renders using Equatable protocol
                                .listRowSeparator(.hidden) // row draws its own inset divider now
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture {
                                    dismissSearch()
                                    navigationCoord.push(Self.route(for: item))
                                }
                            }

                            if !searchText.isEmpty && !messageSearchViewModel.results.isEmpty {
                                Section {
                                    ForEach(messageSearchViewModel.results) { result in
                                        searchMessageRow(result)
                                    }
                                } header: {
                                    Text(t(ChatTranslationKeys.CHAT_LIST_MESSAGES))
                                        .font(.subheadline.weight(.semibold))
                                        .textCase(nil)
                                }
                            }
                        }
                        .listStyle(.plain)
                        .contentMargins(.bottom, 80, for: .scrollContent)
                        .scrollIndicators(.hidden)
                    }
                    .background(Color(.systemBackground))
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .discussionActionLoadingOverlay(
                isLoading: viewModel.isActionLoading,
                message: viewModel.actionLoadingMessage
            )
            .discussionListToast(message: viewModel.discussionListToastMessage)
            // Waangu Copilot flotte au-dessus de la liste, comme Meta AI dans
            // WhatsApp — déplaçable, et il ouvre sa conversation comme une autre.
            .overlay {
                if copilotAvailable && !isSearchFocused {
                    CopilotFloatingButton { openCopilot() }
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .task {
                let surface = navigationCoord.feature.financeSurface
                guard surface.financeSession != nil,
                      case .success(let tools) = await surface.catalog.copilotTools() else { return }
                copilotAvailable = !tools.isEmpty
            }
            .confirmationDialog(
                FinanceStrings.copilotDeleteTitle,
                isPresented: Binding(get: { copilotPendingDeletion != nil },
                                     set: { if !$0 { copilotPendingDeletion = nil } }),
                titleVisibility: .visible
            ) {
                Button(t(ChatTranslationKeys.ACTION_DELETE), role: .destructive) {
                    guard let item = copilotPendingDeletion else { return }
                    copilotPendingDeletion = nil
                    Task { try? await navigationCoord.feature.copilotConversationStore.delete(item.conversationId) }
                }
                Button(FinanceStrings.cancel, role: .cancel) { copilotPendingDeletion = nil }
            } message: {
                Text(FinanceStrings.copilotDeleteMessage)
            }
            .edgesIgnoringSafeArea(.bottom)
            .navigationTitle(isSearchFocused ? "" : t(ChatTranslationKeys.CHAT_LIST_TITLE))
            .navigationBarTitleDisplayMode(.large) // WhatsApp shows "Chats" as a large, leading-aligned title
            .navigationBarHidden(isSearchFocused)
            .onAppear {
                viewModel.startInboxTypingObservation()
            }
            .toolbar( isSearchFocused || !navigationCoord.navigationPath.isEmpty ? .hidden : .visible, for: .tabBar)
            .chatAppearanceSheet(isPresented: $viewModel.showChatPartnerPickerView) {
                ChatPartnerPickerScreen(
                    viewModel: chatPartnerPickerViewModel,
                    translationService: viewModel.translationService,
                    onCreate: viewModel.onNewChannelCreation,
                    onCreateGroup: { groupName, members, image,settings  in
                        viewModel.createGroupDiscussion(
                            groupName: groupName,
                            members: members,
                            image: image,
                            settings: settings
                        )
                    },
                    navigationCoord: navigationCoord
                )
            }
            .onChange(of: viewModel.showChatPartnerPickerView) { isPresented in
                if !isPresented { }
            }
            .chatOptionSheet(
                showSheetOption: $showSheetOption,
                isConfirmDelete: $isConfirmDelete,
                selectedDiscussion: selectedDiscussion,
                viewModel: viewModel
            )
            .alert(t(ChatTranslationKeys.CHAT_LIST_NEW_LIST), isPresented: $viewModel.showAddDiscussionListAlert) {
                TextField(t(ChatTranslationKeys.CHAT_LIST_LIST_NAME), text: $viewModel.newDiscussionListName)
                Button(common("cancel"), role: .cancel) {
                    viewModel.newDiscussionListName = ""
                }
                Button(t(ChatTranslationKeys.NEW_GROUP_CREATE)) {
                    viewModel.createCustomDiscussionList()
                }
            } message: {
                Text(t(ChatTranslationKeys.CHAT_LIST_CREATE_LIST_DESC))
            }
            .alert(
                t(ChatTranslationKeys.CHAT_LIST_DELETE_LIST_TITLE),
                isPresented: Binding(
                    get: { viewModel.customListPendingDeletion != nil },
                    set: { if !$0 { viewModel.cancelDeleteCustomList() } }
                )
            ) {
                Button(common("cancel"), role: .cancel) {
                    viewModel.cancelDeleteCustomList()
                }
                Button(common("delete"), role: .destructive) {
                    viewModel.confirmDeleteCustomList()
                }
            } message: {
                if let list = viewModel.customListPendingDeletion {
                    Text(t(ChatTranslationKeys.CHAT_LIST_DELETE_LIST_MESSAGE, args: [list.name]))
                }
            }
            .chatAppearanceSheet(item: $profileSheetDiscussion) { discussion in
                if let contact = discussion.contact {
                    ContactQuickProfileSheet(contact: contact, translationService: viewModel.translationService) { action in
                        profileSheetDiscussion = nil
                        // A group has no phone number, so none of the contact-shaped
                        // actions apply to it: dialling `contact.phone` would place a
                        // call to the empty string, and matching a conversation by
                        // that same empty phone matches every other group in the list.
                        let isGroup = contact.isGroup
                        switch action {
                        case .message:
                            let route: ChatsTabRoute
                            if isGroup {
                                route = .chatRoom(
                                    type: .group(conversationId: discussion.conversationId),
                                    isArchived: false
                                )
                            } else {
                                let matchesContact: (DiscussionChatItem) -> Bool = { item in
                                    item.contact?.isGroup == false
                                    && !contact.phone.isEmpty
                                    && item.contact?.phone == contact.phone
                                }
                                let existingId = viewModel.discussions.first(where: matchesContact)?.conversationId
                                    ?? viewModel.archivedDiscussions.first(where: matchesContact)?.conversationId
                                route = .chatRoom(
                                    type: .direct(phoneNumber: contact.phone, conversationId: existingId),
                                    isArchived: false
                                )
                            }
                            navigationCoord.push(route)
                        case .audioCall, .videoCall:
                            let hasVideo = action == .videoCall
                            if isGroup {
                                // Every member rides the initial offer, the same way
                                // the group info screen places its calls.
                                Task { @MainActor in
                                    let invitees = await viewModel.groupCallInvitees(
                                        conversationId: discussion.conversationId
                                    )
                                    guard !invitees.isEmpty else { return }
                                    VoipManager.shared.startGroupCall(
                                        invitees,
                                        hasVideo: hasVideo,
                                        conversationId: discussion.conversationId,
                                        groupName: contact.userName
                                    )
                                }
                            } else {
                                VoipManager.shared.startOutgoingCall(
                                    to: contact.phone,
                                    hasVideo: hasVideo,
                                    name: contact.userName,
                                    image: contact.image,
                                    conversationId: discussion.conversationId,
                                    userId: contact.userId
                                )
                            }
                        }
                    }
                    .presentationDetents([.medium])
                    .presentationDragIndicator(.visible)
                } else {
                    EmptyView()
                }
            }
            .onChange(of: showSheetOption) { newValue in
                if !newValue {
                    isConfirmDelete = false
                }
            }
            .discussionDeletionDialog(
                context: $viewModel.deletionDialog,
                translationService: viewModel.translationService,
                onPrimary: { viewModel.confirmDeletionPrimaryAction() },
                onDeleteLocalContent: { viewModel.confirmDeleteLocalContent() },
                onLeaveGroup: { viewModel.confirmLeaveGroupFromDialog() },
                onExitKeepLocally: { viewModel.confirmExitAndKeepLocally() },
                onExitDeleteLocally: { viewModel.confirmExitAndDeleteLocally() }
            )
            .postLeaveLocalCleanupDialog(
                context: $viewModel.postLeaveCleanupDialog,
                translationService: viewModel.translationService,
                onKeepLocally: { viewModel.confirmPostLeaveKeepLocally() },
                onDeleteLocally: { viewModel.confirmPostLeaveDeleteLocally() }
            )
            .alert(
                t(ChatTranslationKeys.CHAT_LIST_DELETION_FAILED),
                isPresented: Binding(
                    get: { viewModel.deletionErrorMessage != nil },
                    set: { if !$0 { viewModel.deletionErrorMessage = nil } }
                )
            ) {
                Button(common("ok"), role: .cancel) {
                    viewModel.deletionErrorMessage = nil
                }
            } message: {
                if let message = viewModel.deletionErrorMessage {
                    Text(message)
                }
            }
            .toolbar {
                if !isSearchFocused {
                    leadingNavItems()
                    trailingNavItem()
                }
            }

        } else {
            // Fallback on earlier versions
        }

    }

    
    func handleDelete(item:DiscussionChatItem) {
//        if let index = props.discussionChats.firstIndex(of: item) {
//            props.discussionChats.remove(at: index)
//            props.onDeleteItem(["index" : index])
//            print("Deleted: \(item.title)")
//        }
    }

    // MARK: - Search Tap Target (non-editable, just opens search)

    private var searchTapTarget: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.gray)
                .font(.system(size: 15))
            Text(searchPlaceholder)
                .font(.subheadline)
                .foregroundColor(.gray)
            Spacer()
        }
        .padding(10)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isSearchFocused = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                isSearchFieldFocused = true
            }
        }
    }

    // MARK: - Search Bar (active, editable)

    private var searchOverlayBar: some View {
        HStack(spacing: 10) {
            Button {
                dismissSearch()
            } label: {
                Image(systemName: "arrow.left")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.primary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.gray)
                    .font(.system(size: 14))

                TextField(searchPlaceholder, text: $searchText)
                    .font(.subheadline)
                    .disableAutocorrection(true)
                    .textInputAutocapitalization(.never)
                    .focused($isSearchFieldFocused)
                    .onChange(of: searchText) { _ in
                        messageSearchViewModel.searchText = searchText
                        messageSearchViewModel.searchAllChats()
                    }

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                        messageSearchViewModel.clearSearch()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                            .font(.system(size: 15))
                    }
                }
            }
            .padding(10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private var displayedDiscussions: [DiscussionChatItem] {
        searchText.isEmpty ? baseDiscussions : filteredDiscussions
    }

    private var discussionFilterChips: some View {
        DiscussionFilterChipsView(
            items: viewModel.discussionFilterItems,
            selectedFilter: viewModel.selectedDiscussionFilter,
            translationService: viewModel.translationService,
            localeToken: viewModel.translationLocaleToken,
            showsCounts: viewModel.hasLoadedDiscussions,
            onSelect: { viewModel.selectDiscussionFilter($0) },
            onAddList: { viewModel.showAddDiscussionListAlert = true },
            onDeleteList: { filter in
                if case .customList(let id, let name) = filter {
                    viewModel.requestDeleteCustomList(listId: id, listName: name)
                }
            }
        )
    }

    private func filterEmptyRow(title: String) -> some View {
        HStack {
            Spacer()
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColors.subtitleGray)
                .multilineTextAlignment(.center)
                .padding(.vertical, 24)
            Spacer()
        }
        .listRowSeparator(.hidden)
    }

    private func searchMessageRow(_ result: MessageSearchResult) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "text.bubble")
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
                .background(Color(.systemGray6))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(result.contactName ?? "Unknown")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(result.message.displayTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(highlightMatch(result.matchedText, query: searchText))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .onTapGesture {
            dismissSearch()
            let discussion = viewModel.discussions.first { $0.conversationId == result.conversationId }
                ?? viewModel.archivedDiscussions.first { $0.conversationId == result.conversationId }
            
            // ✅ Check if this is a group discussion
            let conversationType: ConversationType
            if discussion?.contact?.isGroup == true {
                conversationType = .group(conversationId: result.conversationId)
            } else {
                let phone = discussion?.contact?.phone ?? ""
                conversationType = .direct(
                    phoneNumber: phone,
                    conversationId: result.conversationId
                )
            }
            
            let route: ChatsTabRoute = .chatRoom(type: conversationType, isArchived: false)
            navigationCoord.push(route)
        }
    }

    /// La conversation d'une ligne : Copilot, un groupe, ou un tête-à-tête.
    static func route(for item: DiscussionChatItem) -> ChatsTabRoute {
        if item.contact?.isCopilotChat == true { return .copilot(conversationId: item.conversationId) }
        let conversationType: ConversationType
        if item.contact?.isGroup == true {
            conversationType = .group(conversationId: item.conversationId)
        } else {
            conversationType = .direct(
                phoneNumber: item.contact?.phone ?? "",
                conversationId: item.conversationId
            )
        }
        return .chatRoom(type: conversationType, isArchived: false)
    }

    /// Sa conversation — l'existante, ou une nouvelle après une suppression.
    private func openCopilot() {
        Task {
            guard let id = try? await navigationCoord.feature.copilotConversationStore.conversationID() else { return }
            navigationCoord.push(ChatsTabRoute.copilot(conversationId: id))
        }
    }

    private func dismissSearch() {
        isSearchFieldFocused = false
        searchText = ""
        messageSearchViewModel.clearSearch()
        withAnimation(.easeInOut(duration: 0.2)) {
            isSearchFocused = false
        }
    }

    private func highlightMatch(_ text: String, query: String) -> AttributedString {
        var attributed = AttributedString(text)
        if let range = attributed.range(of: query, options: .caseInsensitive) {
            attributed[range].foregroundColor = .accentColor
            attributed[range].font = .caption.weight(.semibold)
        }
        return attributed
    }
}

@available(iOS 16.0, *)
struct DiscussionChat: View , Equatable {
    var isArchived:Bool = false
    let discussion:DiscussionChatItem
    var hasLeftGroup: Bool = false
    /// Whether this device's user created the group, per the stored roster.
    /// Never assumed: a member who merely received the creation event is not it.
    var isGroupCreatedByCurrentUser: Bool = false
    let typingUser: TypingUser?
    let onShowMoreAction : () -> Void
    let onPressAction : (DiscussionActionType) -> Void
    var onProfileTap: ((DiscussionChatItem) -> Void)? = nil
    let navigationCoord: ChatsTabCoordinator
    var translator: (any TranslationServiceProtocol)? = nil
    /// Bumped by ChannelTabViewModel whenever the locale changes.
    /// Including this in == ensures SwiftUI re-renders rows on language switch.
    var localeToken: Int = 0
    
    static func ==(lhs: Self, rhs: Self) -> Bool {
        lhs.discussion == rhs.discussion &&
        lhs.hasLeftGroup == rhs.hasLeftGroup &&
        lhs.isGroupCreatedByCurrentUser == rhs.isGroupCreatedByCurrentUser &&
        lhs.typingUser == rhs.typingUser &&
        lhs.localeToken == rhs.localeToken
        
    }
    private var isVideo: Bool {
        discussion.lastMessage.typeMessage == .CALL_VIDEO ||  discussion.lastMessage.typeMessage == .MISSING_CALL_VIDEO
    }
    
    private var isMissed: Bool {
        discussion.lastMessage.typeMessage == .MISSING_CALL_AUDIO || discussion.lastMessage.typeMessage == .MISSING_CALL_VIDEO
    }
    private var iconName: String {
        if isMissed {
            return isVideo ? "video.slash.fill" : "phone.down.fill"
        }
        return isVideo ? "video.fill" : "phone.fill"
    }
    
    /// A group row with nothing in it yet, which the creator's own device shows as
    /// "You created the group".
    ///
    /// Gated on actually being the creator: a member added to a group that has not
    /// been spoken in yet sees the same empty row, and claiming it for them was
    /// what made everybody the creator of every group.
    private var isOwnEmptyGroupPlaceholder: Bool {
        isGroupCreatedByCurrentUser
        && discussion.contact?.isGroup == true
        && discussion.lastMessage.codeMessage.isEmpty
        && discussion.lastMessage.message.text.isEmpty
    }
    
    /// Shorthand: resolve a chat translation key using the injected translator,
    /// or return the key itself as a plain string if no translator is available.
    private func t(_ key: String, args: [String] = []) -> String {
        translator?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private var callOutcome: CallOutcome? {
        guard discussion.lastMessage.typeMessage.isCallEvent,
              let raw = discussion.lastMessage.message.call?.outcome else { return nil }
        return CallOutcome(rawValue: raw)
    }

    private var callPreviewTone: BubbleCallTone {
        BubbleCallTone.forOutcome(callOutcome, isMissedFallback: callOutcome == nil && isMissed)
    }

    private var previewForegroundColor: Color {
        if typingUser != nil { return AppColors.primary }
        if discussion.lastMessage.typeMessage.isCallEvent && callPreviewTone == .danger { return .red }
        return hasUnread ? .primary : .gray
    }

    private var callPreviewText: String {
        let kind = t(isVideo ? ChatTranslationKeys.CALL_VIDEO : ChatTranslationKeys.CALL_AUDIO)
        switch callOutcome {
        case .failed:
            return t(ChatTranslationKeys.CALLS_BUBBLE_FAILED, args: [kind])
        case .declined:
            return t(ChatTranslationKeys.CALLS_BUBBLE_DECLINED, args: [kind])
        case .busy:
            return t(ChatTranslationKeys.CALLS_BUBBLE_BUSY, args: [kind])
        case .noAnswer:
            return t(ChatTranslationKeys.CALLS_BUBBLE_NO_ANSWER, args: [kind])
        case .cancelled:
            return t(ChatTranslationKeys.CALLS_BUBBLE_CANCELLED, args: [kind])
        case .missed:
            return t(ChatTranslationKeys.CALLS_BUBBLE_MISSED, args: [kind])
        case .answered:
            return kind
        case .none:
            return t(
                isMissed
                    ? (isVideo ? ChatTranslationKeys.CALL_VIDEO_MISSED : ChatTranslationKeys.CALL_AUDIO_MISSED)
                    : (isVideo ? ChatTranslationKeys.CALL_VIDEO : ChatTranslationKeys.CALL_AUDIO)
            )
        }
    }
    
    /// The unsent composer text to show in place of the last message, or nil.
    ///
    /// Typing wins: someone typing to you right now is newer news than what you
    /// left half-written, and the typing line is rendered by the same branch this
    /// would replace.
    private var draftPreview: String? {
        guard typingUser == nil,
              let draft = discussion.draft?.trimmingCharacters(in: .whitespacesAndNewlines),
              !draft.isEmpty
        else { return nil }
        return draft
    }

    private var showsDeliveryStatus: Bool {
        guard
              // Ticks belong to the last message, and a draft is standing where
              // that message would be — showing them together reads as if the
              // draft itself had been delivered.
              draftPreview == nil,
              discussion.lastMessage.isSentByMe,
              !discussion.lastMessage.codeMessage.isEmpty,
              // A call or group event was never "sent", so it has no ticks to show.
              !discussion.lastMessage.typeMessage.isSystemRecord else {
            return false
        }
        // Deleted-for-everyone: only pending/failed until delete ACK; no ticks after.
        if discussion.lastMessage.isDeleted {
            return discussion.lastMessage.status == .PENDING
                || discussion.lastMessage.status == .FAILED
        }
        return true
    }
    
    private var hasUnread: Bool {
        discussion.count > 0
    }

    /// Name, else number, else "Unknown user" — never a raw id, never blank.
    private var displayName: String {
        ChatDisplayName.text(
            name: discussion.contact?.userName,
            phone: discussion.contact?.phone,
            identifiers: [
                discussion.contact?.userId ?? "",
                discussion.contact?.id ?? "",
                discussion.conversationId
            ],
            translator: translator
        )
    }
    
    var body: some View {
        
        // WhatsApp's chat list uses a wider avatar↔text gap (~12pt) than the
        // 8pt this previously had.
        let chatRow = HStack(spacing: 12) {
            // Avatar with group differentiation.
            // NOTE: WhatsApp's row avatar reads larger than `.xSmall` — if
            // `GroupAwareAvatarView.Size` has a bigger case (e.g. `.medium`),
            // swap it in here for a closer match. Left as `.xSmall` since
            // that's the only case this file was using and I can't see
            // the enum's other cases from here.
            if discussion.contact?.isCopilotChat == true {
                CopilotAvatar()
            } else {
                GroupAwareAvatarView(
                    imageUrl: discussion.contact?.image,
                    isGroup: discussion.contact?.isGroup ?? false,
                    size: .xSmall,
                    onClick: {
                        onProfileTap?(discussion)
                    }
                )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(displayName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    Spacer()
                    Text(discussion.lastMessage.displayTime)
                        .font(.system(size: 14, weight: .medium))
                        .fontWeight(hasUnread ? .semibold : .regular)
                        .foregroundColor(hasUnread ? AppColors.primary : .gray)
                }
                
                HStack {
                    if showsDeliveryStatus {
                        MessageStatusIcon(messageStatus:discussion.lastMessage.status)
                    }
                    Group {
                        if let typingUser = typingUser,
                           let typingText = TypingPhrase.text(
                               for: [typingUser],
                               isGroup: discussion.contact?.isGroup ?? false,
                               translator: translator
                           ) {
                            Text(typingText)
                        } else if let draft = draftPreview {
                            DraftLastMessage(text: draft, label: t(ChatTranslationKeys.DRAFT_LABEL))
                        } else if hasLeftGroup {
                            Text(t(ChatTranslationKeys.USER_LEFT_YOU))
                        } else if isOwnEmptyGroupPlaceholder {
                            Text(t(ChatTranslationKeys.GROUP_CREATED_YOU))
                        } else if discussion.lastMessage.isViewOnce && !discussion.lastMessage.isDeleted {
                            LabelLastMessage(
                                subtitle: t(ChatTranslationKeys.CHAT_VIEW_ONCE_MESSAGE),
                                systemImage: "timer"
                            )
                        } else {
                            switch discussion.lastMessage.typeMessage {
                            case .TEXT:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : discussion.lastMessage.message.text,
                                    systemImage: nil
                                )
                            case .IMAGE:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_PHOTO),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "photo"
                                )
                                
                            case .AUDIO, .VOICE:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_VOICE),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "mic.fill"
                                )
                            case .VIDEO, .VIDEO_NOTE:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_VIDEO),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "video.fill"
                                )
                            case .DOCUMENT:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_DOCUMENT),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "doc.fill"
                                )
                            case .CALL_AUDIO:
                                LabelLastMessage(
                                    subtitle: callPreviewText,
                                    systemImage: iconName,
                                    foregroundColor: previewForegroundColor
                                )
                            case .CALL_VIDEO:
                                LabelLastMessage(
                                    subtitle: callPreviewText,
                                    systemImage: iconName,
                                    foregroundColor: previewForegroundColor
                                )
                            case .MISSING_CALL_AUDIO:
                                LabelLastMessage(
                                    subtitle: callPreviewText,
                                    systemImage: iconName,
                                    foregroundColor: previewForegroundColor
                                )
                            case .MISSING_CALL_VIDEO:
                                LabelLastMessage(
                                    subtitle: callPreviewText,
                                    systemImage: iconName,
                                    foregroundColor: previewForegroundColor
                                )
                                
                            case .CONTACT:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_CONTACT),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "person.fill"
                                )
                            case .LOCATION:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_LOCATION),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "map.fill"
                                )
                            case .POLL:
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted ? t(ChatTranslationKeys.MESSAGE_DELETED) : t(ChatTranslationKeys.MEDIA_TYPE_POLL),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : "chart.bar.fill"
                                )
                            // Un message financier n'a pas de texte : sans ce cas, la
                            // ligne tombait sur `default` et restait vide.
                            case .ISMONEY:
                                let finance = ChatListFinancePreview(message: discussion.lastMessage)
                                LabelLastMessage(
                                    subtitle: discussion.lastMessage.isDeleted
                                        ? t(ChatTranslationKeys.MESSAGE_DELETED)
                                        : finance.subtitle(translate: { t($0) }),
                                    systemImage: discussion.lastMessage.isDeleted ? nil : finance.systemImage
                                )
                            // Creation included: it is a group event like any other,
                            // and the actor decides whether it reads "You" or a name.
                            // Hardcoding the "You" string here made every member who
                            // received the event the creator of the group.
                            case .GROUP_CREATED, .GROUP_UPDATED, .USER_ADDED_TO_GROUP, .USER_JOINED_GROUP,
                                 .USER_LEFT_GROUP, .USER_REMOVED_FROM_GROUP,
                                 .USER_PROMOTED_TO_ADMIN, .USER_DEMOTED_FROM_ADMIN:
                                if let translator,
                                   let action = ChatActionItem(
                                       groupEvent: discussion.lastMessage,
                                       conversationId: discussion.id
                                   ) {
                                    Text(action.displayText(using: translator))
                                }
                            default:
                                EmptyView()
                            }
                        }
                    }
                    .font(.system(size: 16, weight: .medium))
                    .fontWeight(hasUnread && typingUser == nil ? .semibold : .regular)
                    .foregroundColor(previewForegroundColor)
                    .lineLimit(2)
                    
                    Spacer()
                    
                    if hasUnread {
                        Text("\(discussion.count)")
                            .font(.system(size: 14, weight: .medium))
                            .padding(6)
                            .background(Circle().fill(AppColors.primary))
                            .foregroundColor(.white)
                            .accessibilityLabel("\(t(ChatTranslationKeys.FILTER_UNREAD)): \(discussion.count)")
                    }
                }
            }
        }
        // Taller row + an inset divider (instead of List's default
        // full-bleed separator) to match WhatsApp, where the dividing
        // line starts under the text rather than under the avatar.
            .padding(.vertical, 8)
            .overlay(alignment: .bottom) {
                Divider().padding(.leading, 68)
            }
            .contentShape(Rectangle())
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(action: {
                    onPressAction(.toggleMarkAsRead)
                }) {
                    Label(t(ChatTranslationKeys.ACTION_MARK_READ), systemImage: "message.fill")
                }
                .tint(AppColors.primary)
                
                Button(action: { onPressAction(.togglePin) }) {
                    Label(t(ChatTranslationKeys.ACTION_PIN), systemImage: "pin.fill")
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(action: {
                    onPressAction(.toggleArchive(!isArchived))
                }) {
                    Label(
                        isArchived ? t(ChatTranslationKeys.ACTION_UNARCHIVE) : t(ChatTranslationKeys.ACTION_ARCHIVE),
                        systemImage: isArchived ? "tray.and.arrow.up.fill" : "archivebox"
                    )
                }
                // Copilot n'a ni profil, ni blocage, ni appel : rien à proposer de plus.
                if discussion.contact?.isCopilotChat != true {
                    Button(action : onShowMoreAction) {
                        Label(t(ChatTranslationKeys.ACTION_MORE), systemImage: "ellipsis")
                    }
                    .tint(Color(.systemBlue))
                }
            }
        
        
        if #available(iOS 16.0, tvOS 16.0, *) {
            chatRow.contextMenu {
                Button(action: { onPressAction(.toggleArchive(!isArchived)) }) {
                    Label(
                        isArchived ? t(ChatTranslationKeys.ACTION_UNARCHIVE) : t(ChatTranslationKeys.ACTION_ARCHIVE),
                        systemImage: isArchived ? "tray.and.arrow.up.fill" : "archivebox"
                    )
                }
                Button(role: .destructive, action: { onPressAction(.delete) }) {
                    Label(t(ChatTranslationKeys.ACTION_DELETE), systemImage: "trash")
                }
            }
        } else {
            chatRow
        }
        
    }
    
}

struct MessageStatusIcon: View {
    
    let messageStatus: MessageStatus
    var body: some View {
        
        switch messageStatus {
                case .PENDING:
                     Image(systemName: "clock")
                         .foregroundColor(.gray)
                         .font(.system(size: 13))
                case .SENT:
                        Image.custom("tick")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color(.gray))
                       
                 case .SEEN:
                        Image.custom("doubleStick")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color(.systemBlue))
                 case .UNSEEN:
                        Image.custom("tick")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color(.gray))
                 case .DELIVERED:
                        Image.custom("doubleStick")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color(.gray))
                case .FAILED:
                        Image(systemName: "exclamationmark.circle")
                            .foregroundColor(.red)
                            .font(.system(size: 14))
                 case .MODIFY:
                        Image.custom("doubleStick")
                            .resizable()
                            .renderingMode(.template)
                            .frame(width: 22, height: 22)
                            .foregroundColor(Color(.systemBlue))
                 }
        
    }
}

/// The chat list's stand-in for the last message while a draft is pending.
///
/// Sets its own colours rather than inheriting the row's `previewForegroundColor`:
/// the prefix has to keep the accent under an unread row, where the preview
/// otherwise turns `.primary`.
struct DraftLastMessage: View {
    let text: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text("\(label):")
                .foregroundColor(AppColors.primary)
            Text(text)
                .foregroundColor(.gray)
        }
        // One line, ellipsised: a draft is a reminder of what you were writing,
        // and letting a long one wrap to two lines makes it taller than every
        // other row in the list.
        .lineLimit(1)
        .truncationMode(.tail)
    }
}

/// The last-message line of a row. Typing is not its business: the row branches
/// to `TypingPhrase` before it gets here, so this only ever renders what was
/// actually said.
struct LabelLastMessage: View {
    let subtitle: String
    let systemImage: String?
    let foregroundColor: Color

    init(
        subtitle: String,
        systemImage: String?,
        foregroundColor: Color = .gray
    ) {
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.foregroundColor = foregroundColor
    }

    var body: some View {
        HStack(spacing: 4) {
            if let img = systemImage {
                Image(systemName: img)
            }
            Text(subtitle)
        }
        .font(.system(size: 16, weight: .medium))
        .foregroundColor(foregroundColor)
        .lineLimit(2)
    }
}


struct PreviewCard<PreviewChildren: View>: View  {
    let title: String
    let subtitle: String
    
    let preview: () -> PreviewChildren
    
    var body: some View {
        preview()
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.title)
                .bold()
            Text(subtitle)
                .font(.body)
                .foregroundColor(.gray)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(UIColor.secondarySystemBackground)))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
//#Preview {
//    ContentView()
//}

@available(iOS 16.0, *)
extension ChatListNativeView {
    

//    @ViewBuilder
//    private func destinationView(for route: AppRoutes) -> some View {
//        switch route {
//        case .archiveChatList:
//            if #available(iOS 16.0, *) {
//                ArchiveChatList()
//                    .environmentObject(viewModel)
//                    .toolbar(.hidden, for: .tabBar)
//            } else {
//                ArchiveChatList()
//                    .environmentObject(viewModel)
//            }
//        }
//    }
    
    @ToolbarContentBuilder
    private func leadingNavItems() -> some ToolbarContent {
        // WhatsApp's leading item is just a green "Edit" text button — no
        // menu. "Exit to host app" isn't a WhatsApp concept, so rather than
        // bury it inside a menu it's kept as its own small icon that only
        // shows up if the coordinator actually supports exiting.
        if let onExit = navigationCoord.onExitToMainApp {
            ToolbarItem(placement: .topBarLeading) {
                Button(action: onExit) {
                    Image(systemName: "chevron.left")
                }
            }
        }
//        ToolbarItem(placement: .topBarLeading) {
//            Button {
//                // TODO: wire this to a real multi-select mode (tap rows to
//                // select, then bulk Archive/Read/Delete) to fully match
//                // WhatsApp's Edit flow — that mode doesn't exist yet in this
//                // view model, so it's left as a no-op for now.
//            } label: {
//                Text("Edit")
//            }
//        }
    }
    
    @ToolbarContentBuilder
    private func trailingNavItem() -> some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            cameraButton()
            newChatButton()
        }
    }

    private func newChatButton() -> some View {
        Button {
            viewModel.showChatPartnerPickerView = true
        } label: {
            // WhatsApp's "new chat" icon is a square-and-pencil glyph, not a
            // plus — swapped to match.
            Image(systemName: "square.and.pencil")
        }
        .tint(AppColors.primary)
    }
    
    private func cameraButton() -> some View {
        Button {
            
        } label: {
            Image(systemName: "camera")
        }
        .tint(AppColors.primary)
    }
    
    private func archivedButton() -> some View {
        Button {
            let route: ChatsTabRoute = .archiveChat
            navigationCoord.push(route)
        } label: {
            HStack {
                // WhatsApp shows the archive glyph inside a small filled
                // rounded square rather than as a bare icon.
                Image(systemName: "archivebox.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(.white)
                    .frame(width: 28, height: 28)
                    .background(Color(.systemGray3))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(viewModel.translationService?.resolve(key: ChatTranslationKeys.ARCHIVED_LABEL, module: ChatTranslationKeys.MODULE).value ?? "Archived")
                    .foregroundStyle(.primary)

                Spacer()

                Text("\(viewModel.archivedDiscussions.count)")
                    .foregroundStyle(Color(.systemGray))
            }
            .padding(.vertical, 4)
        }
    }
    
    private func inboxFooterView() -> some View {
        HStack {
            Image(systemName: "lock.fill")
            Text(viewModel.translationService?.resolve(key: ChatTranslationKeys.E2EE_BANNER, module: ChatTranslationKeys.MODULE).value ?? "Your personal messages are end-to-end encrypted.")
        }
        .foregroundStyle(.gray)
        .font(.caption)
        .padding(.horizontal)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Pending Group Row Component

@available(iOS 16.0, *)
struct PendingGroupRow: View {
    let group: GroupChat
    let translationService: (any TranslationServiceProtocol)?
    let onRetry: () -> Void
    
    @State private var isRetrying = false

    init(
        group: GroupChat,
        translationService: (any TranslationServiceProtocol)? = nil,
        onRetry: @escaping () -> Void
    ) {
        self.group = group
        self.translationService = translationService
        self.onRetry = onRetry
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Group Avatar
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 50, height: 50)
                .overlay {
                    Image(systemName: "person.3.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                }
            
            // Group Info
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(group.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    
                    // Status Badge
                    if isRetrying {
                        Text(t(ChatTranslationKeys.GROUP_SYNC_RETRYING))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.15))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    } else if group.syncStatus == .failed {
                        Text(t(ChatTranslationKeys.GROUP_SYNC_FAILED))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.red.opacity(0.15))
                            .foregroundStyle(.red)
                            .clipShape(Capsule())
                    } else {
                        Text(t(ChatTranslationKeys.GROUP_SYNC_CREATING))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(.orange)
                            .clipShape(Capsule())
                    }
                }
                
                Text(t(ChatTranslationKeys.GROUP_INFO_PARTICIPANT_COUNT, args: ["\(group.memberCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            
            Spacer()
            
            // Retry Button or Loading Indicator
            if isRetrying {
                // Show loading when retrying
                ProgressView()
                    .scaleEffect(0.8)
            } else if group.syncStatus == .failed {
                // Show retry button when failed
                Button {
                    isRetrying = true
                    onRetry()
                    // Reset after a delay (will be updated by state changes)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isRetrying = false
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                }
                .disabled(isRetrying)
            } else {
                // Show loading indicator for pending status
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.vertical, 8)
        .opacity(isRetrying ? 0.85 : 0.7)
        .animation(.easeInOut(duration: 0.2), value: isRetrying)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
