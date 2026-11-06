//
//  ContactProfileViewModel.swift
//  Pods
//
//  Created by Asyst on 8/30/25.
//
import Combine
import Foundation
import WaanguCoreKit

final class ContactProfileViewModel: ObservableObject {

    @Published var linksMessages: [MessageDataItem] = []
    @Published var documentMessages: [MessageDataItem] = []
    @Published var mediaMessages: [MessageDataItem] = []
    @Published var user: UserContactProps?
    @Published var totalMedia: Int = 0
    @Published var disappearingDuration: DisappearingDuration = .off
    @Published var isMuted: Bool = false
    @Published var cachedImagesData: [CachedMediaItem] = []

    private let discussionId: String
    private var messagesUseCases: MessagesUseCasesProtocol
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let contactsUseCases: ContactsUseCasesProtocol?
    private let conversationRoomUseCases: ConversationRoomUseCasesProtocol?
    private let translationService: (any TranslationServiceProtocol)?
    private var cancellables = Set<AnyCancellable>()

    /// Title for headers: name, then number, then a translated "Unknown user".
    ///
    /// The two hardcoded "Unknown"s this replaces stayed English in every
    /// language, and neither of them screened out an account id arriving as a
    /// name.
    var displayTitle: String {
        ChatDisplayName.text(
            name: user?.name,
            phone: user?.phone,
            identifiers: [user?.userId ?? "", user?.idContact ?? "", discussionId],
            translator: translationService
        )
    }

    init(
        discussionId: String,
        user: UserContactProps?,
        discussionUseCases: DiscussionUseCasesProtocol,
        messagesUseCases: MessagesUseCasesProtocol,
        contactsUseCases: ContactsUseCasesProtocol? = nil,
        conversationRoomUseCases: ConversationRoomUseCasesProtocol? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.translationService = translationService
        self.discussionId = discussionId
        self.discussionUseCases = discussionUseCases
        self.messagesUseCases = messagesUseCases
        self.contactsUseCases = contactsUseCases
        self.conversationRoomUseCases = conversationRoomUseCases

        self.user = user
        reloadDisappearingFromStore()
        reloadMuteFromStore()
        observeBlockStatusChanges()

        Task { @MainActor in
            do {
                let messages = try await discussionUseCases.getMessages.execute(conversationId: discussionId) ?? []
                debugLog("👀 message count : \(messages.count)")
                self.groupMessages(messages)
            } catch {
                debugLog("❌❌ error occur while getting discussion :  \(error)")
            }
        }
    }

    func onUpdateNewMessages(_ messages: [MessageDataItem]) {
        self.groupMessages(messages)
    }

    func groupMessages(_ messages: [MessageDataItem]) {
        self.documentMessages = messages.filter { $0.typeMessage == .DOCUMENT }
        self.mediaMessages = messages.filter {
            ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce
        }

        self.linksMessages = messages.filter { msg in
            if let s = msg.message.url?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
                return true
            }
            return LinkPreviewProvider.extractFirstURL(from: msg.message.text) != nil
        }

