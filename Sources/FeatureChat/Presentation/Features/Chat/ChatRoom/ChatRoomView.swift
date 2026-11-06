//
//  ChatRoomScreen.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 8.01.2025.
//

import SwiftUI
import PhotosUI
import SDWebImageSwiftUI
import AVKit
import QuickLook
import WaanguSharedUI
import WaanguCoreKit

// MARK: - User Model

struct UserRoom: Equatable {

    
    let idContact: String
    let userId: String
    let phone: String?
    let name: String?
    let avatar: String?
    let description: String?
    var isOnline: Bool = false
    var onlineStatus: UserOnline
    var isBlocked : Bool
    static func == (lhs: UserRoom, rhs: UserRoom) -> Bool {
        lhs.idContact == rhs.idContact &&
        lhs.userId == rhs.userId &&
        lhs.phone == rhs.phone &&
        lhs.name == rhs.name
    }
}


// MARK: - Main Chat Room Screen

@available(iOS 16.0, *)
struct ChatRoomScreen: View {
    /// The parts of chat the host turned on: the call buttons below exist only with calls.
    @Environment(\.chatEnabledModules) private var enabledModules
    let naviagationCoord: ChatsTabCoordinator
    // Inputs
    let user: UserRoom
//    let messages: [MessageDataItem] // You need to define MessageDataItem elsewhere
    let devicesContacts: [UserContactProps]
    let waanguContacts: [UserContactProps]
    
    // View Models
    @ObservedObject private var viewModel: ChatRoomViewModel
    @StateObject private var voiceMessagePlayer = VoiceMessagePlayer()
    @StateObject private var galleryViewModel: GalleryViewModel
    @ObservedObject private var mediaViewModel: PHMediaManagerViewModel
    let uploadViewModel: FileUploadViewModel
    let globalAudioManager: GlobalAudioPlaybackManager
    @ObservedObject private var channelViewModel: ChannelTabViewModel
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @State private var showDeleteConfirmation: Bool = false
    @State private var showChatSearch: Bool = false
    @State private var showAddParticipant = false
    @State private var showInviteLinkSheet = false
    @State private var showRealtimeMonitor = false
    @State private var pendingFinanceSelection: FinanceCatalogEntry?
     private var contactUseCase: ContactsUseCasesProtocol
     private var opusPlaybackService: any OpusPlaybackServiceProtocol
     private var groupPermissionsUseCases: GroupPermissionsUseCasesProtocol?
     private var discussionUseCases: DiscussionUseCasesProtocol
    private let updatesTabCoordinator: UpdatesTabCoordinator
    @ObservedObject private var statusStore: StoriesViewModel

    // MARK: TESTING
    
//    @State private var cachedImagesData: [CachedImageItem] = []
//    @State private var selectedItem: CachedImageItem?
    
    
    private var conversationId:String
    private var conversationType: ConversationType

    
    init(
        imageTransitionNamespace: Namespace.ID,
        conversationType: ConversationType,
        chatListViewModel: ChannelTabViewModel,
        chatPartnerPickerViewModel: ChatPartnerPickerViewModel,
        phMediaManagerViewModel:PHMediaManagerViewModel,
        messagesUseCases: MessagesUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        // e2eeUseCases: E2EEUseCasesProtocol, // Temporarily disabled
        pendingE2EEQueue: any PendingE2EEQueueProtocol,
        contactsUseCases: ContactsUseCasesProtocol,
        voiceRecordingViewModel: VoiceRecordingViewModel,
        opusPlaybackService: any OpusPlaybackServiceProtocol,
        chatActionsUseCase: ChatActionsUseCaseProtocol,
        groupUseCases: GroupUseCasesProtocol? = nil,
        groupPermissionsUseCases: GroupPermissionsUseCasesProtocol? = nil,
        isArchived: Bool,
        navigationCoord: ChatsTabCoordinator,
        uploadViewModel: FileUploadViewModel,
        globalAudioManager: GlobalAudioPlaybackManager,
        translationService: (any TranslationServiceProtocol)? = nil,
        conversationRoomUseCases: ConversationRoomUseCasesProtocol,
        messagesStoreFactory: @escaping () -> ChatRoomMessagesStore,
        financeSurface: ChatFinanceSurface? = nil
    ) {
        let idConvers: String
        let contact: ContactChannel

        switch conversationType {
        case .direct(let phoneNumber, let knownConversationId, let peer):
            // Which conversation, then who it is with — two questions, answered
            // separately. They used to be tangled together, so a branch that
            // found the conversation but not the contact left the room nameless.
            let listContact: ContactChannel?

            if let knownId = knownConversationId, !knownId.isEmpty {
                idConvers = knownId
                listContact = (
                    chatListViewModel.discussions.first(where: { $0.conversationId == knownId })
                        ?? chatListViewModel.archivedDiscussions.first(where: { $0.conversationId == knownId })
                )?.contact
            } else if let existing = DirectRoomContactResolver.discussion(
                for: phoneNumber,
                in: chatListViewModel.discussions
            ) {
                idConvers = existing.id
                listContact = existing.contact
            } else if let archived = DirectRoomContactResolver.discussion(
                for: phoneNumber,
                in: chatListViewModel.archivedDiscussions
            ) {
                idConvers = archived.id
                listContact = archived.contact
            } else {
                idConvers = UUID().lowercasedString
                listContact = nil
            }

            contact = DirectRoomContactResolver.resolve(
                phoneNumber: phoneNumber,
                listContact: listContact,
                directoryContact: DirectRoomContactResolver.directoryContact(
                    for: phoneNumber,
                    in: chatPartnerPickerViewModel.waanguUsers
                ),
                peer: peer
            )

        case .group(let groupConversationId):
            idConvers = groupConversationId
            if isArchived {
                let discussion = chatListViewModel.archivedDiscussions.first { $0.id == groupConversationId }
                contact = discussion?.contact ?? ContactChannel(isBlocked: false)
            } else {
                let discussion = chatListViewModel.discussions.first { $0.id == groupConversationId }
                contact = discussion?.contact ?? ContactChannel(isBlocked: false)
            }
        }

        self.conversationId = idConvers
        self.conversationType = conversationType

        let userdisc = UserRoom(
            idContact: contact.id,
            userId: contact.userId,
            phone: contact.phone,
            name: contact.userName,
            avatar: contact.image,
            description: "",
            onlineStatus: ChatRoomPresenceText.status(for: contact.userId, translator: translationService),
            isBlocked: contact.isBlocked
        )
    
        self.user = userdisc
        self.channelViewModel = chatListViewModel
        self.devicesContacts = chatPartnerPickerViewModel.deviceContacts
        self.waanguContacts = chatPartnerPickerViewModel.waanguUsers
        self.contactUseCase = contactsUseCases
        self.opusPlaybackService = opusPlaybackService
        self.groupPermissionsUseCases = groupPermissionsUseCases
        self.naviagationCoord = navigationCoord
        self.uploadViewModel = uploadViewModel
        self.globalAudioManager = globalAudioManager

        _viewModel = ObservedObject(
            wrappedValue: navigationCoord.chatRoomViewModel(for: idConvers) {
                ChatRoomViewModel(
                    userdisc,
                    isGroup: conversationType.isGroup,
                    conversationId: idConvers,
                    messagesUseCase: messagesUseCases,
                    discussionsUseCase: discussionUseCases,
                    // e2eeUseCases: e2eeUseCases, // Temporarily disabled
                    pendingE2EEQueue: pendingE2EEQueue,
                    voiceRecordingViewModel: voiceRecordingViewModel,
                    contactsUseCases: contactsUseCases,
                    chatActionsUseCase: chatActionsUseCase,
                    groupUseCases: conversationType.isGroup ? groupUseCases : nil,
                    groupPermissionsUseCases: conversationType.isGroup ? groupPermissionsUseCases : nil,
                    navigationCoordinator: navigationCoord,
                    translationService: translationService,
                    messagesStore: messagesStoreFactory(),
                    conversationRoomUseCases: conversationRoomUseCases,
                    conversationWriteAccess: navigationCoord.feature.conversationWriteAccess,
                    financeSurface: financeSurface
                )
            }
        )
        _galleryViewModel = StateObject(wrappedValue: GalleryViewModel(
            user: userdisc,
            isGroup: conversationType.isGroup,
            conversationId: idConvers,
            discussionsUseCase: discussionUseCases,
            devicesContacts: chatPartnerPickerViewModel.deviceContacts,
            waanguContacts: chatPartnerPickerViewModel.waanguUsers
        ))
        self.mediaViewModel = phMediaManagerViewModel
        self.contactUseCase = contactsUseCases
        self.opusPlaybackService = opusPlaybackService
        self.groupPermissionsUseCases = groupPermissionsUseCases
        self.discussionUseCases = discussionUseCases
        self.updatesTabCoordinator = UpdatesTabCoordinator(feature: navigationCoord.feature)
        _statusStore = ObservedObject(wrappedValue: navigationCoord.feature.makeStoriesViewModel())
        
    }
    
