//
//  ChatRoomViewModel.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 15.01.2025.
//

import Foundation
import Combine
import PhotosUI
import SwiftUI
import UIKit
import WaanguSharedUI
import AVFoundation
import WaanguCoreKit


enum UserTypingStatus {
    case isTyping
    case isRecording
}

enum NavBarActionsType {
    case goBack
    case profile
    case callVideo
    case callAudio
}


@MainActor
final class ChatRoomViewModel: ObservableObject, ForwardMessageSource {
    
//    public let coordinator: ChatRoomCoordinator
//    let scrollToMessage = PassthroughSubject<String, Never>()
    @Published var scrollToMessage:String = ""
    /// Set when user taps a status reply preview — ChatRoom presents single-segment viewer.
    @Published var pendingStatusReplyCode: String?
    
    @Published  var contextMenuIsVisible: Bool = false
    /// Deliberately not `@Published`: the composer changes on every keystroke, and
    /// routing that through this view model re-rendered the whole message list per
    /// character. The composer bar observes the model directly instead.
    let composer = ChatComposerModel()

    /// Passthrough so everything that reads or sets the draft keeps working, while
    /// the change notification stays confined to `composer`.
    var textMessage: String {
        get { composer.text }
        set {
            // The field writes through its binding and then reports the same text
            // via `onTextChanged`. Without this guard every keystroke published twice.
            guard composer.text != newValue else { return }
            composer.text = newValue
        }
    }
    @Published var groupedMessages: [MessageSection] = []
    @Published var messages: [MessageDataItem] = []
    // MARK: for pagination started
    @Published var isLoadingMore = false
    @Published var hasMore = true
    @Published var oldestLoadedDate: Date?

    /// How many older pages have been spliced in above the window so far.
    ///
    /// Monotonic on purpose, and never reset here. The list keeps its own copy
    /// and restores its scroll anchor whenever the two differ, so the signal
    /// survives any number of unrelated updates landing in between.
    ///
    /// A boolean does not work, and neither does `isLoadingMore`. Both are
    /// cleared by whatever runs next, and something always does: the sink that
    /// applies a page also kicks off `markVisibleMessagesAsRead()`, whose write
    /// comes straight back through the database observation as a second
    /// publish. Both sinks run before SwiftUI evaluates the body once, so a
    /// flag set by the first is already cleared by the second when `onChange`
    /// finally reads it -- and the list jumps.
    @Published private(set) var prependGeneration: Int = 0
    // MARK: Pagination ended
    @Published var replyMessage: MessageRow? = nil
    @Published private(set) var messageBeingEdited: MessageDataItem? = nil
    @Published var selectedMessages: [MessageDataItem]? = nil
    @Published var messageAction: MessageMenuAction? = nil
    @Published var showForwardMessagePicker = false
    @Published var stubMessages  = MessageItem.stubMessages
    @Published var showPhotoPicker = false
    @Published var showCameraCapture = false
    @Published var showVideoNoteRecorder = false
    /// Set by the recorder's view-once button; consumed by the next voice send.
    private var voiceNoteIsViewOnce = false
    /// The view-once message open full screen, if any.
    @Published private(set) var viewOnceMessage: MessageDataItem?
    @Published var galleryEditorPreview: PreviewMediaItem?
//    @Published var photoPickerItems: [PhotosPickerItem] = []
    @Published var photoPickerItems: [String] = []
    @Published var mediaAttachments: [MediaAttachment] = []
    @Published var videoPlayerState: (show: Bool, player: AVPlayer?) = (false, nil)
    @Published var isRecordingVoiceMessage = false
    @Published var elapsedVoiceMessageTime: TimeInterval = 0
    @Published var scrollToBottomRequest: (scroll: Bool, isAnimated: Bool) = (false, false)
    @Published var isPaginating = false
    // Media viewer — one request replaces the seven pieces of carousel state
    // (frame, transition image, mode, index, open flag, video sheet flag, URL)
    // the SwiftUI hero needed.
    @Published var allMediasMessages: [MessageDataItem] = []
    @Published var mediaViewerRequest: MediaViewerRequest?
    @Published var showDocumentPreview: Bool = false
    @Published var documentPreviewURL: URL?
    
    // Error notification
    @Published var showErrorNotification: Bool = false
    @Published var errorNotificationMessage: String = ""
    
    // Loading state for invite link operations
    @Published var isLoadingInviteLink: Bool = false
    @Published var inviteLinkLoadingMessage: String = ""

//    @Published var messagesToDelete: [MessageDataItem] = []

    // Link preview while composing
    @Published var composeLinkPreview: LinkPreviewData?
    @Published var composeLinkURL: URL?
    private var linkDetectionTask: Task<Void, Never>?
    
    /// Maps a photo/video codeMessage → its media-group scroll ID.
    private(set) var photoCodeToGroupId: [String: String] = [:]
    private var timelineBuilder = ChatRoomTimelineBuilder()
    
    private(set) var channel: ChannelItem = .placeholder
    private var subscriptions = Set<AnyCancellable>()
    let messagesStore: ChatRoomMessagesStore
    private let conversationWriteAccess: (any ConversationWriteAccessResolving)?
    private let conversationRoomUseCases: ConversationRoomUseCasesProtocol
    @Published var typingUsers: [TypingUser] = []

    // MARK: - Realtime Heartbeat (subscription monitoring)

    /// Deliberately not `@Published`: the monitor beats once a second, and routing
    /// that through this view model re-rendered the whole message list on every
    /// beat. The header indicator observes the monitor directly instead.
    let heartbeatMonitor = ChatRoomHeartbeatMonitor()
    public var currentReceiverUser: UserRoom?
    private let voiceRecordingViewModel: VoiceRecordingViewModel
    private var messagesUseCases : MessagesUseCasesProtocol
    private(set) var conversationId: String = ""

    /// Translation service — injected at construction, used by BubbleCheckpointView and BubbleView.
    let translationService: (any TranslationServiceProtocol)?
    @Published private(set) var translationLocaleToken: Int = 0

    @Published var chatAppearance: ChatAppearancePreference = .system
    private let appearanceStore = ChatAppearanceStore.shared
    private var discussionsUseCases : DiscussionUseCasesProtocol
    /// Token for the background observer that flushes the composer draft.
    private var draftBackgroundObserver: (any NSObjectProtocol)?
    /// Whether the stored draft has been read back yet for this room.
    ///
    /// Until it has, an empty composer means "not filled in yet", not "the user
    /// cleared it" — and writing that emptiness back deletes the draft we are in
    /// the middle of restoring.
    private var draftRestored = false
    /// The pending debounced draft write; cancelled by the next keystroke.
    private var draftWriteTask: Task<Void, Never>?
    /// How long typing has to pause before the draft is written.
    private static let draftWriteDebounce: UInt64 = 400_000_000  // 0.4s
    private let e2eeUseCases: E2EEUseCasesProtocol?
    private let pendingE2EEQueue: any PendingE2EEQueueProtocol
    private lazy var e2eeCoordinator: ChatRoomE2EECoordinator? = {
        guard let e2eeUseCases = e2eeUseCases else { return nil }
        return ChatRoomE2EECoordinator(
            e2eeUseCases: e2eeUseCases,
            pendingQueue: pendingE2EEQueue
        )
    }()
    private var contactsUseCases: ContactsUseCasesProtocol
    private var chatActionsUseCase: ChatActionsUseCaseProtocol
    
    // Navigation coordinator for proper navigation
    private weak var navigationCoordinator: ChatsTabCoordinator?
    
    // Block status
    @Published var isContactBlocked: Bool = false
    
    // Chat actions
    @Published var chatActions: [ChatActionItem] = []
    
    @Published var isGroup : Bool = false
    @Published var isGroupReadOnly: Bool = false
    /// Set for a broadcast channel or a community's announcements group the
    /// user may not post in. Nil everywhere else — including when it could not
    /// be resolved, so a plain chat is never locked by a failed lookup.
    @Published private(set) var writeRestriction: ConversationWriteRestriction?
    @Published var groupChat: GroupChat? {
        didSet { rebuildGroupMemberAvatarIndex() }
    }

    /// Where each timeline row sits in a run of consecutive messages from one
    /// sender. Empty for direct chats. See `GroupSenderRunResolver`.
    @Published private(set) var senderRunPositions: [String: SenderRunPosition] = [:]

    /// senderId → roster entry, rebuilt whenever the group changes.
    ///
    /// Messages do not carry the sender's avatar — the field is dropped at
    /// persistence — so the face on a group bubble is resolved from the roster
    /// already loaded for this room. Held as a dictionary because the timeline
    /// asks once per visible row and the roster can run to hundreds of members.
    private var groupMembersById: [String: GroupMember] = [:]
    /// Once true, the WhatsApp-style group intro never shows again for this conversation.
    @Published private(set) var hasGroupIntroBeenDismissed = false
    
    private let groupUseCases: GroupUseCasesProtocol?
    private let groupPermissionsUseCases: GroupPermissionsUseCasesProtocol?
    
    // Public accessor for groupUseCases
    public var groupUseCasesForForwarding: GroupUseCasesProtocol? { groupUseCases }

    /// Whether new members must be approved before joining (permissions table + legacy settings).
    @Published private(set) var isJoinApprovalRequired = false
    
    /// True when the thread currently has at least one real user message.
    var hasUserGeneratedMessages: Bool {
        ChatRoomGroupIntroCoordinator.hasUserGeneratedMessages(in: messages)
    }

    /// WhatsApp-style centered group card — only before the first user message ever.
    var shouldShowGroupIntroHeader: Bool {
        ChatRoomGroupIntroCoordinator.shouldShowIntro(
            isGroup: isGroup,
            hasBeenDismissed: hasGroupIntroBeenDismissed
        )
    }

    private func loadGroupIntroDismissedState() {
        hasGroupIntroBeenDismissed = ChatRoomGroupIntroCoordinator.loadDismissedState(
            isGroup: isGroup,
            conversationId: conversationId
        )
    }

    private func persistGroupIntroDismissalIfNeeded(from candidateMessages: [MessageDataItem]? = nil) {
        let source = candidateMessages ?? messages
        if ChatRoomGroupIntroCoordinator.shouldAutoDismiss(
            isGroup: isGroup,
            hasBeenDismissed: hasGroupIntroBeenDismissed,
            messages: source
        ) {
            persistGroupIntroDismissalPermanently()
        }
    }

    private func persistGroupIntroDismissalPermanently() {
        guard isGroup, !hasGroupIntroBeenDismissed else { return }
        hasGroupIntroBeenDismissed = true
        ChatRoomGroupIntroCoordinator.markDismissed(conversationId: conversationId)
    }
    
    var groupIntroName: String {
        groupChat?.name ?? channel.name ?? "Group"
    }
    
    var groupIntroDescription: String? {
        groupChat?.description
    }
    
    var groupIntroMemberCount: Int {
        max(groupChat?.memberCount ?? channel.membersCount, 1)
    }
    
    var groupIntroAvatarUrl: String? {
        groupChat?.avatarUrl ?? channel.coverImageUrl
    }
    
    var isGroupAdmin: Bool {
        guard let group = groupChat else { return false }
        return group.isCurrentUserAdmin(currentUserId: CurrentSessionInfo.shared.currentUid)
    }

    /// Whether this device's user created the group.
    ///
    /// An unresolved creator is stored as the empty string, and `currentUid` is
    /// empty before the session is injected — so the two are only compared once
    /// both are known, otherwise the intro card greets every member as the creator.
    var isGroupCreatedByCurrentUser: Bool {
        let currentUserId = CurrentSessionInfo.shared.currentUid
        guard let createdBy = groupChat?.createdBy,
              !createdBy.isEmpty,
              !currentUserId.isEmpty
        else { return false }
        return createdBy == currentUserId
    }
    