        self.totalMedia = self.mediaMessages.count + self.linksMessages.count + self.documentMessages.count
    }

    func reloadDisappearingFromStore() {
        Task { @MainActor in
            guard let list = try? await discussionUseCases.getDiscussions.execute(),
                  let item = list.first(where: { $0.conversationId == discussionId }),
                  let secs = item.setting?.ephemeralMessageDuration,
                  secs > 0,
                  let d = DisappearingDuration(rawValue: secs) else {
                disappearingDuration = .off
                return
            }
            disappearingDuration = d
        }
    }

    func setDisappearingMessages(_ duration: DisappearingDuration) async throws {
        guard let list = try await discussionUseCases.getDiscussions.execute(),
              let idx = list.firstIndex(where: { $0.conversationId == discussionId }) else {
            disappearingDuration = duration
            return
        }

        var item = list[idx]
        var s = item.setting ?? UserConversationSetting()
        s.conversation = discussionId
        s.ephemeralMessageDuration = duration == .off ? 0 : duration.rawValue
        s.ephemeralStartAt = duration == .off ? nil : Date()
        s.ephemeralEndAt = nil
        s.updatedAt = Date()
        item.setting = s

        try await discussionUseCases.updateDiscussionSetting.execute(discussion: item)
        disappearingDuration = duration
    }

    func reloadMuteFromStore() {
        Task { @MainActor in
            guard let list = try? await discussionUseCases.getDiscussions.execute(),
                  let item = list.first(where: { $0.conversationId == discussionId }) else {
                isMuted = false
                return
            }
            isMuted = item.setting?.isMuted == true
        }
    }

    func setMuted(_ muted: Bool) async throws {
        guard let list = try await discussionUseCases.getDiscussions.execute(),
              let idx = list.firstIndex(where: { $0.conversationId == discussionId }) else {
            isMuted = muted
            return
        }

        var item = list[idx]
        var s = item.setting ?? UserConversationSetting()
        s.conversation = discussionId
        s.isMuted = muted
        s.muteStartAt = muted ? Date() : nil
        s.muteEndAt = muted ? nil : nil
        s.updatedAt = Date()
        item.setting = s

        try await discussionUseCases.updateDiscussionSetting.execute(discussion: item)
        isMuted = muted
        NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
    }

    func deleteMessages(onlyMe: Bool, message: MessageDataItem) {
        Task { @MainActor in
            do {
                let forEveryone = !onlyMe && message.isSentByMe
                let isUnsent = message.status == .PENDING || message.status == .FAILED
                let effectiveForEveryone = forEveryone && !isUnsent

                try await messagesUseCases.deleteMessages.execute(
                    messageId: message.codeMessage,
                    forEveryone: effectiveForEveryone
                )
                ChatRoomMessageMediaCleanup.deleteMediaFiles(for: message)

                if let index = self.mediaMessages.firstIndex(where: { $0.id == message.id }) {
                    self.mediaMessages.remove(at: index)
                    if index < self.cachedImagesData.count {
                        self.cachedImagesData.remove(at: index)
                    }
                    self.totalMedia = self.mediaMessages.count + self.linksMessages.count + self.documentMessages.count
                }

                if !isUnsent {
                    await notifyMessageDeleted(message, forEveryone: effectiveForEveryone)
                }
                NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
            } catch {
                debugLog("error occur while deleting message  \(error)")
            }
        }
    }

    func notifyMessageDeleted(_ message: MessageDataItem, forEveryone: Bool) async {
        if message.status == .PENDING || message.status == .FAILED {
            return
        }
        let effectiveForEveryone = forEveryone && message.isSentByMe
        await conversationRoomUseCases?.publishDeleteMessage.execute(
            codeMessage: message.codeMessage,
            conversationId: discussionId,
            forEveryone: effectiveForEveryone
        )
    }
    
    // MARK: - Observe Block Status Changes
    
    private func observeBlockStatusChanges() {
        NotificationCenter.default.publisher(for: .contactBlockStatusChanged)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] notification in
                guard let self,
                      let userInfo = notification.userInfo,
                      let contactId = userInfo["contactId"] as? String,
                      let isBlocked = userInfo["isBlocked"] as? Bool,
                      contactId == self.user?.idContact else { return }
                
                self.user?.isBlocked = isBlocked
            }
            .store(in: &cancellables)
    }
    
    // MARK: - Block/Unblock Contact
    
    @Published var isBlockingContact: Bool = false
    @Published var blockError: String?
    
    func toggleBlockContact() async {
        guard let contactsUseCases = contactsUseCases,
              let user = user,
              !user.phone.isEmpty else {
            await MainActor.run {
                blockError = ChatErrorStrings.blockMissingContact
            }
            return
        }
        
        await MainActor.run {
            isBlockingContact = true
            blockError = nil
        }
        
        do {
            let newBlockedState = !(user.isBlocked ?? false)
            try await contactsUseCases.toggleBlockContact.execute(
                contactId: user.id,
                blocked: newBlockedState
            )
            
            await MainActor.run {
                self.user?.isBlocked = newBlockedState
                isBlockingContact = false
                
                // Notify ChatRoomViewModel about the block status change
                NotificationCenter.default.post(
                    name: .contactBlockStatusChanged,
                    object: nil,
                    userInfo: [
                        "contactId": user.idContact,
                        "isBlocked": newBlockedState
                    ]
                )
                
                // Notify that discussions should refresh to update blocked state
                NotificationCenter.default.post(name: .discussionsShouldRefresh, object: nil)
            }
        } catch {
            await MainActor.run {
                blockError = error.localizedDescription
                isBlockingContact = false
            }
        }
    }
}