    // MARK: - Header

    /// A name when we have one, the number when we don't, "Unknown user" when
    /// we have neither.
    ///
    /// Blank was the old answer, and it is never the right one: a contact
    /// shared with you is by definition someone you have not saved, so the
    /// number is the only thing that identifies them until you do.
    private var headerDisplayName: String {
        ChatDisplayName.text(
            name: user.name,
            phone: user.phone,
            identifiers: [user.userId, user.idContact, conversationId],
            translator: viewModel.translationService
        )
    }

    /// `nil` when we know nothing — the subtitle is then omitted entirely
    /// rather than filled with a guess.
    private var headerPresenceText: String? {
        if user.onlineStatus.status == .online {
            return viewModel.translationService?
                .resolve(key: ChatTranslationKeys.CHAT_ONLINE, module: ChatTranslationKeys.MODULE, args: []).value ?? "Online"
        }
        let lastSeen = user.onlineStatus.lastSeen
        return lastSeen.isEmpty ? nil : lastSeen
    }

    var body: some View {
        ZStack {
            if #available(iOS 17.0, *) {
                mainChatView
            }

            // Error notification overlay
            if viewModel.showErrorNotification {
                errorNotificationView
            }
        }
        .mediaViewer(
            $viewModel.mediaViewerRequest,
            userName: user.name ?? "",
            translate: { key, args in
                viewModel.translationService?
                    .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
            },
            onDelete: { item, onlyMe in
                viewModel.deleteMediaItem(item, onlyMe: onlyMe)
            },
            transferOverlay: { item, onReady in
                // The bubble's own retry button, hosted over the page — same
                // component, same allowance, same behaviour as the bubble it
                // opened from.
                // Nothing to overlay when the file is already here: the grid is
                // guarded by the same question, but a viewer page is not, and
                // `MediaTransferButton` on a settled item reads as `.idle` — which
                // draws a download prompt over a photo that is already showing.
                guard let message = viewModel.mediaMessage(for: item.id),
                      message.mediaNeedsTransfer else { return nil }
                return AnyView(
                    MediaViewerTransferOverlay(
                        uploadVM: uploadViewModel,
                        message: message,
                        chatVM: viewModel,
                        onReady: onReady
                    )
                )
            },
            itemRefresher: { id in viewModel.refreshedViewerItem(for: id) }
        )
        .preferredColorScheme(appearanceStore.defaultAppearance.preferredColorScheme)
        .onAppear {
            appearanceStore.reloadFromPersistence()
            viewModel.syncChatAppearanceFromStore()
            // The view model may be a cached one built before we knew who the
            // peer was — a room opened from a shared contact card knows more
            // than a room opened from a bare phone number ever did.
            if !conversationType.isGroup {
                viewModel.adoptReceiverDetails(user)
            }
            viewModel.onAppear()
            // The upload view model is shared and long-lived; the room is not. Bind
            // the outcome hooks to whichever room is on screen so a transfer that
            // fails or recovers is written onto the message rather than living only
            // in the view model's in-memory dictionaries.
            //
            // Weakly: the upload view model outlives every room, so a strong
            // capture here would pin each room's view model in memory for the life
            // of the app.
            uploadViewModel.onTransferFailed = { [weak viewModel] code in
                viewModel?.setMediaTransferFailed(codeMessage: code, failed: true)
            }
            uploadViewModel.onTransferRecovered = { [weak viewModel] code, remoteURL in
                // An upload that landed clears the pending flag and publishes the
                // message; `clearPendingUpload` also clears the failure. A download
                // only ever clears the failure.
                if let remoteURL {
                    viewModel?.clearPendingUpload(codeMessage: code, remoteUrl: remoteURL)
                } else {
                    viewModel?.setMediaTransferFailed(codeMessage: code, failed: false)
                }
            }
            if conversationType.isGroup {
                viewModel.refreshGroupMembershipStatus()
            }
            globalAudioManager.setCurrentChatRoom(
                conversationId,
                messages: viewModel.messages
            )
        }
        .onDisappear {
            viewModel.onDisappear()
            globalAudioManager.clearCurrentChatRoom()
            globalAudioManager.clearCoordinatorCache()
        }
        .onChange(of: viewModel.messages) { newMessages in
            // Update messages in global manager for queue building
            globalAudioManager.setCurrentChatRoom(conversationId, messages: newMessages)
        }
        .onChange(of: viewModel.pendingStatusReplyCode) { code in
            guard let code else { return }
            Task {
                _ = await statusStore.presentSingleStatusSegment(codeStatus: code)
                await MainActor.run {
                    viewModel.pendingStatusReplyCode = nil
                }
            }
        }
    }
    
    // MARK: - Subviews

    @available(iOS 17.0, *)
    private var mainChatView: some View {
        VStack(spacing: 0) {
            chatHeaderBar
            messageListWithModifiers
        }
        .toolbar(.hidden, for: .tabBar)
        .chatAppearanceSheet(isPresented: $viewModel.showPhotoPicker, onDismiss: {
            guard let entry = pendingFinanceSelection else { return }
            pendingFinanceSelection = nil
            viewModel.onSelectFinanceEntry(entry)
        }) {
            photoPickerSheet
        }
        #if DEBUG
        // Échafaudage de capture d'écran — `waangu://chat/finance/{id}`.
        //
        // Le hub ne s'ouvre autrement qu'au doigt, depuis la feuille d'actions ;
        // sans ce raccourci la surface financière n'est pas observable en
        // automatisation. DEBUG seulement.
        .onReceive(NotificationCenter.default.publisher(for: .waanguDebugOpenFinanceHub)) { _ in
            viewModel.showsFinanceHome = true
        }
        .onAppear {
            // Le drapeau couvre le cas où la vue est reconstruite par le lien
            // lui-même : la notification part alors avant qu'il y ait un abonné.
            if DebugFinanceHubRequest.consume() {
                viewModel.showsFinanceHome = true
            }
            if DebugFinanceHubRequest.consumeActionSheet() {
                viewModel.showPhotoPicker = true
            }
            if DebugFinanceHubRequest.consumePublish() {
                // Référence fabriquée localement : elle ne désigne aucun objet
                // réel, et `objects.current(for:)` rendra donc une charge vide.
                // C'est précisément ce qu'on veut observer — la bulle telle
                // qu'elle s'affiche avant que le serveur ait projeté le montant.
                let reference = FinancialReference(
                    type: .payment,
                    id: "debug-bubble-" + UUID().lowercasedString,
                    version: 1,
                    correlationID: CorrelationId()
                )
                Task {
                    // Semer la projection **avant** de publier : la bulle lit
                    // `current(for:)` à sa création, et une graine posée après
                    // la laisserait sur « chargement » jusqu'au prochain
                    // rafraîchissement.
                    let store = naviagationCoord.feature.financialObjectStore
                    await store.beginSession()
                    _ = await store.applyLocalEcho(
                        FinancialCardPayload(
                            reference: reference,
                            // `processing` et non `completed` : une bulle qui
                            // s'affiche déjà réglée avant toute confirmation
                            // serveur serait exactement le faux succès que le
                            // §33 interdit.
                            status: .processing,
                            amount: 25_000,
                            currency: "BIF",
                            feeAmount: 375,
                            feeCurrency: "BIF",
                            counterpartyName: "Bénéficiaire test",
                            note: "Pour le déjeuner",
                            verification: .verified
                        )
                    )

                    _ = await viewModel.publishFinanceReference(
                        reference,
                        using: naviagationCoord.feature.publishFinanceMessage
                    )
                }
            }
            if let kind = DebugFinanceHubRequest.consumeEntry() {
                // Entrée minimale : seule sa `kind` compte pour choisir la
                // destination, le catalogue n'a pas à être consulté ici.
                viewModel.onSelectFinanceEntry(
                    FinanceCatalogEntry(
                        id: kind.rawValue.lowercased(),
                        kind: kind,
                        titleKey: "entry_" + kind.rawValue.lowercased(),
                        iconName: "circle",
                        isEnabled: true,
                        unavailableReasonKey: nil
                    )
                )
            }
        }
        #endif
        .chatAppearanceFullScreenCover(isPresented: financeEntryBinding) {
            FinanceNavigationScope {
                if viewModel.showsFinanceHome {
                    financeHome
                        .financeDestination(isPresented: financeTaskBinding) { financeEntrySheet }
                } else {
                    financeEntrySheet
                }
            }
            .environment(\.financeFlowSurface, viewModel.financeSurface)

            .environment(\.financeOperationKeys, viewModel.financeSurface?.operationKeys ?? .processLocal)
            .environment(\.financeObjectReader, naviagationCoord.feature.financialObjectUseCases)
        }
        .chatAppearanceFullScreenCover(isPresented: financialCardBinding) {
            financialCardSheet
                .environment(\.financeFlowSurface, viewModel.financeSurface)

                .environment(\.financeOperationKeys, viewModel.financeSurface?.operationKeys ?? .processLocal)
            .environment(\.financeObjectReader, naviagationCoord.feature.financialObjectUseCases)
        }
        // Payer une demande reçue — un devis, puis confirmation explicite (§4).
        .chatAppearanceFullScreenCover(isPresented: Binding(
            get: { viewModel.requestToPay != nil },
            set: { if !$0 { viewModel.requestToPay = nil } }
        )) {
            if let request = viewModel.requestToPay {
                PayMoneyRequestView(request: request, conversationID: viewModel.conversationId,
                                    onDismiss: { viewModel.requestToPay = nil })
                    .environment(\.financeFlowSurface, viewModel.financeSurface)
                    .environment(\.financeOperationKeys, viewModel.financeSurface?.operationKeys ?? .processLocal)
                    .environment(\.financeObjectReader, naviagationCoord.feature.financialObjectUseCases)
                    // Aucune bulle à part : c'est la carte de la demande qui passe
                    // à « Paiement envoyé » — voir `PayMoneyRequestView.requestChanged`.
                    .environment(\.financePublishReference, nil)
            }
        }
        .chatAppearanceDialog(
            isPresented: Binding(get: { viewModel.requestToDecline != nil },
                                 set: { if !$0 { viewModel.requestToDecline = nil } }),
            configuration: DialogConfiguration(
                title: FinanceStrings.requestDeclineTitle,
                message: FinanceStrings.requestDeclineDetail,
                style: .destructive,
                buttons: [
                    DialogButton(title: FinanceStrings.close, role: .primary) {},
                    // La demande est prise **ici**, à l'affichage : l'action ne
                    // joue qu'après la fermeture du dialogue, qui a déjà remis
                    // `requestToDecline` à nil — la relire alors ne trouvait rien,
                    // et aucun appel ne partait.
                    DialogButton(title: FinanceStrings.requestActionDecline, role: .destructive) {
                        [pending = viewModel.requestToDecline] in
                        guard let pending else { return }
                        Task { await viewModel.confirmDeclineRequest(pending) }
                    },
                ]
            )
        )
        .chatAppearanceDialog(
            isPresented: Binding(get: { viewModel.requestToCancel != nil },
                                 set: { if !$0 { viewModel.requestToCancel = nil } }),
            configuration: DialogConfiguration(
                title: FinanceStrings.requestCancelTitle,
                message: FinanceStrings.requestCancelDetail,
                style: .destructive,
                buttons: [
                    DialogButton(title: FinanceStrings.close, role: .primary) {},
                    // Même raison que pour le refus : capturée à l'affichage.
                    DialogButton(title: FinanceStrings.requestActionCancel, role: .destructive) {
                        [pending = viewModel.requestToCancel] in
                        guard let pending else { return }
                        Task { await viewModel.confirmCancelRequest(pending) }
                    },
                ]
            )
        )
        .chatAppearanceSheet(isPresented: Binding(get: { viewModel.issuedPaymentLink != nil },
                                                  set: { if !$0 { viewModel.issuedPaymentLink = nil } })) {
            if let link = viewModel.issuedPaymentLink {
                PaymentLinkIssuedSheet(link: link) { viewModel.issuedPaymentLink = nil }
            }
        }
        .chatAppearanceDialog(
            isPresented: Binding(get: { viewModel.requestNotice != nil },
                                 set: { if !$0 { viewModel.requestNotice = nil } }),
            configuration: .financeError(message: viewModel.requestNotice ?? "")
        )
        .chatAppearanceFullScreenCover(isPresented: $viewModel.showCameraCapture) {
            cameraCaptureCover
        }
        .chatAppearanceFullScreenCover(isPresented: viewOnceViewerBinding) {
            viewOnceViewer
        }
        .chatAppearanceSheet(isPresented: $viewModel.showVideoNoteRecorder) {
            VideoNoteRecorderSheet(
                translationService: viewModel.translationService,
                onRecorded: { url in viewModel.sendVideoNote(at: url) },
                onDismiss: { viewModel.showVideoNoteRecorder = false }
            )
        }
        .chatAppearanceFullScreenCover(isPresented: galleryEditorCoverBinding) {
            galleryEditorCover
        }
        .chatAppearanceSheet(isPresented: $viewModel.showDocumentPreview) {
            documentPreviewSheet
        }
        .chatAppearanceSheet(isPresented: $showChatSearch) {
            ChatInAppSearchView(viewModel: viewModel)
        }
        .chatAppearanceSheet(isPresented: $viewModel.showForwardMessagePicker) {
            ForwardMessagePicker(
                source: viewModel,
                statusStore: statusStore,
                contactsUseCases: contactUseCase,
                discussionUseCases: discussionUseCases,
                groupUseCases: viewModel.groupUseCasesForForwarding
            )
        }
        .chatAppearanceSheet(isPresented: $showAddParticipant) {
            AddParticipantSheet(
                existingPhones: viewModel.existingMemberPhones,
                onAdd: { contacts in
                    await viewModel.addMembers(contacts)
                },
                contactUseCase: contactUseCase,
                groupLocalId: viewModel.groupChat?.localId,
                groupServerId: viewModel.groupChat?.serverId,
                isAdmin: viewModel.isGroupAdmin,
                permissionsUseCases: groupPermissionsUseCases,
                translationService: viewModel.translationService
            )
        }
        .chatAppearanceSheet(isPresented: $showInviteLinkSheet) {
            GroupInviteLinkSheet(
                inviteLink: viewModel.groupInviteLink,
                hasInviteLink: viewModel.hasInviteLink,
                isLoading: $viewModel.isLoadingInviteLink,
                loadingMessage: viewModel.inviteLinkLoadingMessage,
                translationService: viewModel.translationService,
                onRegenerate: {
                    viewModel.regenerateInviteLink() 
                }
            ).onChange(of: viewModel.isLoadingInviteLink){ newValue in
                debugLog("🔗 onChange fired - isLoadingInviteLink changed to \(newValue) : \(viewModel.groupInviteLink)")
             
            }
           
        }
        .sheet(isPresented: $showRealtimeMonitor) {
            RealtimeMonitorView(chatViewModel: viewModel)
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { statusStore.showSingleSegmentViewer },
                set: { presented in
                    if !presented {
                        statusStore.closeSingleSegmentViewer()
                    } else {
                        statusStore.showSingleSegmentViewer = true
                    }
                }
            )
        ) {
            if let story = statusStore.singleSegmentViewerStory {
                DraggableFullScreenModal(
                    isPresented: Binding(
                        get: { statusStore.showSingleSegmentViewer },
                        set: { presented in
                            if !presented {
                                statusStore.closeSingleSegmentViewer()
                            }
                        }
                    ),
                    content: {
                        StatusViewer(
                            pinnedStory: story,
                            viewModel: statusStore,
                            updateTabCoordinator: updatesTabCoordinator,
                            translationService: viewModel.translationService
                        )
                    },
                    statusStore: statusStore,
                    onDismiss: { statusStore.closeSingleSegmentViewer() }
                )
                .background(Color.black)
                .ignoresSafeArea()
            }
        }
    }
    
    @available(iOS 17.0, *)
    private var messageListWithModifiers: some View {
        MessageListView(
            viewModel: viewModel,
            uploadVM: uploadViewModel,
            contactsUseCases: contactUseCase,
            opusPlaybackService: opusPlaybackService,
            navigationCoord: naviagationCoord,
            globalAudioPlaybackManager: globalAudioManager,
            onScrollDirectionChanged: { direction in
                debugLog("👀🔥 is scrolling vers \(direction)")
            },
            onGroupIntroAddMembers: {
                hideKeyboard()
                showAddParticipant = true
            },
            onGroupIntroInviteLink: {
                hideKeyboard()
                showInviteLinkSheet = true
            },
            onJoinRequestCheckpointTap: {
                hideKeyboard()
                let route: ChatsTabRoute = .pendingJoinRequests(
                    discussionId: conversationId,
                    groupName: viewModel.channel.name ?? ""
                )
                naviagationCoord.push(route)
            }
        )
        .onChange(of: viewModel.messages) { newValue in
            Task { @MainActor in
                await channelViewModel.updateDiscussions()
            }
        }
        .onChange(of: user) { _ in
            viewModel.updateChannel(user)
        }
        .onChange(of: viewModel.voiceRecordingVM.elapsedTime) { time in
            debugLog("👀🔥 voiceRecordingViewModel.elapsedTime \(time)")
        }
        .onChange(of: [waanguContacts, devicesContacts]) { _ in
            galleryViewModel.updateWaanguUsers(
                waanguUsers: waanguContacts,
                devicesContacts: devicesContacts
            )
        }
        .environmentObject(voiceMessagePlayer)
    }
    
    private var financialCardBinding: Binding<Bool> {
        Binding(
            get: { viewModel.presentedFinancialCard != nil },
            set: { if !$0 { viewModel.dismissFinancialCard() } }
        )
    }

    /// Les suites de la transaction portée par la carte touchée.
    @ViewBuilder
    private var financialCardSheet: some View {
        if let payload = viewModel.presentedFinancialCard, let surface = viewModel.financeSurface {
            FinancialObjectActionsView(
                payload: payload,
                surface: surface,
                conversationID: viewModel.conversationId,
                onDismiss: { viewModel.dismissFinancialCard() }
            )
        }
    }

    private var financeEntryBinding: Binding<Bool> {
        Binding(
            get: { viewModel.showsFinanceHome || viewModel.presentedFinanceEntry != nil },
            set: { if !$0 { closeFinanceHome() } }
        )
    }

    private var financeTaskBinding: Binding<Bool> {
        Binding(get: { viewModel.presentedFinanceEntry != nil },
                set: { if !$0 { viewModel.dismissFinanceEntry() } })
    }

    private func closeFinanceHome() {
        viewModel.dismissFinanceEntry()
        viewModel.showsFinanceHome = false
        // Les parcours ferment par `closeFinanceHome` quel que soit le chemin
        // par lequel ils ont été ouverts ; celui de la feuille doit donc se
        // refermer ici aussi, sans quoi il survivrait à sa propre fermeture.
        sheetFinanceEntry = nil
    }

    /// Le parcours financier ouvert depuis la feuille de pièces jointes.
    @State private var sheetFinanceEntry: FinanceCatalogEntry?

    private var financeHome: some View {
        Group {
            if let surface = viewModel.financeSurface {
                FinanceHomeView(
                    surface: surface,
                    context: viewModel.financeContext,
                    onSelect: { entry in
                        guard entry.isActionable() else { return }
                        viewModel.onSelectFinanceEntry(entry)
                    },
                    translationService: viewModel.translationService,
                    copilotHost: copilotHost,
                    copilotMessaging: copilotMessaging(),
                    // Une seule conversation Copilot, partout : celle de la liste.
                    copilotStore: naviagationCoord.feature.copilotConversationStore
                )
            } else {
                FinanceHubUnavailableView()
            }
        }
        .navigationTitle(FinanceStrings.hubTitle)
        .navigationBarTitleDisplayMode(.large)
        .financeTaskControls(onClose: closeFinanceHome)
    }

    @ViewBuilder
    private var financeEntrySheet: some View {
        if let entry = viewModel.presentedFinanceEntry, let surface = viewModel.financeSurface {
            // Les portes du §16 sont appliquées par `PaymentsDestination` elle-même.
            // Les reposer ici les ferait évaluer deux fois, avec deux indicateurs
            // d'attente successifs.
            financeDestination(entry, surface)
        }
    }

    /// Bénéficiaire de secours, DEBUG uniquement.
    private var debugRecipientInput: RecipientInput? {
        #if DEBUG
        guard let phone = DebugFinanceHubRequest.recipientOverride, !phone.isEmpty else { return nil }
        return .phoneNumber(phone)
        #else
        return nil
        #endif
    }

    @ViewBuilder
    /// Délègue à la table partagée — voir ``PaymentsDestination``.
    ///
    /// La conversation y ajoute les deux seules choses qu'elle est seule à
    /// avoir : un fil où publier la référence, et un interlocuteur.
    private func financeDestination(
        _ entry: FinanceCatalogEntry,
        _ surface: ChatFinanceSurface
    ) -> some View {
        PaymentsDestination(
            entry: entry,
            surface: surface,
            conversationID: viewModel.conversationId,
            recipientInput: viewModel.financeRecipientInput ?? debugRecipientInput,
            peerPhoneNumber: viewModel.peerPhoneNumber,
            recipientName: viewModel.peerName,
            peerChatUserID: viewModel.financePeerChatUserID,
            publishReference: { reference, note in
                await viewModel.publishFinanceReference(
                    reference,
                    note: note,
                    using: naviagationCoord.feature.publishFinanceMessage
                )
            },
            onDismiss: { closeFinanceHome() }
        )
    }

    /// Waangu Copilot ouvert depuis ce fil : l'interlocuteur, et l'annonce ici.
    private var copilotHost: CopilotConversationHost {
        CopilotConversationHost(
            conversationID: viewModel.conversationId,
            peer: viewModel.financeRecipientInput,
            peerName: viewModel.peerName,
            peerChatUserID: viewModel.financePeerChatUserID,
            receivedRequests: {
                var seen = Set<String>()
                return viewModel.messages
                    .filter { $0.direction == .received }
                    .compactMap { $0.message.financial?.reference }
                    .filter { $0.type == .moneyRequest && seen.insert($0.id).inserted }
            },
            publish: { reference, note in
                await viewModel.publishFinanceReference(
                    reference, note: note,
                    using: naviagationCoord.feature.publishFinanceMessage)
            })
    }

    /// Un autre contact que l'interlocuteur — ou tout contact dans un groupe —
    /// est payé dans son propre fil direct.
    private func copilotMessaging() -> WalletPaymentFlowViewModel {
        WalletPaymentFlowViewModel(
            discussions: naviagationCoord.feature.discussionUseCases,
            publisher: naviagationCoord.feature.publishFinanceMessage)
    }

    private var photoPickerSheet: some View {
        SheetActionView(
            onDismiss: {
                viewModel.closeChatActionsSheet()
            },
            onSendMedia: { caption in
                viewModel.closeChatActionsSheet()
                viewModel.onSendMedia(caption: caption, selectedMedia: mediaViewModel.selectedMedia)
                mediaViewModel.resetSelectedMedia()
            },
            onOpenMediaEditor: { media in
                viewModel.openGalleryMediaEditor(with: media)
            },
            onSendFiles: { urls in
                viewModel.closeChatActionsSheet()
                for url in urls {
                    viewModel.sendDocument(fileURL: url)
                }
            },
            onSendContacts: { contacts in
                viewModel.closeChatActionsSheet()
                viewModel.sendContactMessage(contacts: contacts)
            },
            onSendLocation: { location in
                viewModel.closeChatActionsSheet()
                viewModel.sendLocationMessage(location: location)
            },
            onSendPoll: { question, options, allowsMultipleAnswers in
                viewModel.closeChatActionsSheet()
                viewModel.sendPollMessage(
                    question: question,
                    options: options,
                    allowsMultipleAnswers: allowsMultipleAnswers
                )
            },
            financeSurface: viewModel.financeSurface,
            financeContext: viewModel.financeContext,
            onSelectFinanceEntry: { entry in
                // Keep the existing Wallet menu; open its selected task only
                // after the attachment sheet has actually finished dismissing.
                pendingFinanceSelection = entry
                viewModel.closeChatActionsSheet()
            },
            // Le parcours reste dans la feuille : c'est elle qui le présente,
            // avec la table de destinations de cette conversation.
            financeEntry: $sheetFinanceEntry,
            financeDestination: { entry in
                guard let surface = viewModel.financeSurface else { return AnyView(EmptyView()) }
                return AnyView(financeDestination(entry, surface))
            },
            conversationId: viewModel.conversationId,
            // L'onglet Waangu de la feuille : le même Copilot que l'accueil du fil.
            copilotHost: copilotHost,
            copilotMessaging: copilotMessaging(),
            copilotStore: naviagationCoord.feature.copilotConversationStore,
            loadRecentDocuments: {
                await viewModel.fetchRecentSentDocuments()
            },
            translationService: viewModel.translationService,
            galleryViewModel: galleryViewModel,
            mediaViewModel: mediaViewModel
        )
        .presentationDragIndicator(.hidden)
        .presentationDetents([.height(500), .large])
    }

    private var galleryEditorCoverBinding: Binding<Bool> {
        Binding(
            get: { viewModel.galleryEditorPreview != nil },
            set: { isPresented in
                if !isPresented {
                    viewModel.closeGalleryMediaEditor()
                }
            }
        )
    }

    @ViewBuilder
    private var galleryEditorCover: some View {
        if let preview = viewModel.galleryEditorPreview {
            ChatMediaEditorView(
                previewMedia: preview,
                recipientName: user.name ?? "",
                mediaCount: max(1, mediaViewModel.selectedMedia.count),
                translationService: viewModel.translationService,
                onSend: { caption, result in
                    viewModel.sendEditedMedia(result, caption: caption)
                    viewModel.closeGalleryMediaEditor()
                    mediaViewModel.resetSelectedMedia()
                },
                onDismiss: {
                    viewModel.closeGalleryMediaEditor()
                },
                onAddMoreMedia: {
                    viewModel.closeGalleryMediaEditor()
                    viewModel.showPhotoPicker = true
                },
                onSendViewOnce: { caption, result in
                    viewModel.sendEditedMedia(result, caption: caption, viewOnce: true)
                    viewModel.closeGalleryMediaEditor()
                    mediaViewModel.resetSelectedMedia()
                }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
        }
    }

    // MARK: - View once

    private var viewOnceViewerBinding: Binding<Bool> {
        Binding(
            get: { viewModel.viewOnceMessage != nil },
            set: { if !$0 { closeViewOnce() } }
        )
    }

    @ViewBuilder
    private var viewOnceViewer: some View {
        if let message = viewModel.viewOnceMessage {
            ViewOnceMessageViewer(
                translationService: viewModel.translationService,
                onClose: closeViewOnce
            ) {
                switch message.typeMessage {
                case .AUDIO, .VOICE:
                    BubbleVoiceView(
                        message: message,
                        uploadVM: uploadViewModel,
                        isSelectionMode: false,
                        opusPlaybackService: opusPlaybackService,
                        chatRoomId: viewModel.conversationId,
                        globalAudioManager: globalAudioManager,
                        chatVM: viewModel
                    )
                case .IMAGE, .VIDEO:
                    ViewOnceMediaPage(
                        message: message,
                        uploadVM: uploadViewModel,
                        translationService: viewModel.translationService
                    )
                default:
                    // Voice notes, photos and videos are the kinds that can be
                    // sent as view once.
                    EmptyView()
                }
            }
        }
    }

    /// The voice bubble keeps playing when it leaves the screen, by design for
    /// the thread; a view-once message must not outlive its viewer.
    private func closeViewOnce() {
        if let id = viewModel.viewOnceMessage?.id,
           globalAudioManager.currentlyPlayingAudio?.messageId == id {
            globalAudioManager.stop()
        }
        viewModel.closeViewOnce()
    }

    private var cameraCaptureCover: some View {
        ChatCameraFlowView(
            mediaViewModel: mediaViewModel,
            recipientName: user.name ?? "",
            translationService: viewModel.translationService,
            onSendGalleryMedia: { caption, media in
                viewModel.onUserCloseCamera()
                viewModel.onSendMedia(caption: caption, selectedMedia: [media])
                mediaViewModel.resetSelectedMedia()
            },
            onSendCapturedMedia: { caption, captured in
                viewModel.onUserCloseCamera()
                viewModel.sendCapturedMedia(captured, caption: caption)
                mediaViewModel.resetSelectedMedia()
            },
            onDismiss: {
                viewModel.onUserCloseCamera()
                mediaViewModel.resetSelectedMedia()
            },
            onSendViewOnce: { caption, result in
                viewModel.onUserCloseCamera()
                viewModel.sendEditedMedia(result, caption: caption, viewOnce: true)
                mediaViewModel.resetSelectedMedia()
            }
        )
    }
    
    private var documentPreviewSheet: some View {
        Group {
            if let url = viewModel.documentPreviewURL {
                DocumentPreviewSheet(url: url)
            }
        }
    }
    
    private var errorNotificationView: some View {
        VStack {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.white)
                Text(viewModel.errorNotificationMessage)
                    .foregroundColor(.white)
                    .font(.subheadline)
            }
            .padding()
            .background(Color.red.opacity(0.9))
            .cornerRadius(10)
            .shadow(radius: 10)
            .padding(.horizontal)
            Spacer()
        }
        .padding(.top, 50)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(), value: viewModel.showErrorNotification)
        .zIndex(999)
    }
}

