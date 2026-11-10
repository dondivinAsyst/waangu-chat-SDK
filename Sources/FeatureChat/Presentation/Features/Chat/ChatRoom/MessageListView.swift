//
//  MessageListView.swift
//  Pods
//  Created by Don divin on 2/6/26.
//

import SwiftUI
import Combine
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 17.0, *)
struct MessageListView: View {
    @ObservedObject var viewModel: ChatRoomViewModel
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @ObservedObject var uploadVM: FileUploadViewModel
    var contactsUseCases:ContactsUseCasesProtocol
    let opusPlaybackService: any OpusPlaybackServiceProtocol
    let navigationCoord: ChatsTabCoordinator
    let globalAudioPlaybackManager:GlobalAudioPlaybackManager
    
    // Callbacks
    var onUserDraggingChanged: ((Bool) -> Void)?
    var onScrollDirectionChanged: ((ScrollDirection?) -> Void)?
    var onGroupIntroAddMembers: (() -> Void)?
    var onGroupIntroInviteLink: (() -> Void)?
    var onJoinRequestCheckpointTap: (() -> Void)?
    
    // MARK: - Scroll State
    @State private var scrollProxy: ScrollViewProxy?
    @State private var isNearBottom = true
    @State private var showScrollToBottomButton = false
    /// The row to hold still while an older page is spliced in above it.
    ///
    /// It is cleared only by the splice itself, never by an unrelated timeline
    /// change: read receipts, reactions, poll votes and inbound messages all
    /// rebuild `groupedMessages` while a page is in flight, and every one of
    /// them used to consume the anchor before the page could arrive.
    @State private var paginationAnchorRowId: String?
    /// The splice count this list has already reacted to. Compared against the
    /// view model's rather than consuming a flag, so no amount of unrelated
    /// traffic between the splice and this check can swallow the signal.
    @State private var seenPrependGeneration = 0
    /// False until the user has actually dragged the list. See `handleRowAppeared`.
    @State private var hasUserScrolled = false

    /// One older page per gesture, no matter how far the drag travels.
    ///
    /// `isRowNearTop` is index-based, so the instant a page is spliced in the
    /// new top rows appear and arm the next one. A single drag used to pull
    /// three pages (14 → 28 → 42 → 56 messages), and since each restore lands
    /// slightly off, the error compounded once per page. Re-armed only when a
    /// new drag begins, so momentum after the lift cannot chain another page.
    @State private var pageArmed = true
    @State private var isDragging = false
    
    // MARK: - Combine
    @State private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Context Menu
    @State private var showContextMenu = false
    @State private var selectedMessageForContext: MessageRow?
    @State private var showReactionEmojiPicker = false
    @State private var messagePendingCustomReaction: MessageDataItem?
    
    // MARK: - Highlight Animation
    @State private var highlightedMessageId: String?
    @State private var highlightOpacity: Double = 0
    
    // MARK: - Input
    @State private var inputHeight: CGFloat = 60
    @State private var previousMessageCount: Int = 0
    @State private var pendingNewMessageCount = 0
    @State private var messageCountWhenLeftBottom = 0
    