    var canAddMembers: Bool {
        guard isGroup, !isGroupReadOnly, let group = groupChat else { return false }
        if isGroupAdmin { return true }
        return !group.settings.onlyAdminsCanAddMembers
    }
    
    var canShowInviteLink: Bool {
        isGroup && !isGroupReadOnly
    }
    
    var groupInviteLink: String {
        return groupChat?.settings.inviteLink ?? ""
    }
    
    var hasInviteLink: Bool {
        guard let inviteLink = groupChat?.settings.inviteLink else { return false }
        return !inviteLink.isEmpty
    }
    
    var shouldShowGenerateInviteLink: Bool {
        isGroup && !isGroupReadOnly && !hasInviteLink
    }
    
    var shouldShowInviteLinkOptions: Bool {
        isGroup && !isGroupReadOnly && hasInviteLink
    }
    
    var existingMemberPhones: Set<String> {
        Set(groupChat?.members.map(\.phone) ?? [])
    }

    init(_
         user: UserRoom,
//         coordinator: ChatRoomCoordinator,
//         messages:[MessageDataItem],
         isGroup:Bool,
         conversationId: String,
         messagesUseCase: MessagesUseCasesProtocol,
         discussionsUseCase: DiscussionUseCasesProtocol,
         e2eeUseCases: E2EEUseCasesProtocol? = nil,
         pendingE2EEQueue: any PendingE2EEQueueProtocol,
         voiceRecordingViewModel: VoiceRecordingViewModel,
         contactsUseCases: ContactsUseCasesProtocol,
         chatActionsUseCase: ChatActionsUseCaseProtocol,
         groupUseCases: GroupUseCasesProtocol? = nil,
         groupPermissionsUseCases: GroupPermissionsUseCasesProtocol? = nil,
         navigationCoordinator: ChatsTabCoordinator? = nil,
         translationService: (any TranslationServiceProtocol)? = nil,
         messagesStore: ChatRoomMessagesStore,
         conversationRoomUseCases: ConversationRoomUseCasesProtocol,
         conversationWriteAccess: (any ConversationWriteAccessResolving)? = nil,
         financeSurface: ChatFinanceSurface? = nil
     ) {
        self.financeSurface = financeSurface
        // Le numéro du pair est une **saisie** à faire résoudre par le backend,
        // pas une identité financière. Il n'est stocké que pour être envoyé à
        // `RecipientResolving`, jamais pour désigner un portefeuille.
        self.peerPhoneNumber = user.phone
        // Le nom tel qu'il apparaît dans le fil. Transmis au résolveur comme
        // **indication** — voir `RecipientResolving.resolve(_:knownAs:)` — et
        // jamais affiché à la place du titulaire rendu par le backend.
        self.peerName = user.name
        // Partie d'une demande d'argent (§4 : userIds Chat) — un repli, jamais
        // une résolution : voir `MoneyRequestDraft.recipientChatUserID`.
        self.peerChatUserID = user.userId.isEmpty ? nil : user.userId
        self.messagesStore = messagesStore
        self.conversationRoomUseCases = conversationRoomUseCases
        self.translationService = translationService
        self.isGroup = isGroup
        self.groupUseCases = groupUseCases
        self.groupPermissionsUseCases = groupPermissionsUseCases
        self.discussionsUseCases = discussionsUseCase
        self.messagesUseCases = messagesUseCase
        self.conversationId = conversationId
        self.e2eeUseCases = e2eeUseCases
        self.pendingE2EEQueue = pendingE2EEQueue
        self.voiceRecordingViewModel = voiceRecordingViewModel
        self.contactsUseCases = contactsUseCases
        self.chatActionsUseCase = chatActionsUseCase
        self.navigationCoordinator = navigationCoordinator
        self.isContactBlocked = user.isBlocked
        self.chatAppearance = appearanceStore.defaultAppearance
        self.conversationWriteAccess = conversationWriteAccess
        debugLog("this is a conversation id  \(conversationId)")
        // Après la dernière assignation : Swift interdit tout appel de méthode
        // tant qu'une propriété stockée reste non initialisée.
        loadGroupIntroDismissedState()
        if isGroup {
            reloadGroupChat()
            refreshGroupMembershipStatus()
            resolveWriteRestriction()
        }
        bindMessagesStore()
        messagesStore.setDecryptHandler { [weak self] batch in
            guard let self, let coordinator = self.e2eeCoordinator else { return batch }
            return await coordinator.decryptBatch(batch, conversationId: self.conversationId)
        }
//        self.getMessages(conversationId: conversationId)
//        self.messages =  messages.sorted(by: { $0.createdAt < $1.createdAt })
//        self.coordinator = coordinator
        self.updateChannel(user)
        self.currentReceiverUser = user
//        self.rebuildGroupedMessages()
        wireNotificationObservers()
//        Task { @MainActor in
//            self.observeConnectivityForPendingMessages()
//        }
        scrollToBottom(isAnimated:  false)
        if isPreviewMode {
//            messages = MessageItem.stubMessages
        }
    }
    
    func reloadGroupChat() {
        Task { @MainActor in
            groupChat = await ChatRoomGroupMembershipCoordinator.fetchGroup(
                isGroup: isGroup,
                conversationId: conversationId,
                groupUseCases: groupUseCases
            )
        }
    }

    /// Resolves whether this room is one the user may write in.
    ///
    /// Only asked for group-shaped rooms: a broadcast channel and an
    /// announcements group both arrive here as `.group`, and a direct chat can
    /// never be restricted this way.
    func resolveWriteRestriction() {
        guard let conversationWriteAccess else { return }
        let conversationId = self.conversationId

        Task { @MainActor [weak self] in
            self?.writeRestriction = await conversationWriteAccess.restriction(
                forConversationId: conversationId
            )
        }
    }

    func refreshGroupMembershipStatus() {
        Task { @MainActor in
            let result = await ChatRoomGroupMembershipCoordinator.refresh(
                isGroup: isGroup,
                conversationId: conversationId,
                shouldShowGroupIntroHeader: shouldShowGroupIntroHeader,
                groupUseCases: groupUseCases,
                permissionsUseCases: groupPermissionsUseCases
            )
            groupChat = result.groupChat
            isGroupReadOnly = result.isGroupReadOnly
            isJoinApprovalRequired = result.isJoinApprovalRequired
            if result.shouldRebuildTimeline {
                rebuildGroupedMessages()
            }
        }
    }
    
    @discardableResult
    func addMembers(_ contacts: [UserContactProps]) async -> Bool {
        guard let groupUseCases, let group = groupChat else { return false }

        let newMembers = ChatRoomGroupMembersCoordinator.newMembers(
            from: contacts,
            existing: group.members
        )
        guard !newMembers.isEmpty else { return false }

        do {
            try await ChatRoomGroupMembersCoordinator.addMembers(
                newMembers,
                to: group,
                using: groupUseCases
            )
            reloadGroupChat()
            refreshGroupMembershipStatus()
            rebuildGroupedMessages()
            return true
        } catch {
            showErrorNotification(String(format: ChatErrorStrings.addMembersFailed, error.localizedDescription))
            return false
        }
    }
    
    func createOrRegenerateInviteLink() {
        guard let groupUseCases else { 
            debugLog("❌ No groupUseCases available")
            return 
        }
        
//        let hasExistingLink = hasInviteLink
//        let actionText = hasExistingLink ? "Regenerating" : "Generating"
//        let successText = hasExistingLink ? "regenerated" : "generated"
        
        
        Task { @MainActor in
           
            isLoadingInviteLink = true
            inviteLinkLoadingMessage = "Generating invite link..."
           
            
            do {
                let inviteData: InviteDataDTO
                 
                    inviteData = try await groupUseCases.regenerateInviteLink.execute(groupId: conversationId)
            
                
                // Update the groupChat directly
                if var updatedGroup = groupChat {
                    updatedGroup.settings.inviteLink = inviteData.inviteLink
                    updatedGroup.settings.isInviteLinkActive = true
                    updatedGroup.settings.inviteCode = inviteData.inviteCode
                    updatedGroup.settings.inviteExpiresAt = inviteData.expiresAt
                    updatedGroup.settings.inviteRemainingUses = inviteData.remainingUses
                    
                    // This should trigger UI updates since groupChat is @Published
                    groupChat = updatedGroup
                
                } else {
                    debugLog("❌ No groupChat to update")
                }
                self.isLoadingInviteLink = false
                inviteLinkLoadingMessage = ""
                // Show success message
                showSuccess("Invite link reset successfully")
                
            } catch {
                debugLog("❌ Error in createOrRegenerateInviteLink: \(error)")
                self.isLoadingInviteLink = false
                inviteLinkLoadingMessage = ""
                showError(String(format: ChatErrorStrings.resetInviteLinkFailed, error.localizedDescription))
            }
        }
    }
    
    // Convenience methods for clearer intent
    func generateNewInviteLink() {
        debugLog("🔗 generateNewInviteLink() called")
        createOrRegenerateInviteLink()
    }
    
    func regenerateInviteLink() {
       
        createOrRegenerateInviteLink()
    }
    
    func getChannel() -> ChannelItem {
        return self.channel
    }

    
    private func bindMessagesStore() {
        messagesStore.$messages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newMessages in
                guard let self else { return }
                self.republishReadReceiptsForEditedIncomingMessages(newMessages)
                self.messages = newMessages
                self.persistGroupIntroDismissalIfNeeded(from: newMessages)
                // Mirrored before the rebuild, so the count the list reads is
                // already current when the resulting `groupedMessages` change
                // reaches it. Only ever moves forward.
                self.prependGeneration = self.messagesStore.prependGeneration
                self.rebuildGroupedMessages()
                if self.isChatRoomActive {
                    Task { await self.markVisibleMessagesAsRead() }
                }
            }
            .store(in: &subscriptions)

        messagesStore.$allMediaMessages
            .receive(on: DispatchQueue.main)
            .assign(to: \.allMediasMessages, on: self)
            .store(in: &subscriptions)