// MARK: - Toolbar Items

//extension ChatRoomScreen {
//    @ToolbarContentBuilder
//    func leadingNavItems() -> some ToolbarContent {
//        ToolbarItemGroup(placement: .topBarLeading) {
//            HStack(spacing: 8) {
//                CircularProfileImageView(user.avatar ?? "", size: .xSmall)
//                    .foregroundColor(.black.opacity(0.5))
//
//                VStack(alignment: .leading) {
//                    Text(user.name ?? "")
//                        .bold()
//
//                    if let description = user.description, !description.isEmpty {
//                        Text(description)
//                            .font(.subheadline)
//                            .foregroundColor(.gray)
//                    }
//                }
//                .onTapGesture {
//                    print("this was about to open the profile")
////                    viewModel.coordinator.onNavBarActionPressed(.profile, dic: [:])
//                }
//            }
//        }
//    }
//
//    @ToolbarContentBuilder
//    func trailingNavItems() -> some ToolbarContent {
//        ToolbarItemGroup(placement: .topBarTrailing) {
//            if viewModel.messageAction == .delete || viewModel.messageAction == .forward {
//                Button("Cancel") {
//                    viewModel.messageAction = nil
//                }
//            } else {
//                Button {
////                    viewModel.coordinator.onNavBarActionPressed(.callVideo, dic: [:])
//                    print("this was about to open the Video call")
//                } label: {
//                    Image(systemName: "video")
//                        .foregroundColor(.black.opacity(0.7))
//                }
//
//                Button {
//                    print("this was about to open the audio Call")
////                    viewModel.coordinator.onNavBarActionPressed(.callAudio, dic: [:])
//                } label: {
//                    Image(systemName: "phone")
//                        .foregroundColor(.black.opacity(0.7))
//                }
//            }
//        }
//    }
//}