    var body: some View {
        ZStack {
            // Background
            backgroundView
            
            VStack(spacing: 0) {
                messagesScrollView
                
                // Reply View
                if viewModel.replyMessage != nil {
                    ReplyViewSwiftUI(chatRoomVM: viewModel, uploadVM: uploadVM)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                // Link preview while composing
                if let url = viewModel.composeLinkURL {
                    ComposeLinkPreviewView(url: url, preview: viewModel.composeLinkPreview) {
                        viewModel.dismissLinkPreview()
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
   
                
                if viewModel.isGroupReadOnly {
                    LeftGroupReadOnlyActionBar(translationService: viewModel.translationService)
                } else if let restriction = viewModel.writeRestriction {
                    // A broadcast channel or a community's announcements group:
                    // everyone reads, only the owner or an admin writes.
                    RestrictedRoomActionBar(
                        restriction: restriction,
                        translationService: viewModel.translationService
                    )
                } else if viewModel.isSelectionMode {
                    // Selection mode: hide composer. Forward shows action bar; delete uses header Cancel/Delete.
                    if viewModel.isForwardSelectionMode {
                        ForwardSelectionActionBar(
                            selectedCount: viewModel.selectedMessages?.count ?? 0,
                            translationService: viewModel.translationService,
                            onCancel: {
                                viewModel.exitSelectionMode()
                            },
                            onForward: {
                                viewModel.showForwardPicker()
                            }
                        )
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                } else if !viewModel.isContactBlocked {
                    TypingIndicatorView(
                        users: viewModel.typingUsers,
                        isGroup: viewModel.isGroup,
                        translator: viewModel.translationService,
                        localeToken: viewModel.translationLocaleToken
                    )
                    ChatComposerBar(
                        composer: viewModel.composer,
                        viewModel: viewModel,
                        localeToken: viewModel.translationLocaleToken,
                        userInterfaceStyle: appearanceStore.defaultAppearance.userInterfaceStyle,
                        contentHeight: $inputHeight
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }else{
                    BlockedConversationActionBar(translationService: viewModel.translationService, onUnblock: {
                        viewModel.blockContact()  // This will toggle to unblock
                    }, onClearMessages: {
                        Task {
                            do {
                                try await viewModel.clearAllMessagesLocally()
                            } catch {
                                debugLog("Error clearing messages: \(error)")
                            }
                        }
                    })
                }
                              }
                              // blur when context menu is open
                              .blur(radius: showContextMenu ? 12 : 0)
                              .scaleEffect(showContextMenu ? 0.95 : 1.0)
                              .allowsHitTesting(!showContextMenu)
                              .animation(.easeInOut(duration: 0.3), value: viewModel.isSelectionMode)
                              .animation(.easeInOut(duration: 0.3), value: viewModel.isForwardSelectionMode)
                              .animation(.easeInOut(duration: 0.3), value: viewModel.messageBeingEdited?.id)
         
              
            
            // Scroll-to-bottom FAB
            if showScrollToBottomButton && !showContextMenu && viewModel.replyMessage == nil {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        scrollToBottomButton
                            .padding(.trailing, 16)
                            .padding(.bottom, inputHeight + 30)
                    }
                }
                .transition(.scale.combined(with: .opacity))
            }
            
            // Pagination loading indicator at top
            if viewModel.isLoadingMore {
                VStack {
                    ProgressView()
                        .controlSize(.small)
                        .padding(8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.top, 110)
                    Spacer()
                }
                .transition(.opacity)
            }
            
            // Context Menu Overlay (WhatsApp-style)
            if showContextMenu, let message = selectedMessageForContext {
                contextMenuOverlay(for: message)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showScrollToBottomButton)
        .chatAppearanceSheet(isPresented: $showReactionEmojiPicker, onDismiss: {
            messagePendingCustomReaction = nil
        }) {
            ReactionEmojiPickerSheet(translationService: viewModel.translationService) { emoji in
                if let message = messagePendingCustomReaction {
                    viewModel.addReaction(emoji: emoji, to: message)
                }
                messagePendingCustomReaction = nil
                showReactionEmojiPicker = false
            }
        }
        .onAppear {
            previousMessageCount = viewModel.messages.count
            messageCountWhenLeftBottom = viewModel.messages.count
            setupMessageListener()
            refreshEditHighlight(for: viewModel.messageBeingEdited?.id)
        }
        .onChange(of: viewModel.messageBeingEdited?.id) { _, editedMessageId in
            refreshEditHighlight(for: editedMessageId)
        }
        .preferredColorScheme(appearanceStore.defaultAppearance.preferredColorScheme)
    }
    
    // MARK: - Background View
    
    private var backgroundView: some View {
        Image("chatBackground", bundle: .module)
            .resizable()
            .ignoresSafeArea()
    }
    
    // MARK: - Messages ScrollView
    
    private var messagesScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(viewModel.groupedMessages) { section in
                        Section(header: sectionHeader(for: section)) {
                            ForEach(section.rows) { row in
                                messageRow(message: row)
                                    .id(row.id)
                                    .onAppear {
                                        handleRowAppeared(row)
                                    }
                                    .onDisappear {
                                        handleRowDisappeared(row)
                                    }
                            }
                        }
                    }
                }
                .padding(.bottom, 5)
            }
            .defaultScrollAnchor(viewModel.shouldShowGroupIntroHeader ? .top : .bottom)
//            .safeAreaInset(edge: .top) {
//                Spacer().frame(width:100,height: 100).background(.red.opacity(0.5))
//            }
            .scrollDismissesKeyboard(.interactively)
            .simultaneousGesture(
                TapGesture().onEnded { _ in
                    ChatKeyboard.hide()
                }
            )
            .simultaneousGesture(
                DragGesture(minimumDistance: 8)
                    .onChanged { _ in
                        hasUserScrolled = true
                        // Only on the leading edge of a gesture: onChanged fires
                        // continuously, and re-arming throughout the drag would
                        // put the chained pages straight back.
                        if !isDragging {
                            isDragging = true
                            pageArmed = true
                        }
                    }
                    .onEnded { _ in isDragging = false }
            )
            .onAppear {
                scrollProxy = proxy
            }
            .onChange(of: viewModel.groupedMessages) { _, _ in
                handleMessagesChanged(proxy: proxy)
            }
            .onChange(of: viewModel.messageBeingEdited?.id) { _, editedMessageId in
                guard let editedMessageId else { return }
                highlightedMessageId = editedMessageId
                scrollToMessage(withId: editedMessageId, position: .center, animated: true, shouldHighlight: false)
            }
        }
    }
    // MARK: - Scroll-to-Bottom Button
    