        messagesStore.$typingUsers
            .receive(on: DispatchQueue.main)
            .assign(to: \.typingUsers, on: self)
            .store(in: &subscriptions)
    }

    func onAppear() {
        isChatRoomActive = true
        ActiveChatSessionStore.shared.setActive(conversationId: conversationId)
        startRealtimeHeartbeat()
        observeBackgroundingForDraft()
        restoreDraft()
        Task {
            await conversationRoomUseCases.session.start(
                conversationId: conversationId,
                store: messagesStore
            )
            hasMore = messagesStore.hasMore
            oldestLoadedDate = messagesStore.oldestLoadedDate
            await syncJoinRequestsIfNeeded()
            await loadChatActions()
            await markVisibleMessagesAsRead()
            await revalidateFinancialCards()
        }
    }

    /// Bloc 1 §8 : à l'ouverture, les cartes encore en mouvement ou non
    /// prouvées sont relues au serveur. Le magasin applique la réponse sous son
    /// garde de version et la projection redessine la bulle — rien n'est écrit
    /// ici.
    private func revalidateFinancialCards() async {
        guard let reader = financeSurface?.objectReader else { return }
        for reference in FinancialCardRevalidation.references(in: messagesStore.messages) {
            guard isChatRoomActive else { return }
            _ = await reader.refresh(reference)
        }
    }

    func onDisappear() {
        // Order matters. `isChatRoomActive` goes down first so that nothing below
        // can schedule another draft write: `cancelMessageEdit()` empties the
        // composer, and the field echoes that back through `onTextChanged`, which
        // would otherwise queue a write of the blank and wipe the draft a few
        // hundred milliseconds after the room was already gone.
        isChatRoomActive = false
        // Then the final write, while the text is still there to read.
        persistDraft()
        cancelMessageEdit()
        ActiveChatSessionStore.shared.setActive(conversationId: nil)
        stopRealtimeHeartbeat()
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
        Task {
            await conversationRoomUseCases.session.stop(store: messagesStore)
        }
    }

    // MARK: - Composer draft

    /// Writes whatever is in the composer onto the conversation so the chat list
    /// can show it in place of the last message.
    ///
    /// Skipped while a message is being edited — that text belongs to the message,
    /// not to a new one, and `cancelMessageEdit()` discards it anyway.
    ///
    /// A brand-new direct chat has no conversation row yet (`conversationId` is
    /// empty until the first message creates one), so there is nothing to attach
    /// a draft to; the use case drops those.
    private func persistDraft() {
        draftWriteTask?.cancel()
        guard messageBeingEdited == nil else { return }
        let text = composer.text
        // Clearing is only meaningful once the restore has landed. Backing out
        // faster than the read completes must leave the stored draft alone rather
        // than persist the blank the composer still happens to be showing.
        guard draftRestored || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        let useCases = discussionsUseCases
        let id = conversationId
        Task {
            try? await useCases.draft.save(conversationId: id, text: text)
        }
    }

    /// Puts a stored draft back in the composer when the room opens.
    ///
    /// Only when the composer is empty: `onAppear` fires again on every return to
    /// the foreground, and overwriting live text with an older draft would delete
    /// what the user is in the middle of typing.
    private func restoreDraft() {
        guard !draftRestored, composer.text.isEmpty, messageBeingEdited == nil else { return }
        let useCases = discussionsUseCases
        let id = conversationId
        Task { @MainActor [weak self] in
            let stored = try? await useCases.draft.fetch(conversationId: id)
            // Set before the guards below, and set even when the read failed or
            // found nothing: the point is that the question has been answered, so
            // writes may resume either way.
            self?.draftRestored = true
            guard let draft = stored ?? nil, !draft.isEmpty,
                  let self,
                  self.composer.text.isEmpty,
                  self.messageBeingEdited == nil
            else { return }
            self.composer.text = draft
        }
    }

    /// Writes the draft shortly after the user stops typing.
    ///
    /// Debounced rather than written per keystroke: the composer changes on every
    /// character, and a database write plus a list refresh at that rate would cost
    /// far more than the draft is worth. Each keystroke cancels the pending write
    /// and starts a new one, so a burst of typing settles into a single write.
    ///
    /// `onDisappear` still writes unconditionally — backing out within the delay
    /// must not lose the last few characters.
    private func scheduleDraftWrite() {
        // Only while the room is on screen. The composer reports every change back
        // through `onTextChanged`, including the ones the view model makes itself
        // on the way out, and a write scheduled from one of those echoes lands
        // after the final write and undoes it.
        guard isChatRoomActive, draftRestored else { return }
        draftWriteTask?.cancel()
        draftWriteTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.draftWriteDebounce)
            guard !Task.isCancelled else { return }
            self?.persistDraft()
        }
    }

    /// Leaving via the home screen or the app switcher never calls `onDisappear`,
    /// so without this a draft is lost whenever the app is killed from the
    /// background rather than backed out of.
    private func observeBackgroundingForDraft() {
        guard draftBackgroundObserver == nil else { return }
        draftBackgroundObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.persistDraft() }
        }
    }

    // MARK: - Realtime Heartbeat

    func startRealtimeHeartbeat() {
        heartbeatMonitor.start(useCases: conversationRoomUseCases)
    }

    func stopRealtimeHeartbeat() {
        heartbeatMonitor.stop()
    }

    /// Builds the view model for the realtime topics monitor screen.
    func makeRealtimeMonitorViewModel() -> RealtimeMonitorViewModel {
        RealtimeMonitorViewModel(
            useCases: conversationRoomUseCases,
            expectedTopics: ChatRealtimeRegistration.topicRegistrations.map(\.topicPattern.path),
            inboxTopicPath: ChatMQTTTopics.userInbox(
                userId: CurrentSessionInfo.shared.currentUid
            ).path,
            syncHealthMonitor: .shared
        )
    }

    func onTextChanged(_ text: String) {
        textMessage = text
        detectLink(in: text)
        scheduleDraftWrite()
        Task {
            await conversationRoomUseCases.sendTyping.execute(
                conversationId: conversationId,
                isTyping: !text.isEmpty,
                isRecording: false
            )
        }
    }
    
    // MARK: func to initialize first page
    
    func loadInitialMessages(conversationId: String) {
        onAppear()
    }
    
    // MARK: - Chat Actions

    private func rebuildGroupedMessages() {
        groupedMessages = timelineBuilder.build(
            ChatRoomTimelineInput(
                messages: messages,
                chatActions: chatActions,
                shouldShowGroupIntroHeader: shouldShowGroupIntroHeader,
                isGroupAdmin: isGroupAdmin,
                groupIntroContent: shouldShowGroupIntroHeader ? makeGroupIntroContent() : nil
            )
        )
        photoCodeToGroupId = timelineBuilder.photoCodeToGroupId
        senderRunPositions = GroupSenderRunResolver.resolve(
            sections: groupedMessages,
            isGroup: isGroup
        )
    }

    /// Avatar for a group message's sender, or nil to fall back to initials.
    ///
    /// Nil is expected and not an error: a member who has left the group is off
    /// the roster while their messages stay in the thread.
    func senderAvatarURL(forSenderId senderId: String) -> String? {
        groupMembersById[senderId]?.avatar.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Avatar of whoever sent a message, for the live location marker.
    ///
    /// Read from the profile that is current now, never from what the message
    /// was stamped with: a share is about where someone *is*, and the face on
    /// the map going stale while the pin moves would be its own small lie.
    ///
    /// Nil falls back to initials — a peer with no picture, or a group member
    /// who has since left and is off the roster.
    func senderAvatarURLForMarker(_ message: MessageDataItem) -> String? {
        func nonEmpty(_ value: String?) -> String? {
            guard let value, !value.isEmpty else { return nil }
            return value
        }

        if message.direction == .sent {
            return nonEmpty(CurrentSessionInfo.shared.avatar)
        }
        if isGroup {
            return senderAvatarURL(forSenderId: message.senderId)
        }
        return nonEmpty(currentReceiverUser?.avatar)
    }

    /// Name to print above a run of group messages.
    ///
    /// Prefers the name the message was stamped with, so an old message keeps
    /// reading as it did when it was sent. The roster covers the case where the
    /// sender arrived without one, which some inbound payloads do.
    func senderDisplayName(forSenderId senderId: String, stampedName: String) -> String {
        let stamped = stampedName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stamped.isEmpty { return stamped }
        return groupMembersById[senderId]?.name ?? ""
    }

    private func rebuildGroupMemberAvatarIndex() {
        guard let members = groupChat?.members else {
            groupMembersById = [:]
            return
        }
        groupMembersById = Dictionary(
            members.map { ($0.userId, $0) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    func syncJoinRequestsIfNeeded() async {
        await ChatRoomJoinRequestCoordinator.syncIfNeeded(
            isGroup: isGroup,
            isGroupAdmin: isGroupAdmin,
            isJoinApprovalRequired: isJoinApprovalRequired,
            conversationId: conversationId,
            groupUseCases: groupUseCases
        )
    }

    /// Syncs pending join requests and refreshes timeline actions. Returns pending count.
    @discardableResult
    func refreshJoinRequestsIfNeeded() async -> Int {
        await ChatRoomJoinRequestCoordinator.refreshIfNeeded(
            isGroup: isGroup,
            isGroupAdmin: isGroupAdmin,
            isJoinApprovalRequired: isJoinApprovalRequired,
            conversationId: conversationId,
            groupUseCases: groupUseCases,
            reloadChatActions: { await self.loadChatActions() }
        )
    }

    func loadChatActions() async {
        do {
            let actions = try await ChatRoomChatActionsCoordinator.fetchActions(
                conversationId: conversationId,
                using: chatActionsUseCase
            )
            await MainActor.run {
                self.chatActions = actions
                self.rebuildGroupedMessages()
            }
        } catch {
            #if DEBUG
            print("Error loading chat actions: \(error)")
            #endif
        }
    }

    func recordChatAction(_ actionType: ChatActionType, targetId: String? = nil, metadata: [String: String]? = nil) async {
        do {
            let action = try await ChatRoomChatActionsCoordinator.record(
                conversationId: conversationId,
                actionType: actionType,
                targetId: targetId,
                metadata: metadata,
                using: chatActionsUseCase
            )
            await MainActor.run {
                self.chatActions.append(action)
                self.rebuildGroupedMessages()
            }
        } catch {
            #if DEBUG
            print("Error recording chat action: \(error)")
            #endif
        }
    }

    func reloadMessagesFromStore() {
        loadInitialMessages(conversationId: conversationId)
    }

    /// Deletes all messages in this conversation locally and refreshes the thread.
    func clearAllMessagesLocally() async throws {
        if isGroup {
            persistGroupIntroDismissalPermanently()
        }
        try await discussionsUseCases.deleteAllDiscussionMessages.execute(converationId: conversationId)
        reloadMessagesFromStore()
        
        // Record chat action for clearing messages
        Task {
            await recordChatAction(.messagesCleared)
        }
//        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }
    
    func blockContact() {
        guard let contact = currentReceiverUser else {
            showError(ChatErrorStrings.blockMissingContact)
            return
        }

        Task { @MainActor in
            await ChatRoomBlockContactCoordinator.toggle(
                contact: contact,
                isCurrentlyBlocked: isContactBlocked,
                handlers: ChatRoomBlockContactCoordinator.Handlers(
                    toggleBlock: { [contactsUseCases] contactId, blocked in
                        try await contactsUseCases.toggleBlockContact.execute(contactId: contactId, blocked: blocked)
                    },
                    recordChatAction: { [weak self] actionType, metadata in
                        await self?.recordChatAction(actionType, metadata: metadata)
                    },
                    showSuccess: { [weak self] message in
                        self?.showSuccess(message)
                    },
                    showError: { [weak self] message in
                        self?.showError(message)
                    },
                    onBlockedStateChanged: { [weak self] isBlocked in
                        guard let self else { return }
                        self.isContactBlocked = isBlocked
                        if var updatedUser = self.currentReceiverUser {
                            updatedUser.isBlocked = isBlocked
                            self.currentReceiverUser = updatedUser
                            self.updateChannel(updatedUser)
                        }
                    }
                )
            )
        }
    }
    
    private func showSuccess(_ message: String) {
        errorNotificationMessage = message
        showErrorNotification = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.showErrorNotification = false
        }
    }
    
    private func showError(_ message: String) {
        errorNotificationMessage = message
        showErrorNotification = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showErrorNotification = false
        }
    }
    
    func setChatAppearance(_ pref: ChatAppearancePreference) {
        appearanceStore.apply(pref)
        syncChatAppearanceFromStore()
    }

    func syncChatAppearanceFromStore() {
        chatAppearance = appearanceStore.defaultAppearance
    }

    var preferredColorScheme: ColorScheme? {
        chatAppearance.preferredColorScheme
    }

    func localizedChatAppearanceName() -> String {
        appearanceStore.defaultAppearance.displayName(translationService: translationService)
    }

    func messagesMatchingSearch(_ query: String) -> [MessageDataItem] {
        ChatRoomMessageSearchCoordinator.matching(query, in: messages)
    }
    
    // MARK: - Read Receipts

    private var publishedReadReceiptCodes = Set<String>()
    private var isChatRoomActive = false
    private var lastKnownMessageTexts: [String: String] = [:]

    func sendReadReceipt(for message: MessageDataItem) {
        Task {
            await publishReadReceipts(for: [message])
        }
    }

    func markVisibleMessagesAsRead() async {
        await publishReadReceipts(for: messages)
    }

    private func publishReadReceipts(for candidates: [MessageDataItem]) async {
        let unread = ChatRoomReadReceiptCoordinator.unreadIncomingMessages(in: candidates)
            .filter { !publishedReadReceiptCodes.contains($0.codeMessage) }
        guard !unread.isEmpty else { return }

        for message in unread {
            publishedReadReceiptCodes.insert(message.codeMessage)
        }

        await conversationRoomUseCases.markMessagesAsRead.execute(
            messages: unread,
            conversationId: conversationId
        )
    }

    /// Indexes message text by code for edit detection.
    ///
    /// Never traps: `Dictionary(uniqueKeysWithValues:)` crashes the app on a
    /// repeated key, and this is bookkeeping over data the view model does not
    /// own — duplicates or blank codes are a reason to skip an edit check, not
    /// to take the process down. The later message wins.
    private static func textsByCode(_ messages: [MessageDataItem]) -> [String: String] {
        Dictionary(
            messages
                .filter { !$0.codeMessage.isEmpty }
                .map { ($0.codeMessage, $0.message.text) },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private func republishReadReceiptsForEditedIncomingMessages(_ messages: [MessageDataItem]) {
        guard isChatRoomActive else {
            lastKnownMessageTexts = Self.textsByCode(messages)
            return
        }

        var republished: [MessageDataItem] = []
        for message in messages where !message.isSentByMe && !message.codeMessage.isEmpty {
            let previousText = lastKnownMessageTexts[message.codeMessage]
            if let previousText,
               previousText != message.message.text,
               message.isEdited {
                republished.append(message)
            }
        }

        lastKnownMessageTexts = Self.textsByCode(messages)

        guard !republished.isEmpty else { return }

        for message in republished {
            publishedReadReceiptCodes.remove(message.codeMessage)
        }

        Task {
            for message in republished {
                await conversationRoomUseCases.markMessagesAsRead.republishRead(
                    message: message,
                    conversationId: conversationId
                )
            }
        }
    }

    func loadMoreIfNeeded() {
        guard !isLoadingMore, messagesStore.hasMore else { return }
        guard messagesStore.oldestLoadedDate != nil else { return }

        isLoadingMore = true

        Task {
            await conversationRoomUseCases.session.loadMore(
                conversationId: conversationId,
                store: messagesStore
            )
            hasMore = messagesStore.hasMore
            oldestLoadedDate = messagesStore.oldestLoadedDate
            isLoadingMore = false
        }
    }
    // MARK: scroll detection
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView.contentOffset.y <= 0 {
            loadMoreIfNeeded()
        }
    }
    
    func groupedMediaCount(groupId: String) -> Int {
        cachedMediaCount(for: groupId)
    }

    /// Fast, cached media count — uses in-memory data from buildRows instead of a DB query.
    /// Safe to call from view body / onAppear without blocking the main thread.
    func cachedMediaCount(for groupId: String) -> Int {
        ChatRoomMediaGroupCounter.count(groupId: groupId, in: groupedMessages)
    }
    
    func deleteAnyMessages(message: MessageDataItem, forEveryone: Bool = false) async throws {
        // Unsent / failed never reached the server — local hide only, never for-everyone.
        // Received messages can only be deleted for me.
        let isUnsent = message.status == .PENDING || message.status == .FAILED
        let effectiveForEveryone = forEveryone && message.isSentByMe && !isUnsent

        try await ChatRoomMessageDeletionCoordinator.delete(
            message,
            forEveryone: effectiveForEveryone,
            messagesUseCases: messagesUseCases
        )

        messagesStore.applyLocalDelete(
            codeMessage: message.codeMessage,
            forEveryone: effectiveForEveryone
        )

        ChatRoomMessageDeletionCoordinator.notifyDiscussionsShouldRefresh()
    }

    
    func deleteMessages(onlyMe: Bool, message: MessageDataItem? = nil) {
        let targets: [MessageDataItem]
        if let message {
            targets = [message]
        } else if let selected = selectedMessages {
            targets = selected
        } else {
            return
        }

        let forEveryone = !onlyMe
        // Exit selection mode immediately so deleted messages can't stay selected.
        exitSelectionMode()

        Task { @MainActor in
            if let error = await ChatRoomMessageDeletionCoordinator.deleteBatch(
                targets,
                onlyMe: onlyMe,
                deleteOne: { [weak self] msg in
                    guard let self else { return }
                    // Per-message: received → for me only; own → honor selection.
                    let everyone = forEveryone && msg.isSentByMe
                    try await self.deleteAnyMessages(message: msg, forEveryone: everyone)
                },
                notifyRemote: { [weak self] msg in
                    let everyone = forEveryone && msg.isSentByMe
                    await self?.notifyMessageDeleted(msg, forEveryone: everyone)
                }
            ) {
                showErrorNotification(error)
            }
        }
    }
    
    func notifyMessageDeleted(_ message: MessageDataItem, forEveryone: Bool) async {
        // Pending/failed were never accepted by the server — do not publish delete.
        // Received messages: publish only as delete-for-me.
        if message.status == .PENDING || message.status == .FAILED {
            return
        }
        let effectiveForEveryone = forEveryone && message.isSentByMe
        await conversationRoomUseCases.publishDeleteMessage.execute(
            codeMessage: message.codeMessage,
            conversationId: conversationId,
            forEveryone: effectiveForEveryone
        )
    }
    
    /// Fills in receiver identity that was unknown when this view model was built.
    ///
    /// View models are cached per conversation, so a room first opened knowing
    /// only a phone number keeps that hollow receiver for as long as the cache
    /// lives — and every message it sends keeps going out with an empty
    /// `receiverId`. A later open that knows more (a shared contact card, a
    /// directory hit that has since synced) tops it up.
    ///
    /// Only empty fields are filled: what is already there came from the
    /// conversation itself and outranks anything a caller passes in.
    func adoptReceiverDetails(_ candidate: UserRoom) {
        guard let current = currentReceiverUser else {
            currentReceiverUser = candidate
            return
        }

        func preferred(_ held: String?, _ offered: String?) -> String? {
            if let held, !held.isEmpty { return held }
            guard let offered, !offered.isEmpty else { return held }
            return offered
        }

        let merged = UserRoom(
            idContact: current.idContact.isEmpty ? candidate.idContact : current.idContact,
            userId: current.userId.isEmpty ? candidate.userId : current.userId,
            phone: preferred(current.phone, candidate.phone),
            name: preferred(current.name, candidate.name),
            avatar: preferred(current.avatar, candidate.avatar),
            description: current.description,
            isOnline: current.isOnline,
            onlineStatus: current.onlineStatus,
            isBlocked: current.isBlocked
        )

        // `UserRoom.==` ignores the avatar, so compare the fields this fills.
        let unchanged = merged.idContact == current.idContact
            && merged.userId == current.userId
            && merged.phone == current.phone
            && merged.name == current.name
            && merged.avatar == current.avatar
        guard !unchanged else { return }

        currentReceiverUser = merged
    }

    func updateChannel(_ user: UserRoom) {
//        self.channel = ChannelItem(
//            id: user.idContact,
//            name: user.name ?? "Unknown",
//            lastMessage: "Hey there!",
//            creationDate: Date(),
//            lastMessageTimestamp: Date(),
//            membersCount: 2,
//            adminUids: ["user_1"],
//            memberUids: ["user_1", "user_2"],
//            thumbnailUrl: "https://example.com/group.jpg",
//            createdBy: "user_1",
//            lastMessageType: .text
//        )
    }
    
    // MARK: - Media viewer

    /// Opens the media viewer at the tapped message. Video is a page in the
    /// pager now, so there is no separate video branch.
    func onTapMedia(_ message: MessageDataItem) {
        mediaViewerRequest = ChatRoomMediaViewerCoordinator.makeRequest(
            tapped: message,
            in: allMediasMessages,
            thumbnailProvider: {
                ChatImageMemoryCache.shared.image(forKey: $0)
                    ?? DiskMediaManager.shared.loadImageFromDisk(fileName: $0, pathName: .CHAT)
            }
        )
    }

    func deleteMediaItem(_ item: MediaViewerItem, onlyMe: Bool) {
        guard let message = allMediasMessages.first(where: { $0.codeMessage == item.id }) else { return }
        deleteMessages(onlyMe: onlyMe, message: message)
    }

    func openDocumentPreview(for message: MessageDataItem) {
        guard let url = ChatRoomMediaViewerCoordinator.resolveDocumentURL(for: message) else { return }
        documentPreviewURL = url
        showDocumentPreview = true
    }

    func getCachedImage(key: String) -> UIImage? {
      
        return DiskMediaManager.shared.loadImageFromDisk(fileName: key, pathName: .CHAT)
    }

    func getCachedMedia(key: String) -> URL? {
        DiskMediaManager.shared.loadVideoFromDisk(fileName: key, pathName: .CHAT)
    }


    public func getMessageByFilename(_ filename: String) -> MessageDataItem? {
        return messages.first { $0.message.fileName == filename }
    }
    
    func updateMessages(_ messages: [MessageDataItem]) {
        Task {
            await messagesStore.replaceMessages(messages)
        }
    }

    func updateMessageNew(_ message: [MessageDataItem]) {
        Task {
            await messagesStore.mergeIncoming(message)
        }
    }
    private func makeGroupIntroContent() -> GroupChatIntroContent {
        ChatRoomGroupIntroCoordinator.makeContent(
            groupName: groupIntroName,
            description: groupIntroDescription,
            memberCount: groupIntroMemberCount,
            avatarUrl: groupIntroAvatarUrl,
            createdByCurrentUser: isGroupCreatedByCurrentUser,
            canAddMembers: canAddMembers,
            canShowInviteLink: canShowInviteLink
        )
    }

    var showPhotoPickerPreview: Bool {
        return !mediaAttachments.isEmpty || !photoPickerItems.isEmpty
    }
    
    var disableSendButton: Bool {
        return mediaAttachments.isEmpty && textMessage.isEmptyOrWhitespace
    }
    
    private var isPreviewMode: Bool {
        return ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    }
    
    
    
    // MARK: - Voice Recording
    
    /// Expose voice recording view model for UI binding
    public var voiceRecordingVM: VoiceRecordingViewModel {
        voiceRecordingViewModel
    }
    
    /// Start voice recording
    public func startVoiceRecording() async {
        await voiceRecordingViewModel.startRecording()
    }
    
    /// Stop voice recording and send the voice message.
    /// The recorder's view-once button, for the recording in progress.
    func setVoiceNoteViewOnce(_ isViewOnce: Bool) {
        voiceNoteIsViewOnce = isViewOnce
    }

    public func stopVoiceRecording() async {
        // Read before the first await: the recorder resets its button as soon as
        // the send has been asked for, and the next recording starts off.
        let viewOnce = voiceNoteIsViewOnce
        voiceNoteIsViewOnce = false
        let result = await voiceRecordingViewModel.stopRecording()
        await ChatRoomVoiceMessageFlow.stopAndSend(
            result: result,
            handlers: ChatRoomVoiceMessageFlow.SendHandlers(
                appendAttachment: { [weak self] attachment in
                    self?.mediaAttachments.append(attachment)
                },
                firstAudioAttachment: { [weak self] in
                    self?.mediaAttachments.first(where: {
                        if case .audio = $0.type { return true }
                        return false
                    })
                },
                sendMessage: { [weak self] content, type, groupId in
                    self?.sendMediaAndTextMessage(content, type: type, groupId: groupId, viewOnce: viewOnce)
                },
                showError: { [weak self] message in
                    self?.showErrorNotification(message)
                },
                clearAttachments: { [weak self] in
                    self?.mediaAttachments.removeAll()
                }
            )
        )
    }
    
    /// Cancel voice recording
    public func cancelVoiceRecording() async {
        voiceNoteIsViewOnce = false
        await voiceRecordingViewModel.cancelRecording()
    }
    
    /// Pause voice recording
    public func pauseVoiceRecording() async {
        await voiceRecordingViewModel.pauseRecording()
    }
    
    /// Resume voice recording
    public func resumeVoiceRecording() async {
        await voiceRecordingViewModel.resumeRecording()
    }
    
    /// Lock voice recording
    public func lockVoiceRecording() async {
        await voiceRecordingViewModel.lockRecording()
    }
    
    deinit {
        subscriptions.forEach { $0.cancel() }
        subscriptions.removeAll()
        if let draftBackgroundObserver {
            NotificationCenter.default.removeObserver(draftBackgroundObserver)
        }
        draftWriteTask?.cancel()
        currentReceiverUser = nil
    }
    
   
    /// Faisceau financier de cette conversation.
    ///
    /// `nil` quand le graphe est construit sans finance — le menu financier
    /// s'affiche alors indisponible plutôt que de disparaître, pour que
    /// l'absence soit visible et non silencieuse.
    let financeSurface: ChatFinanceSurface?

    /// Numéro du pair, tel que saisi dans le fil. Voir le commentaire d'init.
    let peerPhoneNumber: String?

    /// Nom du pair tel qu'affiché dans le fil. Voir le commentaire d'init.
    let peerName: String?

    /// Utilisateur Chat du pair. Voir le commentaire d'init.
    let peerChatUserID: String?

    /// Le pair d'une conversation directe seulement : dans un groupe, il n'y a
    /// pas « un » interlocuteur à qui demander.
    var financePeerChatUserID: String? { isGroup ? nil : peerChatUserID }

    /// Entrée financière que l'utilisateur vient d'ouvrir.
    /// L'entrée ouverte, **entière**.
    ///
    /// Sa seule nature ne suffit plus : une entrée marchand porte
    /// l'identifiant du marchand, que la conversation ne peut pas deviner.
    @Published var presentedFinanceEntry: FinanceCatalogEntry?
    @Published var showsFinanceHome = false

    /// Annonce l'opération dans ce fil. La publication elle-même vit dans
    /// ``PublishFinanceMessageUseCase`` — le même chemin sert aux Réglages ; le
    /// fil n'y ajoute que ce qu'il est seul à avoir : sa cible, et un affichage
    /// immédiat sans attendre l'observation de la base.
    ///
    /// Le paiement n'est jamais relancé ici, y compris après un échec.
    func publishFinanceReference(
        _ reference: FinancialReference,
        note: String? = nil,
        using publisher: any PublishFinanceMessageUseCaseProtocol
    ) async -> Bool {
        let target = FinanceMessageTarget(
            conversationId: conversationId,
            kind: isGroup ? .group : .direct,
            receiverUserId: currentReceiverUser?.userId ?? "",
            contact: DiscussionContactBuilder.contactChannel(
                from: currentReceiverUser, kind: isGroup ? .group : .direct)
        )
        do {
            try await publisher.execute(reference, note: note, to: target) { [weak self] saved in
                await self?.messagesStore.mergeIncoming(saved)
            }
            return true
        } catch {
            await AppLogger.shared.log(
                "Finance message publication failed ref=\(reference.id): \(error)",
                level: .error
            )
            return false
        }
    }

    func openFinanceHome() {
        ChatKeyboard.hide()
        showsFinanceHome = true
    }

    /// Saisie à faire résoudre pour une demande d'argent dans cette conversation.
    /// `nil` en groupe : le chapitre 17 multi-destinataires n'est pas écrit.
    var financeRecipientInput: RecipientInput? {
        guard !isGroup, let phone = peerPhoneNumber, !phone.isEmpty else { return nil }
        return .phoneNumber(phone)
    }

    /// Contexte de résolution du catalogue.
    ///
    /// `direct` et `group` sont connus localement — ce sont des faits de
    /// structure du fil, pas des affirmations financières. `merchant`,
    /// `institution` et `support` ne sont **jamais** déduits ici : les déduire
    /// donnerait à la conversation un pouvoir financier, et c'est au backend de
    /// les établir.
    var financeContext: ChatFinanceContext {
        ChatFinanceContext(
            conversationID: conversationId,
            conversationKind: isGroup ? .group : .direct,
            participantCount: isGroup ? (groupChat?.memberCount ?? 0) : 2
        )
    }

    /// L'utilisateur a choisi une entrée financière.
    ///
    /// La feuille d'actions se ferme **avant** que le parcours s'ouvre : deux
    /// feuilles empilées laissent la première capter les gestes de la seconde.
    func onSelectFinanceEntry(_ entry: FinanceCatalogEntry) {
        closeChatActionsSheet()
        presentedFinanceEntry = entry
    }


    /// La carte financière touchée, dont on veut voir les suites.
    @Published var presentedFinancialCard: FinancialCardPayload?

    func onTapFinancialCard(_ payload: FinancialCardPayload) {
        presentedFinancialCard = payload
    }

    func dismissFinancialCard() {
        presentedFinancialCard = nil
    }

    // MARK: - Répondre à une demande d'argent (§4)

    /// Demande à payer — ouvre `PayMoneyRequestView` : un devis, puis
    /// confirmation explicite. Jamais un débit depuis la bulle.
    @Published var requestToPay: MoneyRequestOverlay?
    /// Demande dont le refus attend confirmation.
    @Published var requestToDecline: MoneyRequestOverlay?
    /// Demande (envoyée) dont l'annulation attend confirmation.
    @Published var requestToCancel: MoneyRequestOverlay?
    /// Issue d'un refus ou d'une relance, dite dans le dialogue de l'app.
    @Published var requestNotice: String?
    /// Lien de paiement tout juste émis, montré dans sa feuille.
    @Published var issuedPaymentLink: MoneyRequestLink?

    /// Les gestes de la carte de demande. `nil` sans répondeur : la carte
    /// n'affiche alors aucun bouton.
    var financeRequestActions: FinanceRequestActions? {
        guard financeSurface?.requestResponder != nil else { return nil }
        return FinanceRequestActions(
            pay: { [weak self] in self?.requestToPay = $0 },
            decline: { [weak self] in self?.requestToDecline = $0 },
            remind: { [weak self] overlay in
                Task { await self?.remind(overlay) }
            },
            cancel: { [weak self] in self?.requestToCancel = $0 },
            issueLink: { [weak self] overlay in
                Task { await self?.issueLink(overlay) }
            }
        )
    }

    /// `overlay` est passé, pas relu : le dialogue remet `requestToDecline` à
    /// nil **avant** de jouer son action.
    func confirmDeclineRequest(_ overlay: MoneyRequestOverlay) async {
        guard let responder = financeSurface?.requestResponder else { return }
        requestToDecline = nil
        switch await responder.decline(overlay.reference, conversationID: conversationId) {
        case .success:
            // La carte change par la seule relecture serveur, qui repasse par le
            // magasin et réécrit la bulle — jamais par une écriture locale.
            _ = await financeSurface?.objectReader?.refresh(overlay.reference)
            NotificationCenter.default.post(name: .financeRequestDidChange, object: overlay.reference.id)
        case .failure(let error):
            requestNotice = FinanceStrings.errorMessage(error)
        }
    }

    /// `overlay` est passé, pas relu — voir `confirmDeclineRequest`.
    func confirmCancelRequest(_ overlay: MoneyRequestOverlay) async {
        guard let responder = financeSurface?.requestResponder else { return }
        requestToCancel = nil
        switch await responder.cancel(overlay.reference, conversationID: conversationId) {
        case .success(.cancelled):
            _ = await financeSurface?.objectReader?.refresh(overlay.reference)
            NotificationCenter.default.post(name: .financeRequestDidChange, object: overlay.reference.id)
        case .success(.requested):
            // Demandée, pas faite : la carte changera quand le serveur le dira.
            requestNotice = FinanceStrings.requestCancelRequested
            _ = await financeSurface?.objectReader?.refresh(overlay.reference)
        case .failure(let error):
            requestNotice = FinanceStrings.errorMessage(error)
        }
    }

    /// `POST /request-money/payment-link`. Le lien désigne la demande ; il ne paie rien.
    private func issueLink(_ overlay: MoneyRequestOverlay) async {
        guard let responder = financeSurface?.requestResponder else { return }
        switch await responder.issueLink(for: overlay.reference, conversationID: conversationId) {
        case .success(let link):
            issuedPaymentLink = link
            NotificationCenter.default.post(name: .financeRequestDidChange, object: overlay.reference.id)
        case .failure(let error):
            requestNotice = FinanceStrings.errorMessage(error)
        }
    }

    private func remind(_ overlay: MoneyRequestOverlay) async {
        guard let responder = financeSurface?.requestResponder,
              let party = overlay.pendingPartyUserIDs.first else { return }
        switch await responder.remind(overlay.reference, partyUserID: party) {
        case .success:            requestNotice = FinanceStrings.requestReminded
        case .failure(let error): requestNotice = FinanceStrings.errorMessage(error)
        }
    }

    func dismissFinanceEntry() {
        presentedFinanceEntry = nil
    }

    func onUserOpenChatActionsSheet() {
        debugLog("👀this was called for sheet action")
        ChatKeyboard.hide()
        self.showPhotoPicker.toggle()
    }

    /// Closes the attachment sheet, whatever state it is in.
    ///
    /// Every send path goes through here rather than through the toggle above:
    /// a sub-view that both reports its draft *and* asks to be dismissed would
    /// otherwise flip the sheet shut and straight back open, which is what made
    /// a sent poll leave the sheet standing.
    func closeChatActionsSheet() {
        ChatKeyboard.hide()
        showPhotoPicker = false
    }

    func onUserOpenCamera() {
        ChatKeyboard.hide()
        withAnimation(ChatMediaOpenAnimation.spring) {
            showCameraCapture = true
        }
    }

    func onUserCloseCamera() {
        withAnimation(ChatMediaOpenAnimation.spring) {
            showCameraCapture = false
        }
    }

    /// A long press on the composer's camera button.
    func onUserOpenVideoNote() {
        ChatKeyboard.hide()
        showVideoNoteRecorder = true
    }

    /// Sent the moment recording stops, so the sheet closes with it.
    func sendVideoNote(at url: URL) {
        showVideoNoteRecorder = false
        sendCapturedMedia(.videoNote(url), caption: nil)
    }

    func openGalleryMediaEditor(with media: GalleryMedia) {
        if showPhotoPicker {
            showPhotoPicker = false
        }
        let preview = PreviewMediaItem(source: .gallery(media))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self else { return }
            withAnimation(ChatMediaOpenAnimation.spring) {
                self.galleryEditorPreview = preview
            }
        }
    }

    func closeGalleryMediaEditor() {
        withAnimation(ChatMediaOpenAnimation.spring) {
            galleryEditorPreview = nil
        }
    }

    func sendEditedMedia(_ result: EditedMediaResult, caption: String?, viewOnce: Bool = false) {
        switch result {
        case .uneditedGallery(let media):
            onSendMedia(caption: caption, selectedMedia: [media], viewOnce: viewOnce)
        case .exportedImage(let image, let jpegData):
            sendCapturedMedia(.image(image, jpegData: jpegData), caption: caption, viewOnce: viewOnce)
        case .exportedVideo(let url):
            sendCapturedMedia(.video(url), caption: caption, viewOnce: viewOnce)
        }
    }

    func sendCapturedMedia(_ captured: CapturedCameraMedia, caption: String?, viewOnce: Bool = false) {
        let captionText = caption ?? ""
        switch captured {
        case .image(let image, let jpegData):
            let payload = ChatCameraCapturedMediaSender.makeImagePayload(
                image: image,
                caption: captionText,
                jpegData: jpegData
            )
            sendMedia(media: payload, caption: caption, groupId: "", viewOnce: viewOnce)
        case .video(let url):
            let payload = ChatCameraCapturedMediaSender.makeVideoPayload(url: url, caption: captionText)
            sendMedia(media: payload, caption: caption, groupId: "", viewOnce: viewOnce)
        case .videoNote(let url):
            let payload = ChatCameraCapturedMediaSender.makeVideoPayload(url: url, caption: captionText)
            sendMedia(media: payload, caption: caption, groupId: "", asVideoNote: true)
        }
    }
    
    func onUserTyping(_ status: UserTypingStatus) {
        Task {
            await conversationRoomUseCases.sendTyping.execute(
                conversationId: conversationId,
                isTyping: status == .isTyping,
                isRecording: status == .isRecording
            )
        }
    }

    func onUserStoppedTyping() {
        Task {
            await conversationRoomUseCases.sendTyping.stop(conversationId: conversationId)
        }
    }

    func onUserRecording() {
        Task {
            await conversationRoomUseCases.sendTyping.execute(
                conversationId: conversationId,
                isTyping: false,
                isRecording: true
            )
        }
    }
    
    func userTappedAnyNavBarAction(_ navActions:NavBarActionsType, dic : [String : Any]) {
//        coordinator.onNavBarActionPressed(navActions, dic: dic)
    }

      func userWantsToPickPhoto() {
//          coordinator.openPhotoPicker()
      }
    
    
    // MARK: - Compose Link Preview

    func detectLink(in text: String) {
        linkDetectionTask?.cancel()

        guard let url = ChatRoomLinkPreviewCoordinator.shouldFetchPreview(
            for: text,
            currentURL: composeLinkURL
        ) else {
            composeLinkPreview = nil
            composeLinkURL = nil
            return
        }

        composeLinkURL = url
        composeLinkPreview = nil

        linkDetectionTask = ChatRoomLinkPreviewCoordinator.fetchPreviewTask(for: url) { [weak self] preview in
            self?.composeLinkPreview = preview
        }
    }

    func dismissLinkPreview() {
        linkDetectionTask?.cancel()
        composeLinkPreview = nil
        composeLinkURL = nil
    }

    func sendTextMessage(_ text: String) {
        if messageBeingEdited != nil {
            commitMessageEdit(with: text)
            return
        }

        ChatRoomOutgoingTextCoordinator.send(
            plaintext: text,
            conversationId: conversationId,
            recipientId: currentReceiverUser?.userId ?? "",
            e2eeCoordinator: e2eeCoordinator,
            handlers: ChatRoomOutgoingTextCoordinator.Handlers(
                sendLocally: { [weak self] content, type, groupId in
                    self?.sendMediaAndTextMessage(content, type: type, groupId: groupId)
                },
                showError: { [weak self] message in
                    self?.showErrorNotification(message)
                },
                patchEncrypted: { [weak self] encrypted, codeMessage in
                    await self?.applyEncryptedText(encrypted, toCodeMessage: codeMessage)
                }
            )
        )
    }

    private func applyEncryptedText(_ encrypted: String, toCodeMessage codeMessage: String) async {
        messages = await ChatRoomEncryptedTextPatcher.patch(
            encrypted: encrypted,
            codeMessage: codeMessage,
            messages: messages,
            messagesUseCases: messagesUseCases
        )
    }

    func createTextMessageContent(_ text: String) -> MessageContent {
        MessageContent(text: text)
    }

    /// Persists the message to local store immediately with PENDING status
    /// (just like a normal send) so it survives app restarts.
    /// Returns the codeMessage so the pending queue can track it.
    @discardableResult
    private func sendPendingMessageLocally(_ content: MessageContent, type: MessageTypeProps, groupId: String) -> String? {
        return sendMediaAndTextMessage(content, type: type, groupId: groupId)
    }

    private func wireNotificationObservers() {
        let handlers = ChatRoomNotificationHandlersFactory.make(
            ChatRoomNotificationHandlersFactory.Dependencies(
                conversationId: conversationId,
                isGroup: { [weak self] in self?.isGroup ?? false },
                isGroupAdmin: { [weak self] in self?.isGroupAdmin ?? false },
                isJoinApprovalRequired: { [weak self] in self?.isJoinApprovalRequired ?? false },
                groupUseCases: { [weak self] in self?.groupUseCases },
                onCallHistoryPersisted: { [weak self] msg in
                    guard let self else { return }
                    Task {
                        await self.messagesStore.mergeIncoming([msg])
                    }
                },
                onContactBlockStatusChanged: { [weak self] isBlocked in
                    guard let self else { return }
                    self.isContactBlocked = isBlocked
                    if var updatedUser = self.currentReceiverUser {
                        updatedUser.isBlocked = isBlocked
                        self.currentReceiverUser = updatedUser
                        self.updateChannel(updatedUser)
                    }
                },
                onReloadChatActions: { [weak self] in
                    await self?.loadChatActions()
                },
                onGroupUpdated: { [weak self] in
                    guard let self else { return }
                    self.reloadGroupChat()
                    self.refreshGroupMembershipStatus()
                    self.rebuildGroupedMessages()
                }
            )
        )

        ChatRoomNotificationObserver.wire(
            conversationId: conversationId,
            currentReceiverContactId: { [weak self] in self?.currentReceiverUser?.idContact },
            handlers: handlers,
            subscriptions: &subscriptions
        )

        NotificationCenter.default.publisher(for: Notification.Name("TranslationKit.localeDidChange"))
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.translationLocaleToken += 1
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: ChatAppearanceStore.didChangeNotification)
            .sink { [weak self] _ in
                self?.syncChatAppearanceFromStore()
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .liveLocationShareEnded)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let event = notification.object as? LiveLocationShareEndedEvent,
                      event.conversationId == self.conversationId else { return }
                self.freezeLiveLocationBubble(event)
            }
            .store(in: &subscriptions)

        NotificationCenter.default.publisher(for: .outgoingMessageLocallySaved)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let event = notification.object as? OutgoingMessageLocallySavedEvent,
                      event.conversationId == self.conversationId else { return }
                Task { await self.messagesStore.mergeIncoming([event.message]) }
            }
            .store(in: &subscriptions)
    }

    private func flushPendingE2EEQueue() {
        Task {
            guard let e2eeCoordinator = e2eeCoordinator else { return }
            let updates = await e2eeCoordinator.flushPending(conversationId: conversationId)
            await ChatRoomE2EECoordinator.applyFlushResults(
                updates,
                pendingQueue: pendingE2EEQueue,
                patchEncrypted: { [weak self] encrypted, code in
                    await self?.applyEncryptedText(encrypted, toCodeMessage: code)
                },
                rebuildTimeline: { [weak self] in
                    self?.rebuildGroupedMessages()
                }
            )
        }
    }

    func sendMedia(media: MediaPayload, caption: String? = nil, groupId: String, asVideoNote: Bool = false, viewOnce: Bool = false) {
        let isVideo = media.mediaType == .video
        // groupId here is the batch UUID from ChatRoomGallerySendCoordinator — use it as mediaBatchId.
        // Never for view once: a batch is drawn as one album, which would show it.
        let batchId = groupId.isEmpty || viewOnce ? nil : groupId
        let mediaContent = ChatRoomMediaSendCoordinator.makeContent(from: media, caption: caption, batchId: batchId)
        let videoType: MessageTypeProps = asVideoNote ? .VIDEO_NOTE : .VIDEO
        let code = sendMediaAndTextMessage(mediaContent, type: isVideo ? videoType : .IMAGE, groupId: "", viewOnce: viewOnce)
        guard let code else {
            showErrorNotification(isVideo ? ChatErrorStrings.sendVideoFailed : ChatErrorStrings.sendImageFailed)
            return
        }
        if isVideo {
            // A failed cache here is what later surfaces as an upload dying with
            // "Local file not found", so report it at the point it happens.
            if !ChatRoomMediaSendCoordinator.cacheSentVideo(media: media, code: code) {
                showErrorNotification(ChatErrorStrings.prepareVideoFailed)
            }
        } else {
            // Cache the JPEG data with the correct message code (codeMessage)
            ChatRoomMediaSendCoordinator.cacheImageFromPayload(media, code: code)
        }
    }

    // MARK: - Send Document

    func fetchRecentSentDocuments(limit: Int = 20) async -> [MessageDataItem] {
        guard !conversationId.isEmpty else { return [] }
        return await messagesUseCases.fetchRecentSentDocuments.execute(
            conversationId: conversationId,
            limit: limit
        )
    }

    func sendDocument(fileURL: URL) {
        ChatRoomDocumentSender.send(
            fileURL: fileURL,
            handlers: ChatRoomDocumentSender.Handlers(
                sendMessage: { [weak self] content, type, groupId, messageCode in
                    self?.sendMediaAndTextMessage(
                        content,
                        type: type,
                        groupId: groupId,
                        messageCode: messageCode
                    )
                },
                showError: { [weak self] message in
                    self?.showErrorNotification(message)
                }
            )
        )
    }

    private func patchAttachmentFile(sourceURL: URL, code: String, field: ChatRoomAttachmentField) {
        ChatRoomAttachmentPersistence.patchMessage(
            sourceURL: sourceURL,
            code: code,
            field: field,
            messages: &messages,
            messagesUseCases: messagesUseCases,
            onUpdated: { [weak self] in
                self?.rebuildGroupedMessages()
            }
        )
    }

    // MARK: - Send Contact
    func sendContactMessage(contacts: [ContactItem]) {
        guard !contacts.isEmpty else { return }
        let content = MessageContent(contact: contacts)
        sendMediaAndTextMessage(content, type: .CONTACT, groupId: "")
    }

    // MARK: - Send Location
    func sendLocationMessage(location: ChatLocationItem) {
        guard location.isLive != true else {
            startLiveLocationShare(location: location)
            return
        }

        let content = MessageContent(location: location)
        let code = sendMediaAndTextMessage(content, type: .LOCATION, groupId: "")
        guard let code else {
            showErrorNotification(ChatErrorStrings.sendLocationFailed)
            return
        }
        #if DEBUG
        print("📍 Location message sent: \(location.coords.lat), \(location.coords.lng)")
        #endif
    }

    /// Sends the anchor message for a live share and starts publishing ticks.
    ///
    /// The message code is generated up front because it is also the share id —
    /// the contract recommends the two match, and it is what lets an arriving
    /// tick find the bubble it belongs to.
    ///
    /// One share per conversation: starting a second would leave two live
    /// bubbles in the thread with no way for the reader to tell which is
    /// current, so the running one is ended first.
    func startLiveLocationShare(location: ChatLocationItem) {
        let manager = LiveLocationSessionManager.shared
        if let running = manager.activeShare(in: conversationId) {
            manager.stop(shareId: running.shareId)
        }

        let code = OutgoingMessageBuilder.newCode()
        let expiresAt = location.expiresAt ?? Date().addingTimeInterval(
            LiveLocationDuration.fifteenMinutes.seconds
        )
        let duration = LiveLocationDuration.nearest(
            toSeconds: location.duration ?? LiveLocationDuration.fifteenMinutes.seconds
        )

        var anchor = location
        anchor.shareId = code
        anchor.expiresAt = expiresAt
        anchor.duration = duration.seconds

        guard sendMediaAndTextMessage(
            MessageContent(location: anchor),
            type: .LOCATION,
            groupId: "",
            messageCode: code
        ) != nil else {
            showErrorNotification(ChatErrorStrings.startLiveLocationFailed)
            return
        }

        manager.configure(publisher: conversationRoomUseCases.publishLiveLocation)
        manager.start(
            LiveLocationShareSession(
                shareId: code,
                conversationId: conversationId,
                codeMessage: code,
                durationMinutes: duration.minutes,
                expiresAt: expiresAt
            )
        )

        #if DEBUG
        print("📡 Live location share started: \(code) until \(expiresAt)")
        #endif
    }

    /// Ends a share started from this device, from the bubble's stop control.
    func stopLiveLocationShare(shareId: String) {
        LiveLocationSessionManager.shared.stop(shareId: shareId)
    }

    /// Writes the end of a share into the anchor message.
    ///
    /// Without this the bubble would read as live again after a relaunch: the
    /// in-memory tick store starts empty, and the stored message would still
    /// say `isLive` until its deadline passed.
    ///
    /// Local only. The contract's `modify-message` step, which would freeze the
    /// bubble for the other participants too, is listed as optional there and
    /// is not sent yet — watchers learn from `LIVE_LOCATION_STOP` instead.
    private func freezeLiveLocationBubble(_ event: LiveLocationShareEndedEvent) {
        guard let index = messages.firstIndex(where: {
            ($0.message.location?.shareId ?? $0.codeMessage) == event.shareId
        }) else { return }

        var updated = messages[index]
        guard var location = updated.message.location, location.isLive == true else { return }

        // The deadline is moved to now rather than clearing `isLive`: the
        // bubble has to keep saying it was a live share so it can say the share
        // ended, and an expiry in the past is already what every reader here
        // treats as over.
        location.expiresAt = Date()
        if let latitude = event.latitude, let longitude = event.longitude {
            location.coords = CoordsLocation(lat: latitude, lng: longitude)
        }
        updated.message.location = location

        messages[index] = updated
        rebuildGroupedMessages()

        Task { [weak self] in
            guard let self else { return }
            await self.messagesStore.upsertMessage(updated)
            try? await self.messagesUseCases.updateMessages.execute(message: updated)
        }
    }

    // MARK: - Send Poll

    func sendPollMessage(question: String, options: [String], allowsMultipleAnswers: Bool = false) {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedQuestion.isEmpty, trimmedOptions.count >= 2 else {
            showErrorNotification("A poll needs a question and at least two options")
            return
        }

        var content = MessageContent()
        content.poll = PollContent(
            question: trimmedQuestion,
            options: trimmedOptions.map { PollOption(text: $0) },
            isMultipleChoice: allowsMultipleAnswers
        )
        sendMediaAndTextMessage(content, type: .POLL, groupId: "")
    }

    // MARK: - Vote Poll

    /// Votes locally first, then publishes the resulting selection.
    ///
    /// The bar has to move on the tap — the round trip is not fast enough to wait
    /// for — and the server's echo re-applies the same selection through the same
    /// merger, so the optimistic state and the confirmed state converge.
    ///
    /// Tapping an option already held retracts it, so this covers unvoting too.
    func voteOnPoll(messageId: String, optionId: String) {
        guard let index = messages.firstIndex(where: { $0.codeMessage == messageId }),
              let poll = messages[index].message.poll,
              !poll.isClosed
        else { return }

        let voterId = CurrentSessionInfo.shared.currentUid
        guard !voterId.isEmpty else { return }

        let merged = PollVoteMerger.toggle(optionId: optionId, voterId: voterId, in: poll)
        guard merged != poll else { return }

        var updated = messages[index]
        updated.message.poll = merged

        // The list renders `groupedMessages`, which is rebuilt only when the
        // store publishes — writing to `messages` alone leaves the drawn
        // timeline holding the pre-vote bubble until the room reloads. The
        // reaction path takes these same three steps for the same reason.
        messages[index] = updated
        rebuildGroupedMessages()

        let selection = merged.selection(of: voterId)

        Task { [conversationId] in
            await messagesStore.upsertMessage(updated)
            try? await messagesUseCases.updateMessages.execute(message: updated)
            await conversationRoomUseCases.votePoll.execute(
                messageId: messageId,
                optionIds: selection,
                conversationId: conversationId
            )
        }
    }

    /// Name and avatar for someone who voted, for the poll votes screen.
    ///
    /// The group roster covers group threads; a direct thread has only two
    /// people, so the other party comes from the room itself. Returns the raw id
    /// as a last resort rather than an empty row — an unnamed voter still voted.
    func pollVoterDisplay(for userId: String) -> (name: String, avatar: String?) {
        if userId == CurrentSessionInfo.shared.currentUid {
            return (translate(ChatTranslationKeys.POLL_VOTER_YOU), CurrentSessionInfo.shared.userProfile)
        }
        if let member = groupMembersById[userId] {
            return (member.name, member.avatar.flatMap { $0.isEmpty ? nil : $0 })
        }
        if let receiver = currentReceiverUser, receiver.userId == userId {
            return (receiver.name ?? userId, receiver.avatar)
        }
        return (userId, nil)
    }

    func translate(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    func saveCachedMedia(url: String, key: String, type: MediaType, UIimage: UIImage?) {
        ChatRoomMediaPersistence.saveCachedMedia(url: url, key: key, type: type, image: UIimage)
    }

    /// Called by the bubble after upload succeeds to clear the pendingUpload flag in DB
    /// and persist the remote download URL so the realtime sender uses the CDN URL.
    func clearPendingUpload(codeMessage: String, remoteUrl: String? = nil) {
        guard let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) else { return }

        // Idempotent, because it is now reached twice for the same upload: once
        // from the caller's own success closure and once from the view model's
        // recovery hook. Without this guard each success published the message
        // twice — the same `codeMessage` sent to the server two times over.
        let current = messages[index]
        let alreadyCleared = !current.message.shouldUploadDownload && !current.message.shouldRetry
        let urlUnchanged = remoteUrl.map { $0.isEmpty || current.message.remoteUri == $0 } ?? true
        if alreadyCleared && urlUnchanged { return }

        var updated = current
        updated.message.shouldUploadDownload = false
        // A retry that worked has to take the failure with it, or the bubble keeps
        // offering to retry something that is already sent.
        updated.message.shouldRetry = false

        if let remoteUrl, !remoteUrl.isEmpty {
            updated.message.remoteUri = remoteUrl
            // Patch the type-specific URL field so bubbles and realtime sending use the CDN URL
            switch updated.typeMessage {
            case .IMAGE:  updated.message.image = remoteUrl
            case .VIDEO, .VIDEO_NOTE:  updated.message.video = remoteUrl
            case .VOICE, .AUDIO: updated.message.audio = remoteUrl
            case .DOCUMENT: updated.message.file = remoteUrl
            default: break
            }
        }

        messages[index] = updated
        Task {
            let toPublish = OutboundMessageFieldNormalizer.ensuringSenderFields(updated)
            try? await messagesUseCases.updateMessages.execute(message: toPublish)
            await conversationRoomUseCases.publishOutgoingMessage.execute(
                message: toPublish,
                conversationId: conversationId
            )
        }
    }

    // MARK: - Automatic transfer attempts

    /// Persists how many times we have automatically tried to move this message's
    /// media, so the cap survives a relaunch.
    ///
    /// Unlike `clearPendingUpload` this deliberately does **not** publish the
    /// message: the count is this device's bookkeeping about its own retries, and
    /// nobody else in the conversation has any use for it.
    func persistAutoTransferAttempts(codeMessage: String, attempts: Int) {
        guard let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) else { return }
        guard messages[index].message.autoTransferAttempts != attempts else { return }

        var updated = messages[index]
        updated.message.autoTransferAttempts = attempts
        messages[index] = updated

        Task {
            try? await messagesUseCases.updateMessages.execute(message: updated)
        }
    }

    // MARK: - View once

    /// Opens a view-once message full screen, and uses it up straight away.
    ///
    /// Marked opened as it opens, not as it closes: killing the app while it is
    /// on screen must not buy a second look. The content is only wiped when the
    /// viewer closes, so it stays playable until then; a copy killed before that
    /// is wiped the next time its bubble appears.
    func openViewOnce(_ message: MessageDataItem) {
        guard let index = messages.firstIndex(where: { $0.codeMessage == message.codeMessage }) else { return }
        let current = messages[index]
        guard current.isViewOnce, current.message.viewOnceOpenedAt == nil else { return }

        viewOnceMessage = current

        var opened = current
        opened.message.viewOnceOpenedAt = Date()
        messages[index] = opened
        Task {
            try? await messagesUseCases.updateMessages.execute(message: opened)
        }
    }

    func closeViewOnce() {
        guard let shown = viewOnceMessage else { return }
        viewOnceMessage = nil
        wipeViewOnceContent(codeMessage: shown.codeMessage)
    }

    /// Deletes an opened view-once message's files and empties its row, so
    /// nothing readable or playable is left on this device. Local only, like
    /// `persistAutoTransferAttempts`: the other side has its own copy.
    func wipeViewOnceContent(codeMessage: String) {
        guard viewOnceMessage?.codeMessage != codeMessage,
              let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) else { return }
        let current = messages[index]
        guard current.viewOnceNeedsWipe else { return }

        // Before the row is emptied: the audio file is found by its file name.
        ChatRoomMessageMediaCleanup.deleteMediaFiles(for: current)
        ChatImageMemoryCache.shared.remove(forKey: codeMessage)
        ChatMediaPreviewCache.shared.remove(forKey: codeMessage)

        var wiped = current
        wiped.message.text = ""
        wiped.message.caption = nil
        wiped.message.audio = nil
        wiped.message.video = nil
        wiped.message.image = nil
        wiped.message.UIimage = nil
        wiped.message.file = nil
        wiped.message.fileName = nil
        wiped.message.thumbnail = nil
        wiped.message.remoteUri = nil
        wiped.message.url = nil
        wiped.message.waveform = nil
        wiped.message.shouldUploadDownload = false
        wiped.message.shouldRetry = false
        messages[index] = wiped
        Task {
            try? await messagesUseCases.updateMessages.execute(message: wiped)
        }
    }

    /// Restores the full automatic allowance after the user asks for a retry.
    func clearAutoTransferAttempts(codeMessage: String) {
        persistAutoTransferAttempts(codeMessage: codeMessage, attempts: 0)
    }

    // MARK: - Media transfer outcome

    /// Records that this message's media could not be moved — an upload for one we
    /// sent, a download for one we received.
    ///
    /// Persisted, unlike the upload view model's own dictionaries, which are memory
    /// and forget everything when the room closes. Without this a failed photo came
    /// back from a relaunch looking exactly like a queued one, which is the whole
    /// reason the bubbles could not tell the two apart.
    ///
    /// Like `persistAutoTransferAttempts` this does not publish: the outcome is
    /// this device's own, and means nothing to anyone else in the conversation.
    func setMediaTransferFailed(codeMessage: String, failed: Bool) {
        guard let index = messages.firstIndex(where: { $0.codeMessage == codeMessage }) else { return }
        guard messages[index].message.shouldRetry != failed else { return }

        var updated = messages[index]
        updated.message.shouldRetry = failed
        messages[index] = updated

        Task {
            try? await messagesUseCases.updateMessages.execute(message: updated)
        }
    }

    /// The media message behind a viewer page.
    ///
    /// `allMediasMessages` first, since that is what the viewer was built from,
    /// falling back to the room's own list for one just sent.
    func mediaMessage(for codeMessage: String) -> MessageDataItem? {
        allMediasMessages.first { $0.codeMessage == codeMessage }
            ?? messages.first { $0.codeMessage == codeMessage }
    }

    /// Rebuilds a viewer page after its file has arrived.
    ///
    /// The page's `fullResURL` and `videoURL` are resolved from disk when the
    /// viewer opens; for a file that was not there yet they are nil, and stay nil
    /// however the transfer goes. This resolves them again.
    func refreshedViewerItem(for codeMessage: String) -> MediaViewerItem? {
        guard let message = mediaMessage(for: codeMessage) else { return nil }
        return ChatRoomMediaViewerCoordinator.makeItem(
            message,
            thumbnail: ChatImageMemoryCache.shared.image(forKey: codeMessage)
                ?? DiskMediaManager.shared.loadImageFromDisk(fileName: codeMessage, pathName: .CHAT)
        )
    }

    // MARK: - Error Notification
    private func showErrorNotification(_ message: String) {
        errorNotificationMessage = message
        showErrorNotification = true
        
        // Auto-dismiss after 3 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.showErrorNotification = false
        }
    }
    
    @discardableResult
    func sendMediaAndTextMessage(
        _ content: MessageContent,
        type: MessageTypeProps,
        groupId: String,
        messageCode: String? = nil,
        viewOnce: Bool = false
    ) -> String? {
        persistGroupIntroDismissalPermanently()
        return messageComposer.send(content, type: type, messageCode: messageCode, viewOnce: viewOnce)
    }

    /// Composes every outgoing message for this room.
    ///
    /// Shared with the channel room — the building is identical, only the context
    /// differs, and this room's context is a peer, a recipient and whatever is
    /// being replied to.
    private lazy var messageComposer = ConversationMessageComposer(
        conversationId: conversationId,
        kind: isGroup ? .group : .direct,
        sendMessage: conversationRoomUseCases.sendMessage,
        context: { [weak self] in
            ConversationMessageComposer.Context(
                receiver: self?.currentReceiverUser,
                recipientId: self?.currentReceiverUser?.userId,
                reply: OutgoingMessageBuilder.replyFrom(self?.replyMessage)
            )
        },
        onError: { [weak self] message in
            self?.showErrorNotification(message)
        },
        onSent: { [weak self] in
            self?.replyMessage = nil
        }
    )
    func onSendImage(caption: String? = nil, selectedImages: [GalleryImage]) {
        ChatRoomGallerySendCoordinator.sendImages(
            caption: caption,
            selectedImages: selectedImages,
            handlers: ChatRoomGallerySendCoordinator.Handlers(
                sendMedia: { [weak self] payload, caption, groupId in
                    self?.sendMedia(media: payload, caption: caption, groupId: groupId)
                }
            ) 
        )
    }

    func onSendMedia(caption: String? = nil, selectedMedia: [GalleryMedia], viewOnce: Bool = false) {
        ChatRoomGallerySendCoordinator.sendMediaItems(
            caption: caption,
            selectedMedia: selectedMedia,
            handlers: ChatRoomGallerySendCoordinator.Handlers(
                sendMedia: { [weak self] payload, caption, groupId in
                    self?.sendMedia(media: payload, caption: caption, groupId: groupId, viewOnce: viewOnce)
                }
            )
        )
    }

    
    
    private func clearTextInputArea() {
        textMessage = ""
        mediaAttachments.removeAll()
        photoPickerItems.removeAll()
        // A sent message is no longer a draft. `onDisappear` would clear it too,
        // but only on the way out — this keeps the list honest if the app dies
        // first. Writes nothing when there was no draft to begin with.
        persistDraft()
    }
    
    private func scrollToBottom(isAnimated: Bool) {
        scrollToBottomRequest.scroll = true
        scrollToBottomRequest.isAnimated = isAnimated
    }
    
    func dismissVideoPlayer() {
        videoPlayerState.player?.replaceCurrentItem(with: nil)
        videoPlayerState.player = nil
        videoPlayerState.show = false
    }
    
    func showMediaPlayer(_ fileURL: URL) {
        videoPlayerState.show = true
        videoPlayerState.player = AVPlayer(url: fileURL)
    }
    
    func handleMediaAttachmentPreview(_ action: MediaAttachmentPreview.UserAction) {
        switch action {
        case .play(let attachment):
            guard let fileURL = attachment.fileURL else { return }
            showMediaPlayer(fileURL)
        case .remove(let attachment):
            if let index = mediaAttachments.firstIndex(where: { $0.id == attachment.id }) {
                mediaAttachments.remove(at: index)
            }
            guard let fileURL = attachment.fileURL else { return }
            if attachment.type == .audio(.stubURL, .stubTimeInterval) {
                // TODO: Implement audio file deletion
                // The OpusAudioService is actor-isolated and not directly accessible here
                // Consider adding a delete method to VoiceRecordingViewModel if needed
            }
        }
    }
    
    func isNewDay(for message: MessageDataItem, at index: Int) -> Bool {
        false
    }
    
    func handleReplyPreviewTap(_ repliedMessage: MessageDataItem) {
        if repliedMessage.typeMessage == .STATUS {
            pendingStatusReplyCode = repliedMessage.codeMessage
        } else {
            scrollToMessage = repliedMessage.codeMessage
        }
    }
    
    // MARK: - Channel Invite Actions
    
    /// Handles when user taps "Join" on a channel invitation bubble.
    /// Subscribes the user to the channel using the channel use cases.
    func handleChannelInviteJoin(channelId: String) {
        Task { @MainActor in
            do {
                // Note: This requires access to ChannelUseCases
                // For now, we'll need to add this dependency to ChatRoomViewModel
                // or route through a coordinator/delegate pattern
                
                // Temporary: Show a toast that the feature needs channel use cases
                // This will be properly implemented when we wire up the dependencies
                showErrorNotification("Channel subscription requires ChannelUseCases - to be wired in dependency injection")
                
                // TODO: Once ChannelUseCases is injected:
                // try await channelUseCases.subscription.subscribe(channelId: channelId)
                // showSuccessNotification("Successfully joined channel!")
                
            } catch {
                showErrorNotification(String(format: ChatErrorStrings.channelJoinFailedWithCause, error.localizedDescription))
            }
        }
    }
    
    // MARK: - Message Edit

    func beginEditingMessage(_ message: MessageDataItem) {
        guard message.isSentByMe, message.typeMessage == .TEXT, !message.isDeleted else { return }
        withAnimation(.easeInOut(duration: 0.3)) {
            messageBeingEdited = message
            replyMessage = nil
            dismissLinkPreview()
        }
        textMessage = message.message.text
        scrollToMessage = message.id
    }

    func cancelMessageEdit() {
        withAnimation(.easeInOut(duration: 0.3)) {
            messageBeingEdited = nil
            textMessage = ""
        }
    }

    func commitMessageEdit(with newText: String) {
        guard let message = messageBeingEdited else { return }
        let trimmed = newText.trimmingCharacters(in: .whitespacesAndNewlines)
        cancelMessageEdit()

        guard !trimmed.isEmpty, trimmed != message.message.text else { return }

        Task {
            do {
                try await conversationRoomUseCases.modifyMessage.execute(
                    message: message,
                    newText: trimmed,
                    conversationId: conversationId
                )
            } catch {
                showErrorNotification(error.localizedDescription)
            }
        }
    }

    func onMessageAction(_ action: MessageMenuAction, to row: MessageRow) {
        if action == .edit {
            if case .message(let message) = row {
                beginEditingMessage(message)
            }
            return
        }

        let result = ChatRoomMessageActionCoordinator.handle(
            action,
            on: row,
            selectedMessages: selectedMessages
        )
        if let copyText = result.copyText {
            UIPasteboard.general.string = copyText
        }
        if let reply = result.replyMessage {
            replyMessage = reply
        }
        if let selection = result.selection {
            withAnimation(.easeInOut(duration: 0.3)) {
                selectedMessages = selection.selectedMessages
                messageAction = selection.messageAction
            }
        }
    }

    var isSelectionMode: Bool {
        ChatRoomMessageActionCoordinator.isSelectionMode(messageAction: messageAction)
    }

    func toggleSelection(for message: MessageDataItem) {
        guard !message.isDeleted else { return }
        let update = ChatRoomMessageActionCoordinator.toggleSelection(
            for: message,
            selectedMessages: selectedMessages,
            messageAction: messageAction
        )
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedMessages = update.selectedMessages
            messageAction = update.messageAction
        }
    }

    func isMessageSelected(_ message: MessageDataItem) -> Bool {
        ChatRoomMessageActionCoordinator.isMessageSelected(message, in: selectedMessages)
    }
    
    // MARK: - Forward Messages

    /// Sends the current selection on to every chosen target, in the order they
    /// were picked.
    ///
    /// Each send is awaited rather than fired into its own task: the pipeline
    /// publishes as it goes, and detached sends let a five-message forward
    /// arrive shuffled — or let the trailing caption overtake the media it
    /// belonged to.
    /// What the picker forwards: whatever selection mode is holding.
    var messagesToForward: [MessageDataItem] { selectedMessages ?? [] }

    func forward(
        to targets: [ForwardTarget],
        caption: String?,
        statusPoster: (any ForwardStatusPosting)? = nil
    ) async {
        guard let messagesToForward = selectedMessages,
              !messagesToForward.isEmpty,
              !targets.isEmpty
        else { return }

        let trimmedCaption = caption?.trimmingCharacters(in: .whitespacesAndNewlines)
        let extraMessage = (trimmedCaption?.isEmpty ?? true) ? nil : trimmedCaption

        let conversationTargets = targets.filter { !$0.isStatus }
        for target in conversationTargets {
            await forward(messagesToForward, to: target, caption: extraMessage)
        }

        if targets.contains(where: \.isStatus) {
            await postToStatus(messagesToForward, caption: extraMessage, poster: statusPoster)
        }

        exitSelectionMode()
        showForwardMessagePicker = false

        // One conversation, and not this one: follow the messages there. Several
        // recipients have no single place to go, so the room stays put.
        if conversationTargets.count == 1, let target = conversationTargets.first {
            navigateIfElsewhere(target)
        }
    }

    /// Forwarding is `MessageForwardingService`'s job — the channel room forwards
    /// the same way, and this room should not own the only copy of it.
    private func forward(
        _ messages: [MessageDataItem],
        to target: ForwardTarget,
        caption: String?
    ) async {
        await forwardingService.forward(messages, to: target, caption: caption)
    }

    private lazy var forwardingService = MessageForwardingService(
        sendMessage: conversationRoomUseCases.sendMessage
    )

    private func postToStatus(
        _ messages: [MessageDataItem],
        caption: String?,
        poster: (any ForwardStatusPosting)?
    ) async {
        guard let poster else {
            showErrorNotification(translate(ChatTranslationKeys.FORWARD_STATUS_FAILED))
            return
        }

        var posted = 0
        for message in messages {
            guard let story = ForwardStatusMapper.story(from: message, caption: caption) else { continue }
            await poster.addOwnStatus(story: story)
            posted += 1
        }

        if posted < messages.count {
            showErrorNotification(translate(ChatTranslationKeys.FORWARD_STATUS_FAILED))
        }
    }

    private func navigateIfElsewhere(_ target: ForwardTarget) {
        guard let conversationId = target.conversationId,
              conversationId != self.conversationId,
              let receiver = target.receiver
        else { return }

        let conversationType: ConversationType = target.isGroup
            ? .group(conversationId: conversationId)
            : .direct(
                phoneNumber: receiver.phone ?? "",
                conversationId: conversationId,
                // We just forwarded to this person — we know exactly who they are.
                peer: DirectChatPeer(
                    userId: receiver.userId,
                    idContact: receiver.idContact,
                    name: receiver.name ?? "",
                    avatar: receiver.avatar ?? ""
                )
            )

        navigationCoordinator?.handle(.chatRoom(type: conversationType, isArchived: false))
    }

    // MARK: - Forward Selection Actions
    
    func showForwardPicker() {
        ChatKeyboard.hide()
        showForwardMessagePicker = true
    }
    
    /// Clears selection mode (delete or forward) and restores the composer.
    func exitSelectionMode() {
        withAnimation(.easeInOut(duration: 0.3)) {
            selectedMessages = nil
            messageAction = nil
        }
    }

    func cancelForwardSelection() {
        exitSelectionMode()
    }
    
    var isForwardSelectionMode: Bool {
        messageAction == .forwardSelection
    }

    func addReaction(_ reaction: Reaction, to message: MessageDataItem) {
        guard reaction != .more else { return }
        addReaction(emoji: reaction.emoji, to: message)
    }

    func addReaction(emoji: String, to message: MessageDataItem) {
        Task {
            do {
                let updated = try await conversationRoomUseCases.reactToMessage.execute(
                    message: message,
                    emoji: emoji,
                    conversationId: conversationId
                )
                await messagesStore.upsertMessage(updated)
                if let index = messages.firstIndex(where: { $0.codeMessage == message.codeMessage }) {
                    messages[index] = updated
                    rebuildGroupedMessages()
                }
            } catch {
                #if DEBUG
                print("Failed to update reaction: \(error)")
                #endif
            }
        }
    }

    
 


}