@available(iOS 16.0, *)
extension ChatRoomScreen {

    @ViewBuilder
    var chatHeaderBar: some View {
        HStack(spacing: 8) {
            if viewModel.messageAction == .delete {
                if conversationType.isGroup {
                    ZStack {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color.gray.opacity(0.2))
                            .frame(width: 50, height: 50)
                        
                        if let urlString = user.avatar, !urlString.isEmpty {
                            WebImage(url: URL(string: urlString))
                                .resizable()
            //                    .placeholder {
            //                        fallbackIcon(systemName: "person.3.fill")
            //                    }
                                .indicator(.activity)
                                .scaledToFill()
                                .frame(width: 50, height: 50)
                                .clipShape(RoundedRectangle(cornerRadius: 16))
                        } else {
                            HStack{
                                Image(systemName: "person.3.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 28, height: 28)
                                    .foregroundColor(.gray)
                                    .padding(8)
                                    .background(.gray.opacity(0.3))
                                    .clipShape(Circle())
                            }
                        }
                         
                        }
                    
                }else {
                    if !conversationType.isGroup {
                        CircularProfileImageView(user.avatar ?? "", size: .xSmall)
                            .foregroundStyle(.secondary)
                    }else{
                        HStack{
                            Image(systemName: "person.3.fill")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 28, height: 28)
                                .foregroundColor(.gray)
                                .padding(8)
                                .background(.gray.opacity(0.3))
                                .clipShape(Circle())
                        }
                    }
                    
                }
               

                Text(headerDisplayName)
                    .font(.headline)
                    .lineLimit(1)

                Spacer()

                Button("Cancel") {
                    viewModel.exitSelectionMode()
                }

                Button(action: {
                    showDeleteConfirmation = true
                }) {
                    Text("Delete")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.red)
                }
                .confirmationDialog(
                    "Delete \(viewModel.selectedMessages?.count ?? 0) message\(viewModel.selectedMessages?.count ?? 0 > 1 ? "s" : "")?",
                    isPresented: $showDeleteConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Delete for Me", role: .destructive) {
                        viewModel.deleteMessages(onlyMe: true)
                    }
                    if viewModel.selectedMessages?.allSatisfy({ $0.isSentByMe }) == true {
                        Button("Delete for Everyone", role: .destructive) {
                            viewModel.deleteMessages(onlyMe: false)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            } else {
                Button {
                    hideKeyboard()
                    viewModel.cancelMessageEdit()
                    naviagationCoord.clearChatRoomViewModelCache()
                    naviagationCoord.popToRoot()
                } label: {
                    Image(systemName: "chevron.backward")
                        .foregroundStyle(.primary)
                }

                HStack(alignment: .center, spacing: 8) {
                    if conversationType.isGroup {
                        // The group's picture, not a fixed icon: this branch used to
                        // draw `person.3.fill` unconditionally, so a group with an
                        // avatar showed one everywhere except the room it opens.
                        // `onClick` stays nil so the surrounding tap gesture — which
                        // opens group info — keeps receiving the tap.
                        GroupAwareAvatarView(
                            imageUrl: user.avatar,
                            isGroup: true,
                            size: .xSmall
                        )
                    }else{
                        CircularProfileImageView(user.avatar ?? "", size: .xSmall)
                            .foregroundStyle(.secondary)
                    }
                   

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(headerDisplayName)
                                .font(.headline)
                                .lineLimit(1)

                            LiveRealtimeHeartbeatIndicator(
                                monitor: viewModel.heartbeatMonitor
                            )
                            .contentShape(Rectangle())
                            .onTapGesture {
                                hideKeyboard()
                                showRealtimeMonitor = true
                            }
                        }

                        // Nothing at all when presence is unknown — the header
                        // used to fill the gap with an invented "last seen".
                        if let presence = headerPresenceText {
                            Text(presence)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    hideKeyboard()
                    if conversationType.isGroup {
                        let route: ChatsTabRoute = .groupInfoView(
                            discussionId: self.conversationId,
                            groupName: user.name ?? ""
                        )
                        naviagationCoord.push(route)
                    } else {
                        let route: ChatsTabRoute = .profileView(
                            contactId: user.idContact,
                            discussionId: self.conversationId,
                            fallbackPhone: user.phone,
                            fallbackDisplayName: user.name.flatMap { $0.isEmpty ? nil : $0 },
                            isBlocked: viewModel.currentReceiverUser?.isBlocked ?? false
                        )
                        naviagationCoord.push(route)
                    }
                }

                Spacer()

//                if #available(iOS 17.0, *) {
//                    Button {
//                        showChatSearch = true
//                    } label: {
//                        Image(systemName: "magnifyingglass")
//                            .foregroundColor(Color.black.opacity(0.7))
//                    }
//                }

                if enabledModules.contains(.calls) {
                    Button {
                        hideKeyboard()
                        if conversationType.isGroup {
                            let invitees = groupCallInvitees
                            guard !invitees.isEmpty else { return }
                            VoipManager.shared.startGroupCall(
                                invitees,
                                hasVideo: true,
                                conversationId: self.conversationId,
                                groupName: user.name
                            )
                        } else {
                            VoipManager.shared.startOutgoingCall(
                                to: user.phone ?? "",
                                hasVideo: true,
                                name: user.name,
                                image: user.avatar,
                                conversationId: self.conversationId,
                                userId: user.userId
                            )
                        }
                    } label: {
                        Image(systemName: "video")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    Spacer().frame(width: 8)
                    Button {
                        hideKeyboard()
                        if conversationType.isGroup {
                            let invitees = groupCallInvitees
                            guard !invitees.isEmpty else { return }
                            VoipManager.shared.startGroupCall(
                                invitees,
                                hasVideo: false,
                                conversationId: self.conversationId,
                                groupName: user.name
                            )
                        } else {
                            VoipManager.shared.startOutgoingCall(
                                to: user.phone ?? "",
                                hasVideo: false,
                                name: user.name,
                                image: user.avatar,
                                conversationId: self.conversationId,
                                userId: user.userId
                            )
                        }
                    } label: {
                        Image(systemName: "phone")
                            .font(.system(size: 20))
                            .foregroundStyle(.primary)
                    }
                    Spacer().frame(width: 8)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .top)
        }
        .animation(.easeInOut(duration: 0.3), value: viewModel.messageAction)
    }
    
    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
    
    private func common(_ key: String) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }

    /// Active group members except this device — maps directly to call invitees,
    /// capped at the room limit. Only valid when conversationType.isGroup.
    private var groupCallInvitees: [CallInvitee] {
        let selfId = CurrentSessionInfo.shared.currentUid
        let selfPhone = CurrentSessionInfo.shared.userPhoneNumber
        return (viewModel.groupChat?.members ?? [])
            .filter { $0.isActive && $0.userId != selfId && $0.phone != selfPhone }
            .prefix(VoipManager.maxParticipants)
            .map { CallInvitee(userId: $0.userId, name: $0.name, phone: $0.phone) }
    }
}

// MARK: - Image Preview View (unchanged from original)

struct ImagePreviewView: View {
    let imageName: String
    let sourceRect: CGRect
    let onDismiss: () -> Void
    let translationService: (any TranslationServiceProtocol)? = nil
    