    private var scrollToBottomButton: some View {
        Button {
            scrollToBottom()
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "chevron.down")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.primary)
                    .frame(width: 36, height: 36)
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.15), radius: 4, x: 0, y: 2)

                if pendingNewMessageCount > 0 {
                    Text(pendingNewMessageCount > 99 ? "99+" : "\(pendingNewMessageCount)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                        .offset(x: 6, y: -6)
                }
            }
        }
    }
    
    // MARK: - Section Header
    
    private func sectionHeader(for section: MessageSection) -> some View {
        MessageStickyHeaderSwiftUIView(date: section.date)
    }
    
    // MARK: - Message Row

    private func messageRow(message row: MessageRow) -> some View {
        let direction: MessageDirection
        let id: String
        let primaryMessage: MessageDataItem?

        switch row {
        case .message(let message):
            direction = message.direction
            id = message.id
            primaryMessage = message
        case .mediaGroup(_, let messages):
            let first = messages.first
            direction = first?.direction ?? .sent
            id = row.id
            primaryMessage = first
        case .checkpoint(let action):
            direction = .sent // Checkpoints are centered, but we need a value
            id = action.id
            primaryMessage = nil
        case .encryptionBanner:
            direction = .sent
            id = row.id
            primaryMessage = nil
        case .groupIntro:
            direction = .sent
            id = row.id
            primaryMessage = nil
        }

        let isHighlighted = highlightedMessageId == id || viewModel.messageBeingEdited?.id == id
        let inSelectionMode = viewModel.isSelectionMode
        let isSelected = primaryMessage.map { viewModel.isMessageSelected($0) } ?? false

        let bubble = BubbleView(
            row: row,
            channel: viewModel.channel,
            senderRunPosition: viewModel.senderRunPositions[row.id],
            uploadVM: uploadVM,
            chatVM: viewModel,
            isSelectionMode: inSelectionMode,
            isContextMenuVisible: showContextMenu,
            isGroupAdmin: viewModel.isGroupAdmin,
            contactsUseCases: contactsUseCases,
            opusPlaybackService: opusPlaybackService,
            navigationCoord: navigationCoord,
            globalAudioPlaybackManager: globalAudioPlaybackManager,
            onGroupIntroAddMembers: onGroupIntroAddMembers,
            onGroupIntroInviteLink: onGroupIntroInviteLink,
            onJoinRequestCheckpointTap: onJoinRequestCheckpointTap
        )
        .ifCondition(isHighlighted) { view in
            view.overlay(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.green.opacity(highlightOpacity(for: id)))
                    .animation(.easeInOut(duration: 0.7), value: highlightOpacity)
            )
        }

        if inSelectionMode {
            return AnyView(
                HStack(spacing: 8) {
                    if isSystemTimelineRow(row) || isDeletedTimelineRow(row) {
                        bubble
                    } else {
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 22))
                            .foregroundColor(isSelected ? AppColors.primary : .gray.opacity(0.5))

                        bubble
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if isSystemTimelineRow(row) || isDeletedTimelineRow(row) {
                        return
                    }
                    
                    if let msg = primaryMessage {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            viewModel.toggleSelection(for: msg)
                        }
                    }
                }
                .opacity(isSelected ? 1.0 : 0.7)
            )
        } else if isDeletedTimelineRow(row) || isSystemTimelineRow(row) {
            // Deleted / system rows: no long-press menu or swipe-to-reply.
            return AnyView(bubble)
        } else {
            return AnyView(
                SwipeToReplyRow(
                    direction: direction,
                    onReply: { triggerReply(for: row) },
                    onLongPress: { handleLongPress(on: row) }
                ) {
                    bubble
                }
            )
        }
    }
    
    // MARK: - Row Visibility Tracking
    
    private func handleRowAppeared(_ row: MessageRow) {
        if isLastRow(row) {
            if !isNearBottom {
                isNearBottom = true
                resetScrollDownBadge()
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollToBottomButton = false
                }
            }
        }
        
        // Older pages are only fetched once the user has actually dragged.
        //
        // On entry the scroll view instantiates the topmost rows in order to measure
        // the content it is about to anchor to the bottom, so their `onAppear` fired
        // before anything was on screen. That paginated the instant the room opened
        // and shifted the content under the first frame the user ever saw.
        guard hasUserScrolled, pageArmed else { return }
        guard viewModel.hasMore, !viewModel.isLoadingMore else { return }

        if isRowNearTop(row) {
            pageArmed = false
            paginationAnchorRowId = row.id
            viewModel.loadMoreIfNeeded()
        }
    }
    
    private func handleRowDisappeared(_ row: MessageRow) {
        if isLastRow(row) {
            if isNearBottom {
                isNearBottom = false
                messageCountWhenLeftBottom = viewModel.messages.count
                pendingNewMessageCount = 0
                withAnimation(.easeInOut(duration: 0.2)) {
                    showScrollToBottomButton = true
                }
            }
        }
    }
    
    private func isLastRow(_ row: MessageRow) -> Bool {
        guard let lastSection = viewModel.groupedMessages.last,
              let lastRow = lastSection.rows.last else { return false }
        return lastRow.id == row.id
    }
    
    private func isRowNearTop(_ row: MessageRow) -> Bool {
        var count = 0
        for section in viewModel.groupedMessages {
            for r in section.rows {
                if r.id == row.id { return true }
                count += 1
                if count >= 3 { return false }
            }
        }
        return false
    }
    
    // MARK: - Messages Changed Handler
    
    private func handleMessagesChanged(proxy: ScrollViewProxy) {
        let newCount = viewModel.messages.count
        let delta = newCount - previousMessageCount
        previousMessageCount = newCount

        // An older page spliced in above the window is the only change allowed to
        // move the scroll position backwards, and it is reported explicitly by
        // the view model rather than inferred from the message count — a receipt
        // changes the timeline without changing the count, and an inbound message
        // changes the count without being a page.
        let generation = viewModel.prependGeneration
        let didPrependPage = generation != seenPrependGeneration
        seenPrependGeneration = generation


        if didPrependPage {
            if let rowId = paginationAnchorRowId {
                paginationAnchorRowId = nil
                // Same update as the splice, with animation off: deferring this to
                // the next runloop turn let the prepend shift the content for one
                // frame before the correction snapped it back — the visible jump.
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    proxy.scrollTo(rowId, anchor: .top)
                }
            }
            // Returns even without an anchor. A prepend must never fall through
            // to the scroll-to-bottom below: `isNearBottom` only goes false when
            // the *last* row's `onDisappear` fires, and the lazy stack often
            // keeps that row alive while the user is far up the thread, so the
            // stale flag would yank the list to the end of the conversation.
            return
        }

        // Until the user touches the list, it follows the newest message,
        // whatever arrives. The unread messages reach the list just after the
        // room opens; with the `isNearBottom` check below they landed under the
        // screen and the room sat on the last message already read.
        //
        // The list's own `scrollToBottom`, with its animation, once now and once
        // on the next frame: the second lands after the new rows are measured
        // (call and money cards are taller than the lazy stack's estimate).
        if !hasUserScrolled, !viewModel.shouldShowGroupIntroHeader {
            scrollToBottom()
            DispatchQueue.main.async {
                guard !hasUserScrolled else { return }
                scrollToBottom()
            }
            return
        }

        if !isNearBottom {
            refreshPendingNewMessageCount()
        }
        
        // No upper bound on the batch: the cap of 3 was there to stop a paginated
        // page from dragging the view to the bottom, and the anchor path above now
        // handles that case and returns. All the cap did was strand the user
        // mid-thread whenever four or more messages landed at once.
        guard delta > 0, isNearBottom else { return }
        
        if let lastSection = viewModel.groupedMessages.last,
           let lastRow = lastSection.rows.last {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                proxy.scrollTo(lastRow.id, anchor: .bottom)
            }
        }
    }

    private func refreshPendingNewMessageCount() {
        guard !isNearBottom else { return }
        let added = viewModel.messages.count - messageCountWhenLeftBottom
        guard added > 0 else {
            pendingNewMessageCount = 0
            return
        }
        pendingNewMessageCount = viewModel.messages.suffix(added).filter { !$0.isSentByMe }.count
    }

    private func resetScrollDownBadge() {
        pendingNewMessageCount = 0
        messageCountWhenLeftBottom = viewModel.messages.count
    }
    
    // MARK: - Context Menu Overlay (WhatsApp-style)
    
    private func contextMenuOverlay(for row: MessageRow) -> some View {
        ZStack {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    dismissContextMenu()
                }
                .transition(.opacity)
            
            VStack(spacing: 12) {
                Spacer()

                if let message = row.primaryMessage {
                    ReactionPickerView(message: message) { reaction in
                        if reaction == .more {
                            messagePendingCustomReaction = message
                            dismissContextMenu {
                                showReactionEmojiPicker = true
                            }
                        } else {
                            dismissContextMenu {
                                viewModel.addReaction(reaction, to: message)
                            }
                        }
                    }
                    .transition(.scale(scale: 0.6, anchor: message.menuAnchor).combined(with: .opacity))
                }

                messageCellSnapshot(for: row)
                    .transition(.scale(scale: 0.85).combined(with: .opacity))
                    .allowsHitTesting(false)

                MessageMenuView(row: row, translator: viewModel.translationService) { action in
                    dismissContextMenu {
                        viewModel.onMessageAction(action, to: row)
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                
                Spacer()
            }
            .padding(.horizontal, 20)
            .zIndex(1)
        }
    }
    
    private func messageCellSnapshot(for row: MessageRow) -> some View {
        BubbleView(
            row: row,
            channel: viewModel.channel,
            // The lifted copy under the context menu is the bubble alone — no
            // name, no face, no gutter shifting it off the one it replaces.
            senderRunPosition: nil,
            uploadVM: uploadVM,
            chatVM: viewModel,
            isSelectionMode: viewModel.isSelectionMode,
            isContextMenuVisible: showContextMenu,
            isGroupAdmin: viewModel.isGroupAdmin,
            contactsUseCases: contactsUseCases,
            opusPlaybackService: opusPlaybackService,
            navigationCoord: navigationCoord,
            globalAudioPlaybackManager: globalAudioPlaybackManager
        )
        .shadow(color: .black.opacity(0.18), radius: 16, x: 0, y: 8)
        .scaleEffect(1.02)
        // The lifted copy sits in a VStack between two Spacers, so it is offered a
        // real height instead of the unspecified one it gets in the timeline. Pin it
        // to its ideal height so no flexible child can stretch the bubble.
        .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Long Press Handler
    
    private func handleLongPress(on message: MessageRow) {
        guard !isDeletedTimelineRow(message), !isSystemTimelineRow(message) else { return }
        viewModel.contextMenuIsVisible = true
        Haptic.impact(.medium)
        selectedMessageForContext = message
        withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) {
            showContextMenu = true
        }
    }
    
    private func dismissContextMenu(completion: (() -> Void)? = nil) {
        viewModel.contextMenuIsVisible = false
        withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
            showContextMenu = false
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            selectedMessageForContext = nil
            completion?()
        }
    }
    
    private func triggerReply(for row: MessageRow) {
        guard !isDeletedTimelineRow(row), !isSystemTimelineRow(row) else { return }
        withAnimation {
            viewModel.replyMessage = row
        }
    }
    
    // MARK: - Setup
    
    private func setupMessageListener() {
        viewModel.$scrollToBottomRequest
            .debounce(for: .milliseconds(10), scheduler: DispatchQueue.main)
            .sink { scrollRequest in
                if scrollRequest.scroll {
                    scrollToBottom(animated: scrollRequest.isAnimated)
                }
            }
            .store(in: &cancellables)

        viewModel.$scrollToMessage
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .receive(on: DispatchQueue.main)
            .sink { [self] target in
                let resolvedId = viewModel.photoCodeToGroupId[target] ?? target
                scrollToMessage(withId: resolvedId)
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Scroll Functions
    
    func scrollToMessage(
        withId messageId: String,
        position: UnitPoint = .center,
        animated: Bool = true,
        shouldHighlight: Bool = true
    ) {
        // The room now shows a chosen message: stop following the bottom.
        hasUserScrolled = true
        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                scrollProxy?.scrollTo(messageId, anchor: position)
            }
        } else {
            scrollProxy?.scrollTo(messageId, anchor: position)
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            viewModel.scrollToMessage = ""
            if shouldHighlight {
                highlightMessage(withId: messageId)
            }
        }
    }
    
    func scrollToMessage(
        withCodeMessage codeMessage: String,
        position: UnitPoint = .center,
        animated: Bool = true
    ) {
        if let groupId = viewModel.photoCodeToGroupId[codeMessage] {
            scrollToMessage(withId: groupId, position: position, animated: animated)
            return
        }

        for section in viewModel.groupedMessages {
            for row in section.rows {
                if case .message(let message) = row,
                   message.codeMessage == codeMessage {
                    scrollToMessage(withId: message.id, position: position, animated: animated)
                    return
                }
            }
        }
    }

    func scrollToBottom(animated: Bool = true) {
        guard let lastSection = viewModel.groupedMessages.last,
              let lastRow = lastSection.rows.last else { return }

        resetScrollDownBadge()

        if animated {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                scrollProxy?.scrollTo(lastRow.id, anchor: .bottom)
            }
        } else {
            scrollProxy?.scrollTo(lastRow.id, anchor: .bottom)
        }
    }
    
    // MARK: - Highlight Animation
    
    private func highlightMessage(withId messageId: String) {
        highlightedMessageId = messageId
        withAnimation(.easeIn(duration: 0.2)) {
            highlightOpacity = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard viewModel.messageBeingEdited?.id != messageId else { return }
            withAnimation(.easeOut(duration: 1.5)) {
                highlightOpacity = 0
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if viewModel.messageBeingEdited?.id != messageId {
                    highlightedMessageId = nil
                }
            }
        }
    }

    private func highlightOpacity(for messageId: String) -> Double {
        viewModel.messageBeingEdited?.id == messageId ? 0.18 : highlightOpacity * 0.1
    }

    private func refreshEditHighlight(for messageId: String?) {
        guard let messageId else {
            withAnimation(.easeOut(duration: 0.2)) {
                highlightOpacity = 0
            }
            if viewModel.messageBeingEdited == nil {
                highlightedMessageId = nil
            }
            return
        }

        highlightedMessageId = messageId
        withAnimation(.easeInOut(duration: 0.2)) {
            highlightOpacity = 1
        }
    }
}

