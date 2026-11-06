import Foundation
import Combine
import SwiftUI
import WaanguCoreKit

@available(iOS 16.0, *)
@MainActor
public class StoriesViewModel: ObservableObject {
    @Published var ownStatus: Status? = nil
    @Published var contactStatus: [Status] = []
    @Published var lastSyncDate: Date?
    @Published var selectedStatusId: String?
    @Published var currentUser: String = ""
    @Published var isLoading = false
    @Published var error: String?
    /// Row currently waiting for delete API confirmation — kept in UI until success.
    @Published var deletingStatusId: String?
    @Published var showDeleteErrorAlert = false
    @Published var deleteErrorMessage: String?
    @Published var currentStory = ""
    @Published var navigateToStatusViewer : Bool = false
    @Published var showSingleSegmentViewer = false
    @Published private(set) var singleSegmentViewerStory: Status?
    @Published var isSlidingToBottom : Bool = false
    /// True while the contact TabView is mid-swipe (3D tilt active).
    @Published var isPagingContacts: Bool = false
    /// Live drag-down offset while dismissing the status fullScreenCover.
    @Published var statusViewerDragOffset: CGFloat = 0
    @Published var navigateToViewMyStories : Bool = false
    @Published var isFirstPageStory : Bool = true
    @Published var selectedMedia : [GalleryMedia] = []
    @Published var mediaItems : [MediaAssetUI] = []
    @Published var hasLoadedInitialData: Bool = false
    /// Bumped when status media is written to disk so strip previews refresh without a full reload.
    @Published var mediaCacheRevision: Int = 0
    
    // new
    @Published var images: [GalleryImage] = []
    @Published var selectedImages: [GalleryImage] = []
    @Published var currentOverlayImage: GalleryImage?
    @Published var albums: [PhotoAlbum] = []
    @Published var selectedAlbum: PhotoAlbum?
    
 
    
    let videoTrimCache = VideoTrimCacheStore()

    var videoCache: [String: CachedVideoData] {
        get { videoTrimCache.cache }
        set { videoTrimCache.cache = newValue }
    }
    
    private var loadTask: Task<Void, Never>?
    private var refreshDebounceTask: Task<Void, Never>?
    
  
    
    
    private var statusChanged: Bool = false {
        didSet {
            
        }
    }
    
    
    //Testing
    @Published var isDocSent = false
    
    // MARK: SQLLITE USECASES
//    private let statusUseCases: StatusUseCases
    private var cancellables = Set<AnyCancellable>()
    // MARK: COREDATA USECASES
    private let statusUseCases: StatusUseCases
    private let phMediaManager: PHMediaManagerProtocol
    private let conversationRoomUseCases: ConversationRoomUseCasesProtocol?
    private let discussionUseCases: DiscussionUseCasesProtocol?
    private let contactsUseCases: ContactsUseCasesProtocol?
    
    
    public init(
        statusUseCases: StatusUseCases,
        phMediaManager: PHMediaManagerProtocol,
        conversationRoomUseCases: ConversationRoomUseCasesProtocol? = nil,
        discussionUseCases: DiscussionUseCasesProtocol? = nil,
        contactsUseCases: ContactsUseCasesProtocol? = nil
    ) {
        self.statusUseCases = statusUseCases
        self.phMediaManager = phMediaManager
        self.conversationRoomUseCases = conversationRoomUseCases
        self.discussionUseCases = discussionUseCases
        self.contactsUseCases = contactsUseCases
         loadInitialData()
        // Subscribe to changes — always go through one debounced reload path so
        // live MQTT inserts can't race with onAppear/getStatusFn while the strip is visible.
        statusUseCases.statusUpdatedPublisher
                   .receive(on: DispatchQueue.main)
                   .sink { [weak self] _ in
                       self?.scheduleStatusesRefresh()
                   }
                   .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusesShouldRefresh)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.scheduleStatusesRefresh()
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: .statusMediaCached)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.notifyStatusMediaCached()
            }
            .store(in: &cancellables)
    }
    