    @State private var backgroundOpacity: Double = 0
    @State private var zoomed: Bool = false

    
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.black
                    .ignoresSafeArea()
                    .opacity(backgroundOpacity)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                            zoomed = false
                            backgroundOpacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                            onDismiss()
                        }
                    }
                
                Image(imageName) // Or use WebImage if it's a URL
                    .resizable()
                    .aspectRatio(contentMode: zoomed ? .fit : .fill)
                    .frame(
                        width: zoomed ? proxy.size.width : sourceRect.width,
                        height: zoomed ? proxy.size.height : sourceRect.height
                    )
                    .clipped()
                    .position(
                        x: zoomed ? proxy.size.width / 2 : sourceRect.minX - proxy.frame(in: .global).minX + sourceRect.width / 2,
                        y: zoomed ? proxy.size.height / 2 : sourceRect.minY - proxy.frame(in: .global).minY + sourceRect.height / 2
                    )
            }
            .onAppear {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                    zoomed = true
                    backgroundOpacity = 0.9
                }
            }
        }
        .ignoresSafeArea()
    }
}



#if DEBUG
/// Demande d'ouverture du hub, franchissant la frontière de module.
///
/// Un drapeau statique plutôt qu'un paramètre de navigation : c'est un
/// échafaudage de capture d'écran, et il ne doit pas s'inscrire dans un contrat
/// que du code de production finirait par lire.
public enum DebugFinanceHubRequest {