// MARK: - Conditional Modifier Helper

extension View {
    @ViewBuilder
    func ifCondition<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}

// MARK: - MessageRow Helpers

private func isSystemTimelineRow(_ row: MessageRow) -> Bool {
    switch row {
    case .checkpoint, .encryptionBanner, .groupIntro:
        return true
    case .message(let message):
        // A group event arrives as a message but is a system record: no selection,
        // no long-press menu, no swipe-to-reply. The timeline already turns these
        // into checkpoints — this keeps the gate closed if one ever gets past it.
        return message.typeMessage.isGroupEvent
    case .mediaGroup:
        return false
    }
}

private func isDeletedTimelineRow(_ row: MessageRow) -> Bool {
    switch row {
    case .message(let message):
        return message.isDeleted
    case .mediaGroup(_, let messages):
        return messages.allSatisfy(\.isDeleted)
    case .checkpoint, .encryptionBanner, .groupIntro:
        return false
    }
}

extension MessageRow {
    var lastMessageId: String? {
        switch self {
        case .message(let message): return message.id
        case .mediaGroup(_, let messages): return messages.last?.id
        case .checkpoint(let action): return action.id
        case .encryptionBanner, .groupIntro:
            return nil
        }
    }
}

// MARK: - Scroll Direction Enum