//    deinit {
//        self.selectedMedia.removeAll()
//        
//    }
    
    // MARK: navigation

    func openMyStatusList(coord:UpdatesTabCoordinator){
        // Never leave a contact StoryViewer cover sitting under My Status.
        if navigateToStatusViewer {
            closeStatusViewer()
        }
        currentStory = ""
        coord.push(UpdatesTabRoute.myStoriesView)
        withAnimation(.easeInOut) {
            self.isFirstPageStory = false
        }
    }
    func closeStatusViewer() {
        navigateToStatusViewer = false
        isFirstPageStory = true
        isSlidingToBottom = false
        isPagingContacts = false
        statusViewerDragOffset = 0
    }

    func closeSingleSegmentViewer() {
        showSingleSegmentViewer = false
        singleSegmentViewerStory = nil
        isSlidingToBottom = false
        isPagingContacts = false
        statusViewerDragOffset = 0
    }

    /// Opens one status segment from chat reply preview (fullscreen, auto-dismiss when duration ends).
    @discardableResult
    func presentSingleStatusSegment(codeStatus: String) async -> Bool {
        guard let item = await resolveStatusItem(codeStatus: codeStatus),
              !isStatusSegmentExpired(item) else {
            return false
        }

        if navigateToStatusViewer {
            closeStatusViewer()
        }

        singleSegmentViewerStory = Status(
            userId: item.userId,
            userName: item.userName,
            userImage: item.userImage,
            lastStatusTime: item.lastStatusTime ?? item.createdAt,
            viewed: item.viewed,
            currentIndex: 0,
            status: [item]
        )
        showSingleSegmentViewer = true
        return true
    }

    private func resolveStatusItem(codeStatus: String) async -> StatusItem? {
        if let item = try? await statusUseCases.getOwnStatus.execute(
            userId: CurrentSessionInfo.shared.currentUid
        )?.status.first(where: { $0.codeStatus == codeStatus }) {
            return item
        }

        if let contacts = try? await statusUseCases.getContactStatuses.execute() {
            for contact in contacts {
                if let item = contact.status.first(where: { $0.codeStatus == codeStatus }) {
                    return item
                }
            }
        }

        if let own = ownStatus?.status.first(where: { $0.codeStatus == codeStatus }) {
            return own
        }
        for contact in contactStatus {
            if let item = contact.status.first(where: { $0.codeStatus == codeStatus }) {
                return item
            }
        }

        if let item = try? await statusUseCases.getStatusItemByCode.execute(codeStatus: codeStatus) {
            return item
        }
        return nil
    }

    private func isStatusSegmentExpired(_ item: StatusItem) -> Bool {
        if let expiresAt = item.expiresAt, expiresAt <= Date() { return true }
        return !item.isActive
    }

    func setPagingContacts(_ paging: Bool) {
        guard isPagingContacts != paging else { return }
        // Preference updates can land during view updates.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isPagingContacts != paging else { return }
            self.isPagingContacts = paging
        }
    }

    /// Safe to call from UIKit gesture callbacks — avoids
    /// "Publishing changes from within view updates".
    private var pendingDragOffset: CGFloat?
    private var pendingDragSliding: Bool?
    private var dragPublishScheduled = false

    func setStatusViewerDragOffset(_ offset: CGFloat, sliding: Bool? = nil) {
        pendingDragOffset = max(0, offset)
        if let sliding {
            pendingDragSliding = sliding
        }
        guard !dragPublishScheduled else { return }
        dragPublishScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dragPublishScheduled = false
            if let sliding = self.pendingDragSliding, self.isSlidingToBottom != sliding {
                self.isSlidingToBottom = sliding
            }
            self.pendingDragSliding = nil
            if let offset = self.pendingDragOffset, self.statusViewerDragOffset != offset {
                self.statusViewerDragOffset = offset
            }
            self.pendingDragOffset = nil
        }
    }

    func resetStatusViewerDrag(animated: Bool = false) {
        pendingDragOffset = nil
        pendingDragSliding = nil
        dragPublishScheduled = false
        let apply = { [weak self] in
            guard let self else { return }
            self.statusViewerDragOffset = 0
            self.isSlidingToBottom = false
        }
        DispatchQueue.main.async {
            if animated {
                withAnimation(.interactiveSpring(response: 0.32, dampingFraction: 0.86, blendDuration: 0.15)) {
                    apply()
                }
            } else {
                apply()
            }
        }
    }

    func finishStatusViewerDragDismiss(screenHeight: CGFloat) {
        pendingDragOffset = nil
        pendingDragSliding = nil
        dragPublishScheduled = false
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            withAnimation(.easeOut(duration: 0.28)) {
                self.statusViewerDragOffset = screenHeight
                self.isFirstPageStory = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { [weak self] in
                self?.closeStatusViewer()
            }
        }
    }

    func goBack(coord:UpdatesTabCoordinator){
        if navigateToStatusViewer {
            closeStatusViewer()
            return
        }
        coord.pop()
        withAnimation(.easeInOut) {
            self.isFirstPageStory = false
        }
    }
    func goBacktoRoot(coord:UpdatesTabCoordinator){
        if navigateToStatusViewer {
            closeStatusViewer()
            return
        }
        coord.popToRoot()
        withAnimation(.easeInOut) {
            self.isFirstPageStory = true
        }
    }
    func openCamera(coord:UpdatesTabCoordinator){
        
        coord.push(UpdatesTabRoute.editTabStoryView(initialTab: .photo))
        withAnimation(.easeInOut) {
            self.isFirstPageStory = false
        }
    }
    func openTextEditor(coord:UpdatesTabCoordinator){
      
        coord.push(UpdatesTabRoute.editTabStoryView(initialTab: .text))
        withAnimation(.easeInOut) {
            self.isFirstPageStory = false
        }

    }
    
    func openStatusEditor(coord:UpdatesTabCoordinator){
        coord.push(UpdatesTabRoute.statusEditorView(selectedMedia: selectedMedia))
        withAnimation(.easeInOut) {
            self.isFirstPageStory = false
        }
    }
    func viewStatus(coord:UpdatesTabCoordinator,storyId:String){
        // Contact statuses: system fullScreenCover + drag-to-dismiss.
        // Own status: NavigationStack push (StatusViewer for ownStatus, not in StoryViewer pages).
        if isOwnStatus(userId: storyId) {
            // Never open the contact pager for the current user.
            // Keep any explicit `currentIndex` set by My Status list.
            if navigateToStatusViewer {
                closeStatusViewer()
            }
            currentStory = ""
            coord.push(UpdatesTabRoute.storieView(storyId: storyId))
            withAnimation(.easeInOut) {
                isFirstPageStory = false
            }
            return
        }

        // Resume at first unviewed segment (WhatsApp-style).
        if let idx = contactStatus.firstIndex(where: { $0.id == storyId || $0.userId == storyId }) {
            contactStatus[idx].applyResumeIndex()
        }

        currentStory = storyId
        isFirstPageStory = false
        navigateToStatusViewer = true
    }
    
    // MARK: - Actions
    
    @Published var syncInProgress: Bool = false
    
    func isOwnStatus(userId:String) -> Bool {
        let trimmed = userId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let sessionUid = CurrentSessionInfo.shared.currentUid
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if !sessionUid.isEmpty, trimmed == sessionUid {
            return true
        }

        // Fallback when session uid is briefly unavailable but own thread is loaded.
        if let ownId = ownStatus?.userId.trimmingCharacters(in: .whitespacesAndNewlines),
           !ownId.isEmpty,
           trimmed == ownId {
            return true
        }

        return ownStatus?.status.contains(where: { $0.userId == trimmed || $0.id == trimmed || $0.codeStatus == trimmed }) == true
    }
    
    
    
    func loadMedia(album: MediaAlbum?, limit: Int = 80) {
            isLoading = true

            Task {
                let assets = phMediaManager.fetchMedia(from: album, limit: limit)

                // Build list by accumulating the return value from each loadThumbnail call
                var output: [MediaAssetUI] = []
                for asset in assets {
                    output = await loadThumbnail(for: asset, list: output)
                }
                self.mediaItems = output
                self.isLoading = false
            }
        }
     
    func retryFailedSyncs(statusId:String) async {
         syncInProgress = true
         defer { syncInProgress = false }
         
         do {
             try await statusUseCases.retryFailedStatusUseCase.execute(statusId: statusId)
             await loadOwnStatus()
         } catch {
             self.error = "❌Erreur lors des retentatives: \(error.localizedDescription)"
         }
     }

    /// Called on MyStatusView.onAppear — resumes any items that are stuck in
    /// .pending or .retrying (app killed mid-upload) or .failed.
    /// Routes each item correctly:
    ///   - not yet uploaded → CDRetryFailedUploadUseCase (re-upload then post)
    ///   - uploaded but not posted → retryFailedSyncs (post only)
    func resumePendingStatuses() async {
        guard !syncInProgress else { return }
        syncInProgress = true
        defer { syncInProgress = false }

        guard let ownStatus = ownStatus else { return }

        for item in ownStatus.status {
            switch item.syncStatus {
            case .synced:
                continue
            case .pending, .retrying, .syncing, .failed:
                if item.type != .text && !item.uploaded {
                    await statusUseCases.retryFailedUploadStatusUseCase.execute(statusItemId: item.codeStatus)
                } else {
                    try? await statusUseCases.retryFailedStatusUseCase.execute(statusId: item.codeStatus)
                }
            }
        }
        await loadOwnStatus()
    }
    
    func deleteOwnStatusItem(statusItem: String, syncStatus: SyncStatus, codeStatus: String) async {
        guard deletingStatusId == nil else { return }

        deletingStatusId = statusItem
        // Let SwiftUI paint the deleting state before the network/DB work starts.
        await Task.yield()

        do {
            // Keep the item in state until the server (or local DB for unsynced) confirms.
            try await statusUseCases.deleteOwnStatusItem.execute(
                statusID: statusItem,
                syncStatus: syncStatus,
                codeStatus: codeStatus
            )
            await loadOwnStatus()
        } catch let appError as AppError {
            deleteErrorMessage = Self.userFacingDeleteMessage(from: appError)
            showDeleteErrorAlert = true
        } catch {
            deleteErrorMessage = nil
            showDeleteErrorAlert = true
        }

        deletingStatusId = nil
    }

    /// Only known filtered AppError cases — never raw server `message` / validation payloads.
    private static func userFacingDeleteMessage(from error: AppError) -> String? {
        switch error {
        case .noInternetConnection,
             .timeout,
             .serverError,
             .rateLimited,
             .serviceUnavailable,
             .forbidden,
             .notFound,
             .sessionExpired,
             .authenticationError,
             .cancelled:
            return error.errorDescription
        case .networkError, .validationError, .badRequest, .unknown, .decodingError, .emptyResponse, .biometric, .tokenRefreshFailed:
            return nil
        }
    }
    func addOwnStatus(story: StoryToSend) async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await statusUseCases.addOwnStatus.execute(storie: story)
            await loadOwnStatus()
            notifyStatusMediaCached(codeStatus: story.id)
        } catch {
            self.error = "Erreur lors de l'ajout du statut: \(error.localizedDescription)"
        }
    }
    
    func addContactStatus(_ status: Status) {
        Task {
            do {
                try await statusUseCases.addContactStatus.execute(status: status)
                await loadContactStatuses()
            } catch {
                self.error = "Erreur lors de l'ajout du statut contact: \(error.localizedDescription)"
            }
        }
    }
    func RetryUploadAndPostStatus(statusId: String) async {
        syncInProgress = true
        defer { syncInProgress = false }
        await statusUseCases.retryFailedUploadStatusUseCase.execute(statusItemId: statusId)
        await loadOwnStatus()
    }
    
    func markAsSeen(contactUserId: String, statusId: String, liked: Bool = false, isStatusItem: Bool = true) {
        // Own stories: don't mark local `viewed` or publish view-story for yourself.
        guard !isOwnStatus(userId: contactUserId) else { return }

        applyLocalViewed(contactUserId: contactUserId, statusId: statusId, wholeThread: !isStatusItem)

        Task {
            do {
                try await statusUseCases.markAsSeen.execute(
                    contactUserId: contactUserId,
                    statusId: statusId,
                    liked: liked,
                    isStatusItem: isStatusItem
                )
            } catch {
                self.error = "Erreur lors du marquage comme vu: \(error.localizedDescription)"
            }
        }
    }

    /// Immediate UI update so the green ring clears without waiting for a reload.
    private func applyLocalViewed(contactUserId: String, statusId: String, wholeThread: Bool) {
        guard let idx = contactStatus.firstIndex(where: { $0.userId == contactUserId }) else { return }

        if wholeThread {
            for i in contactStatus[idx].status.indices {
                contactStatus[idx].status[i].viewed = true
            }
        } else if let itemIdx = contactStatus[idx].status.firstIndex(where: {
            $0.id == statusId || $0.codeStatus == statusId
        }) {
            contactStatus[idx].status[itemIdx].viewed = true
        }

        contactStatus[idx].viewed = contactStatus[idx].status.allSatisfy(\.viewed)
        // Keep open-position in sync for the next time this thread is opened.
        contactStatus[idx].applyResumeIndex()
    }

    /// Call after an image/video poster is saved under `.STATUS` so strip cards pick up real media.
    func notifyStatusMediaCached(codeStatus: String? = nil) {
        mediaCacheRevision &+= 1
    }

    func reactToStatus(storyId: String, reaction: String = "❤️") {
        guard !storyId.isEmpty, !reaction.isEmpty else { return }
        Task {
            await statusUseCases.reactToStatus.execute(storyId: storyId, reaction: reaction)
        }
    }

    /// Sends a normal DM whose `replyTo*` snapshot points at the status segment.
    @discardableResult
    func sendStatusReply(
        text: String,
        statusOwner: Status,
        statusItem: StatusItem
    ) async -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        guard !isOwnStatus(userId: statusOwner.userId) else { return false }
        guard let conversationRoomUseCases else {
            #if DEBUG
            print("[StatusReply] conversationRoomUseCases missing")
            #endif
            return false
        }

        let peerUserId = statusOwner.userId
        guard !peerUserId.isEmpty else { return false }

        let resolved = await resolvePeerConversation(peerUserId: peerUserId, statusOwner: statusOwner)
        let reply = OutgoingMessageBuilder.replyFrom(
            status: statusItem,
            ownerName: statusOwner.userName ?? statusItem.userName
        )

        let request = SendMessageRequest(
            content: MessageContent(text: trimmed),
            type: .TEXT,
            conversationId: resolved.conversationId,
            receiver: resolved.receiver,
            // A status reply goes to the poster, one to one.
            kind: .direct,
            reply: reply,
            recipientId: peerUserId
        )

        let code = await conversationRoomUseCases.sendMessage.execute(request)
        #if DEBUG
        print("[StatusReply] sent=\(code != nil) conversation=\(resolved.conversationId) status=\(statusItem.codeStatus)")
        #endif
        return code != nil
    }

    private func resolvePeerConversation(
        peerUserId: String,
        statusOwner: Status
    ) async -> (conversationId: String, receiver: UserRoom) {
        if let discussions = try? await discussionUseCases?.getDiscussions.execute(),
           let existing = discussions.first(where: {
               $0.contact?.isGroup == false && $0.contact?.userId == peerUserId
           }) {
            let contact = existing.contact
            let receiver = UserRoom(
                idContact: contact?.id ?? peerUserId,
                userId: peerUserId,
                phone: contact?.phone,
                name: contact?.userName ?? statusOwner.userName,
                avatar: contact?.image ?? statusOwner.userImage,
                description: nil,
                onlineStatus: UserOnline(status: .offline, lastSeen: "Never", userId: peerUserId),
                isBlocked: contact?.isBlocked ?? false
            )
            return (existing.conversationId, receiver)
        }

        var phone = ""
        var contactId = peerUserId
        var name = statusOwner.userName ?? ""
        var avatar = statusOwner.userImage
        var isBlocked = false

        if let bundle = try? await contactsUseCases?.getPersistedContacts.execute() {
            if let match = bundle.waanguContacts.first(where: { $0.userId == peerUserId }) {
                phone = match.phone
                contactId = match.id
                name = match.name.isEmpty ? name : match.name
                avatar = match.image ?? avatar
                isBlocked = match.isBlocked
            } else if let props = bundle.UserContactProps.first(where: { $0.userId == peerUserId }) {
                phone = props.phone
                contactId = props.idContact ?? peerUserId
                name = props.name.isEmpty ? name : props.name
                avatar = props.avatar ?? avatar
                isBlocked = props.isBlocked
            }
        }

        let receiver = UserRoom(
            idContact: contactId,
            userId: peerUserId,
            phone: phone.isEmpty ? peerUserId : phone,
            name: name,
            avatar: avatar,
            description: nil,
            onlineStatus: UserOnline(status: .offline, lastSeen: "Never", userId: peerUserId),
            isBlocked: isBlocked
        )
        return (UUID().uuidString.lowercased(), receiver)
    }
    
    func clearAllStatuses() {
        Task {
            do {
                try await statusUseCases.clearAllStatuses.execute()
                ownStatus = nil
                contactStatus = []
                lastSyncDate = nil
            } catch {
                self.error = "Erreur lors du nettoyage: \(error.localizedDescription)"
            }
        }
    }
    func DeleteAllExpiredStatuses() {
        Task {
            do {
                try await statusUseCases.deleteAllExpiredStatusItem.execute()
            } catch {
                self.error = "Erreur lors du nettoyage: \(error.localizedDescription)"
            }
        }
    }
    
    func getStatusByUserId(_ userId: String) async -> [Status] {
        do {
            return try await statusUseCases.getStatusByUserId.execute(userId: userId)
        } catch {
            self.error = "Erreur lors de la récupération: \(error.localizedDescription)"
            return []
        }
    }
    
    func getStatusFn() async {
        // Cancel any prior load — the latest call wins
        loadTask?.cancel()
        refreshDebounceTask?.cancel()

        loadTask = Task {
            guard !Task.isCancelled else { return }

            // Retry once if userId wasn't ready yet (init race)
            var uid = CurrentSessionInfo.shared.currentUid
            if uid.isEmpty {
                // Give the session up to 1 second to populate
                for _ in 0..<10 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                    uid = CurrentSessionInfo.shared.currentUid
                    if !uid.isEmpty { break }
                }
            }

            // Cleared here, not carried over from a previous call: a stale
            // error from an earlier failed load must not block this one from
            // ever being allowed to count as loaded.
            error = nil

            guard !Task.isCancelled else { return }
            await loadOwnStatus()

            guard !Task.isCancelled else { return }
            await loadContactStatuses()
            loadLastSyncDate()

            // Only on success: `loadContactStatuses` sets `error` on failure,
            // and a failed load must stay eligible to retry on the next
            // appearance rather than being marked loaded and skipped forever.
            if error == nil {
                hasLoadedInitialData = true
            }
        }

        await loadTask?.value
    }

    /// Coalesce bursty MQTT / repository notifications into one in-flight reload.
    private func scheduleStatusesRefresh() {
        refreshDebounceTask?.cancel()
        refreshDebounceTask = Task { [weak self] in
            // Short debounce so STORY_CREATED + follow-up events don't thrash the strip.
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard !Task.isCancelled else { return }
            await self?.getStatusFn()
        }
    }
    
    func getNewStatus() async {
//        do {
//            try await statusUseCases.getStatusFromServerUseCase.execute()
//            print("🔥 Nouveau statut reçu successfully")
//        } catch {
//            self.error = "❌Erreur lors des retentatives: \(error.localizedDescription)"
//        }
        
    
    }
    
    func contactViewMyStatus(_ status: StatusItem) {
        // Implémentation quand un contact voit votre statut
        // À adapter selon vos besoins
        #if DEBUG
        print("Statut vu par un contact: \(status.id)")
        #endif
    }
    
    // MARK: - Private Methods
    
    private func loadInitialData() {
        DeleteAllExpiredStatuses()
        Task {
            // ✅ Sync stories from server first
            await syncStoriesFromServer()
            // Then load from local DB
            await getStatusFn()
        }
    }
    
    // MARK: - Stories Sync
    
    private func syncStoriesFromServer() async {
        do {
            debugLog("[StoriesSync] Starting stories sync...")
            let count = try await statusUseCases.syncStories(limit: 50)
            debugLog("[StoriesSync] ✅ Synced \(count) stories from server")
        } catch {
            debugLog("[StoriesSync] ❌ Failed to sync stories: \(error)")
            // Don't fail the whole UI, just log the error
        }
    }
    
     func loadOwnStatus() async {
        let currentUserId = CurrentSessionInfo.shared.currentUid

        // If the session isn't populated yet, don't overwrite a valid ownStatus with nil.
        guard !currentUserId.isEmpty else {
            #if DEBUG
            print("⚠️ loadOwnStatus skipped — currentUid is empty (session not ready yet)")
            #endif
            return
        }

        do {
            let fetched = try await statusUseCases.getOwnStatus.execute(userId: currentUserId)
            #if DEBUG
            print("🟢 loadOwnStatus fetched for uid=\(currentUserId): \(fetched?.status.count ?? 0) items")
            #endif

            guard var thread = fetched else {
                ownStatus = nil
                return
            }

            for i in thread.status.indices {
                let item = thread.status[i]
                if item.type == .video {
                    let url = DiskMediaManager.shared.loadVideoFromDisk(fileName: item.codeStatus, pathName: .STATUS)
                    thread.status[i].content = url?.absoluteString
                    
                }
            }

            ownStatus = thread
            debugLog("this was fetched my own status from GRDB: count...............  \(ownStatus?.status.count)")
        } catch {
            #if DEBUG
            print("❌ loadOwnStatus failed: \(error)")
            #endif
        }
    }
    
    private func loadContactStatuses() async {
        do {
            let contactStatuses = try await statusUseCases.getContactStatuses.execute()
            let previousIds = contactStatus.map(\.id)
            let ownUserId = CurrentSessionInfo.shared.currentUid

            // Never show the current user inside the contact story strip / pager.
            let sortedContactStatuses = contactStatuses
                .filter { status in
                    guard !ownUserId.isEmpty else { return true }
                    return status.userId != ownUserId && !isOwnStatus(userId: status.userId)
                }
                .map { status -> Status in
                    var s = status
                    s.status = status.status.sorted {
                        ($0.createdAt) < ($1.createdAt)
                    }
                    s.applyResumeIndex()
                    return s
                }

            let nextIds = sortedContactStatuses.map(\.id)
            let shouldAnimateInsertion = hasLoadedInitialData && previousIds != nextIds

            // Assign without ViewModel-level withAnimation — animating the whole
            // published array while the strip is on-screen retargets sibling taps
            // (own status). Insertion animation is owned by the ForEach in StoriesView.
            var transaction = Transaction()
            transaction.disablesAnimations = !shouldAnimateInsertion
            withTransaction(transaction) {
                contactStatus = sortedContactStatuses
            }

            // If the open contact pager pointed at a story that disappeared, clear selection.
            if !currentStory.isEmpty,
               !sortedContactStatuses.contains(where: { $0.id == currentStory }) {
                currentStory = sortedContactStatuses.first?.id ?? ""
                if sortedContactStatuses.isEmpty, navigateToStatusViewer {
                    closeStatusViewer()
                }
            }
        } catch {
            self.error = "Erreur lors du chargement des statuts contacts: \(error.localizedDescription)"
        }
    }
    
    private func loadLastSyncDate() {
        do {
//            lastSyncDate = try StatusRepository().getLastSyncDate()
        } catch {
            self.error = "Erreur lors du chargement de la date de sync: \(error.localizedDescription)"
        }
    }
    
    // MARK: - Helper Methods
    
    func refreshData() {
        Task {
            await getStatusFn()
        }
    }
    