    nonisolated(unsafe) public static var pending = false

    /// Parcours à ouvrir directement, sans passer par le hub.
    ///
    /// Le pilotage tactile ne fonctionne pas dans toutes les sessions ; sans ce
    /// raccourci, aucun écran situé après le hub n'est observable.
    nonisolated(unsafe) public static var pendingEntry: FinanceEntryKind?

    /// Bénéficiaire imposé, pour exercer un parcours 1:1 depuis un fil de groupe.
    ///
    /// **Ne contourne pas la règle métier** : `financeRecipientInput` rend `nil`
    /// en groupe parce que l'envoi multi-destinataires n'est pas écrit, et cela
    /// reste vrai. Ce champ ne sert qu'à fournir un destinataire là où le seul
    /// fil de la base de test est un groupe — sans lui, aucun écran d'envoi
    /// n'est observable du tout.
    nonisolated(unsafe) public static var recipientOverride: String?

    /// Ouvre la feuille d'actions elle-même.
    ///
    /// Le fil de test est un groupe **quitté** : la barre de saisie est absente,
    /// donc le « + » qui ouvre la feuille n'existe pas à l'écran. Sans ce
    /// drapeau, la feuille d'actions n'est pas atteignable du tout.
    nonisolated(unsafe) public static var pendingActionSheet = false