enum ScrollDirection {
    case up
    case down
}

private struct LeftGroupReadOnlyActionBar: View {
    let translationService: (any TranslationServiceProtocol)?
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.caption)
                Text(t(ChatTranslationKeys.CHAT_LEFT_GROUP_READONLY))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            
            Divider()
        }
        .background(Material.regular)
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}

/// Says why the composer is missing in a channel or an announcements group.
///
/// Deliberately not a disabled composer: a text field that cannot send reads as
/// broken, while a line of text reads as a rule.
private struct RestrictedRoomActionBar: View {
    let restriction: ConversationWriteRestriction
    let translationService: (any TranslationServiceProtocol)?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "megaphone")
                    .font(.caption)
                Text(t(messageKey))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()
        }
        .background(Material.regular)
    }

    private var messageKey: String {
        switch restriction {
        case .channelOwnerOnly:        return ChatTranslationKeys.CHAT_BROADCAST_READONLY
        case .announcementsAdminsOnly: return ChatTranslationKeys.CHAT_ANNOUNCEMENTS_READONLY
        }
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}

private struct BlockedConversationActionBar: View {
    
    let translationService: (any TranslationServiceProtocol)?
    let onUnblock: () -> Void
    let onClearMessages: () -> Void
    
    var body: some View {
        
        VStack(spacing: 0) {
            
            // Info header — like WhatsApp's "You blocked this contact" label
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                Text(t(ChatTranslationKeys.CHAT_BLOCKED_CONTACT))
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            .padding(.top, 10)
            .padding(.bottom, 6)
            
            Divider()
            
            HStack(spacing: 0) {
                
                // Unblock — primary/positive action on the LEFT in WhatsApp
                Button {
                    onUnblock()
                } label: {
                    Text(t(ChatTranslationKeys.CHAT_UNBLOCK))
                        .fontWeight(.semibold)
                        .foregroundStyle(.green) // WhatsApp green, not blue
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
                
                Divider()
                    .frame(height: 24)
                
                // Delete Chat — destructive on the RIGHT
                Button(role: .destructive) {
                    onClearMessages()
                } label: {
                    Text(t(ChatTranslationKeys.CHAT_DELETE_CHAT))
                        .fontWeight(.semibold)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                }
            }
        }
        .background(Color(.systemBackground)) // WhatsApp uses solid white, not blurred material
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}