//    func selectStatus(_ statusId: String, userId: String) {
//        selectedStatusId = statusId
//        currentUser = userId
//        
//        // Trouver l'index du statut sélectionné
//        if let status = contactStatus.first(where: { $0.userId == userId }) {
//            currentIndex = status.status.firstIndex(where: { $0.id == statusId }) ?? 0
//        }
//    }
}

@available(iOS 16.0, *)
extension StoriesViewModel {

//    private func loadThumbnail(for asset: MediaAsset,
//                               into list: inout [MediaAssetUI]) async {
//
//        await withCheckedContinuation { continuation in
//            phMediaManager.getThumbnailBase64(asset: asset.asset, size: CGSize(width: 90, height: 90)) { base64 in
//
//                let uiModel = MediaAssetUI(
//                    id: asset.id,
//                    phAsset: asset.asset,
//                    type: asset.type,
//                    creationDate: asset.creationDate,
//                    thumbnailBase64: base64
//                )
//
//                list.append(uiModel)
//                continuation.resume()
//            }
//        }
//    }
    private func loadThumbnail(for asset: MediaAsset,
                               list: [MediaAssetUI]) async -> [MediaAssetUI] {
        var result = list
        let base64 = await withCheckedContinuation { continuation in
            phMediaManager.getThumbnailBase64(asset: asset.asset,
                                              size: CGSize(width: 90, height: 90)) { base64 in
                continuation.resume(returning: base64)
            }
        }

        let uiModel = MediaAssetUI(
            id: asset.id,
            phAsset: asset.asset,
            type: asset.type,
            creationDate: asset.creationDate,
            thumbnailBase64: base64
        )

        // Find and update or append depending on your logic
        if let idx = result.firstIndex(where: { $0.id == asset.id }) {
            result[idx] = uiModel
        } else {
            result.append(uiModel)
        }

        return result
    }
}