    /// Publie une référence financière dans la conversation.
    ///
    /// Le seul chemin normal vers une bulle financière est d'aller au bout d'un
    /// virement, ce qui suppose de saisir un montant — impossible en
    /// automatisation ici. Sans ce raccourci, la bulle n'est observable par
    /// personne.
    nonisolated(unsafe) public static var pendingPublish = false

    public static func consumePublish() -> Bool {
        guard pendingPublish else { return false }
        pendingPublish = false
        return true
    }

    public static func consumeActionSheet() -> Bool {
        guard pendingActionSheet else { return false }
        pendingActionSheet = false
        return true
    }

    /// Rend `true` une seule fois, puis se désarme — sans quoi chaque
    /// réapparition de la conversation rouvrirait la feuille.
    public static func consume() -> Bool {
        guard pending else { return false }
        pending = false
        return true
    }

    /// Même règle, pour le parcours direct.
    public static func consumeEntry() -> FinanceEntryKind? {
        defer { pendingEntry = nil }
        return pendingEntry
    }
}

extension Notification.Name {

    /// Demande d'ouverture du hub financier — échafaudage de capture d'écran.
    ///
    /// Déclarée ici **et** dans l'AppTarget : `FeatureChat` ne voit pas
    /// l'AppTarget, et une notification n'a besoin que d'un nom identique des
    /// deux côtés. La chaîne est donc la seule chose partagée.
    static let waanguDebugOpenFinanceHub = Notification.Name("waangu.debug.openFinanceHub")
}
#endif



