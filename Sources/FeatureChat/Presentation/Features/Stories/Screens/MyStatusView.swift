import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

enum ActiveSheet: Identifiable {
    case addStatus
    case filePicker
    
    var id: Int {
        hashValue
    }
}

@available(iOS 16.0, *)
struct MyStatusView: View {
    @Environment(\.dismiss) var dismiss
    @State private var activeSheet: ActiveSheet?
    @State private var openStatusEditorAfterGalleryDismiss = false
    @State private var navigateToNext = false
    @State private var goToStatusEditor: Bool = false
    let navigationCoord : UpdatesTabCoordinator
    
    let screenWidth = UIScreen.main.bounds.width
    @ObservedObject public var statusStore:StoriesViewModel
    let viewModel: PHMediaManagerViewModel
    let translationService: (any TranslationServiceProtocol)?

    init(
        navigationCoord: UpdatesTabCoordinator,
        statusStore: StoriesViewModel,
        viewModel: PHMediaManagerViewModel,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.navigationCoord = navigationCoord
        self.statusStore = statusStore
        self.viewModel = viewModel
        self.translationService = translationService
    }

    var body: some View {
        ZStack {
            if #available(iOS 16.0, *) {
                Spacer().toolbar( .hidden,for: .tabBar).onAppear{
                    debugLog("this current state of the tab bar is: \(statusStore.isFirstPageStory ? "visible" : "hidden")")
                }
            } else {
                // Fallback on earlier versions
            }
                VStack {
                    // Header
                    HStack {
                        Image(systemName: "chevron.left")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 15)
                            .foregroundStyle(.primary)
                            .onTapGesture {
                                statusStore.goBacktoRoot(coord: navigationCoord)
                            }
                        Spacer()
                        Text(t(ChatTranslationKeys.STORIES_MY_STATUS))
                            .bold()
                            .font(.title2)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(t(ChatTranslationKeys.STORIES_EDIT))
                            .font(.title2)
                            .foregroundStyle(AppColors.primary)
                    }
                    .padding(.horizontal, 20)
                    .onAppear {
                        Task {
                            await statusStore.loadOwnStatus()
                            // Resume any pending/failed syncs that were interrupted
                            // (e.g. app was killed while uploading, or network was offline)
                            await statusStore.resumePendingStatuses()
                        }
//                        statusStore.isFirstPageStory = false
                    }
                    
                    if #available(iOS 16.0, *) {
                        Spacer().frame(height: 40)
                    }
                    
                    // Main content scroll
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack {
                            // Own statuses list
                            if let ownStatus = statusStore.ownStatus, !ownStatus.status.isEmpty {
                                StatusListView(ownStatus: ownStatus,navigationCoord:navigationCoord, statusStore: statusStore, translationService: translationService)
                                Divider()
                            }
                            
                            // Add status row
                            AddStatusRowView(translationService: translationService) {
                                withAnimation {
                                    activeSheet = .addStatus
                               
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .background(AppColors.cardBackground)
                        .cornerRadius(16)
                    }
                }
                .background(Color(.systemGroupedBackground).ignoresSafeArea())
                .alert(
                    t(ChatTranslationKeys.STORIES_DELETE_FAILED_TITLE),
                    isPresented: $statusStore.showDeleteErrorAlert
                ) {
                    Button(common("ok"), role: .cancel) {
                        statusStore.deleteErrorMessage = nil
                    }
                } message: {
                    // Prefer filtered AppError message; otherwise translated fallback.
                    // Never show raw server payloads.
                    Text(
                        statusStore.deleteErrorMessage
                            ?? t(ChatTranslationKeys.STORIES_DELETE_FAILED_MESSAGE)
                    )
                }
            
            
            // Sheet
            .chatAppearanceSheet(item: $activeSheet, onDismiss: {
                viewModel.resetSelectedMedia()
                if openStatusEditorAfterGalleryDismiss {
                    openStatusEditorAfterGalleryDismiss = false
                    statusStore.openStatusEditor(coord: navigationCoord)
                }
            }) { sheet in
                switch sheet {
                case .addStatus:
                    if #available(iOS 16.0, *) {
                        AddStatusSheetContent(
                            screenWidth: screenWidth,
                            viewModel: viewModel, statusStore: statusStore,
                            translationService: translationService,
//                            statusStore: statusStore
                            onGallerySelected: {
                                openStatusEditorAfterGalleryDismiss = true
                                activeSheet = nil
                            },
                            onTextEditor: {
                                activeSheet = nil
                                statusStore.openTextEditor(coord: navigationCoord)
    //                            goToStatusEditor = true
    //                            statusStore.isFirstPageStory = false
                            }
                        )
                        .presentationDetents([.fraction(0.99)])
                        .presentationDragIndicator(.visible)
                    }
                case .filePicker:
                    EmptyView()
                }
            }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Extracted Views

@available(iOS 16.0, *)
struct StatusListView: View {
    let ownStatus: Status
    let navigationCoord: UpdatesTabCoordinator
    @ObservedObject var statusStore: StoriesViewModel
    let translationService: (any TranslationServiceProtocol)?
    
    init(
        ownStatus: Status,
        navigationCoord: UpdatesTabCoordinator,
        statusStore: StoriesViewModel,
        translationService: (any TranslationServiceProtocol)?
    ) {
        self.ownStatus = ownStatus
        self.navigationCoord = navigationCoord
        self.statusStore = statusStore
        self.translationService = translationService
    }
   
    var body: some View {
        ForEach(ownStatus.status) { stori in
            ZStack {
                
//                NavigationLink(
//                    destination: StatusViewer(
//                        storyId: ownStatus.userId, viewModel: statusStore
//                    )
//                    .navigationBarBackButtonHidden()
//                ) {
                    HStack {
                        Spacer().frame(width: 20)
                        
                        // Thumbnail with sync status overlay
                        ZStack(alignment: .bottomLeading) {
                            switch stori.type {
                            case .text:
                                TextStatusViewComponent(
                                    text: stori.content ?? "",
                                    backgroundColor: Color(hex: stori.background ?? "#000000"),
                                    width: 70,
                                    height: 70,
                                    cornerRadius: 200,
                                    fontFamily: stori.fontText ?? "system",
                                    fontWeight: stori.fontWeight?.asFontWeight ?? .regular
                                )
                            case .image, .video:
                                let preview = StatusLocalMediaResolver.stripPreview(
                                    for: stori,
                                    ownLocalOnly: true
                                )
                                ImageViewComponent(
                                    url: preview.remoteURL,
                                    isImageDataUrl: preview.isImageDataUrl,
                                    width: 70,
                                    height: 70,
                                    isFromDisk: preview.usesDisk,
                                    imageFromDisk: preview.diskImage,
                                    zoomIn: 3
                                )
                                .id("mystatus-\(stori.codeStatus)-\(statusStore.mediaCacheRevision)")
                            case .audio:
                                EmptyView()
                            }

                            // Sync badge overlay on the thumbnail
                            if statusStore.deletingStatusId == stori.id {
                                ZStack {
                                    Circle()
                                        .fill(Color.black.opacity(0.45))
                                    ProgressView()
                                        .tint(.white)
                                }
                            } else {
                                StatusSyncBadge(syncStatus: stori.syncStatus)
                                    .padding(4)
                            }
                        }
                        .frame(width: 70, height: 70)
                        
                        Spacer().frame(width: 20)
                        
                        if statusStore.deletingStatusId == stori.id {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text(t(ChatTranslationKeys.STORIES_DELETING))
                                        .bold()
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                                Text(t(ChatTranslationKeys.STORIES_PLEASE_WAIT))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else if stori.isPublished {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.green)
                                        .font(.subheadline)
                                    Text(t(ChatTranslationKeys.STORIES_VIEWS, args: ["\(stori.viewCount)"]))
                                        .bold()
                                        .font(.headline)
                                        .foregroundStyle(.primary)
                                }
                                Text(formatDate(stori.createdAt))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    switch stori.syncStatus {
                                    case .pending, .retrying, .syncing:
                                        ProgressView()
                                            .scaleEffect(0.8)
                                        Text(t(ChatTranslationKeys.STORIES_SENDING))
                                            .bold()
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                    case .failed:
                                        Image(systemName: "exclamationmark.circle.fill")
                                            .foregroundColor(.red)
                                            .font(.subheadline)
                                        Text(t(ChatTranslationKeys.STORIES_FAILED_SEND))
                                            .bold()
                                            .font(.headline)
                                            .foregroundStyle(.red)
                                    case .synced:
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                            .font(.subheadline)
                                        Text(t(ChatTranslationKeys.STORIES_SENT))
                                            .bold()
                                            .font(.headline)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                Text(stori.syncStatus == .failed
                                     ? t(ChatTranslationKeys.STORIES_TAP_RETRY)
                                     : t(ChatTranslationKeys.STORIES_PLEASE_WAIT))
                                    .font(.caption)
                                    .foregroundStyle(stori.syncStatus == .failed ? AppColors.primary : .secondary)
                            }
                        }
                        
                        Spacer()
                    }
                    .frame(height: 100)
//                }
                .onTapGesture {
                    if let index = ownStatus.status.firstIndex(where: { $0.codeStatus == stori.codeStatus }) {
                        statusStore.ownStatus?.currentIndex = index
//                        statusStore.navigateToViewMyStories = true
                        statusStore.viewStatus(coord:navigationCoord,storyId: ownStatus.userId)
                    }
                }
                
                HStack {
                    Spacer()
                    
                    if stori.syncStatus == .failed && statusStore.deletingStatusId != stori.id {
                        Button {
                            Task {
                                if stori.type != .text && !stori.uploaded {
                                    await statusStore.RetryUploadAndPostStatus(statusId: stori.codeStatus)
                                } else {
                                    await statusStore.retryFailedSyncs(statusId: stori.codeStatus)
                                }
                            }
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 36, height: 36)
                                .background(AppColors.primary)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 4)
                        .accessibilityLabel(t(ChatTranslationKeys.STORIES_TAP_RETRY))
                    }

                    if statusStore.deletingStatusId == stori.id {
                        ProgressView()
                            .frame(width: 36, height: 36)
                            .padding(.trailing, 12)
                    } else {
                        Menu {
                            Button(common("delete"), systemImage: "trash", role: .destructive) {
                                Task {
                                    await statusStore.deleteOwnStatusItem(
                                        statusItem: stori.id,
                                        syncStatus: stori.syncStatus,
                                        codeStatus: stori.codeStatus
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.title3)
                                .foregroundStyle(.primary)
                                .frame(width: 36, height: 36)
                        }
                        .disabled(statusStore.deletingStatusId != nil)
                        .padding(.trailing, 12)
                    }
                }
            }
            .opacity(statusStore.deletingStatusId == stori.id ? 0.6 : 1)
            .allowsHitTesting(statusStore.deletingStatusId != stori.id)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

// MARK: - Sync status badge shown on the thumbnail corner

/// Small badge overlaid on a status thumbnail to communicate upload/sync state at a glance.
struct StatusSyncBadge: View {
    let syncStatus: SyncStatus

    var body: some View {
        Group {
            switch syncStatus {
            case .synced:
                // No badge needed — success is the default, don't add noise
                EmptyView()
            case .pending, .syncing, .retrying:
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 22, height: 22)
                    ProgressView()
                        .scaleEffect(0.55)
                        .tint(.white)
                }
            case .failed:
                ZStack {
                    Circle()
                        .fill(Color.red)
                        .frame(width: 22, height: 22)
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }
            }
        }
    }
}

struct AddStatusRowView: View {
    let translationService: (any TranslationServiceProtocol)?
    let onTap: () -> Void
    
    init(translationService: (any TranslationServiceProtocol)?, onTap: @escaping () -> Void) {
        self.translationService = translationService
        self.onTap = onTap
    }
    
    var body: some View {
        HStack {
            Spacer().frame(width: 20)
            VStack {
                Image(systemName: "plus")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .foregroundColor(AppColors.primary)
            }
            .frame(width: 70, height: 70)
            .background(AppColors.primary.opacity(0.12))
            .cornerRadius(100)
            
            Spacer().frame(width: 20)
            Text(t(ChatTranslationKeys.STORIES_ADD_STATUS))
                .bold()
                .font(.headline)
                .foregroundStyle(.primary)
            Spacer()
        }
        .frame(height: 100)
        .onTapGesture(perform: onTap)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

@available(iOS 16.0, *)
struct AddStatusSheetContent: View {
    let screenWidth: CGFloat
    @ObservedObject var viewModel: PHMediaManagerViewModel
    let statusStore: StoriesViewModel
    let translationService: (any TranslationServiceProtocol)?
    let onGallerySelected: () -> Void
    let onTextEditor: () -> Void
    
    init(screenWidth: CGFloat, viewModel: PHMediaManagerViewModel, statusStore: StoriesViewModel, translationService: (any TranslationServiceProtocol)?, onGallerySelected: @escaping () -> Void, onTextEditor: @escaping () -> Void) {
        self.screenWidth = screenWidth
        self.viewModel = viewModel
        self.statusStore = statusStore
        self.translationService = translationService
        self.onGallerySelected = onGallerySelected
        self.onTextEditor = onTextEditor
    }
    
    var body: some View {
        VStack {
            Text(t(ChatTranslationKeys.STORIES_ADD_STATUS))
                .font(.title2)
                .foregroundStyle(.primary)
                .padding()
            
            Spacer().frame(height: 10)
            
            HStack {
                Spacer()
                
                VStack(spacing: 0) {
                    Image(systemName: "pencil")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30)
                        .foregroundColor(AppColors.primary)
                    Spacer().frame(height: 10)
                    Text(t(ChatTranslationKeys.STORIES_TEXT))
                        .font(.title2)
                        .foregroundStyle(.primary)
                }
                .frame(width: screenWidth * 0.4, height: 100)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                .onTapGesture {
                  onTextEditor()
                    
                }
                
                VStack(spacing: 0) {
                    Image(systemName: "camera.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30)
                        .foregroundColor(AppColors.primary)
                    Spacer().frame(height: 10)
                    Text(t(ChatTranslationKeys.STORIES_CAMERA))
                        .font(.headline)
                        .foregroundStyle(.primary)
                }
                .frame(width: screenWidth * 0.4, height: 100)
                .background(Color(.systemGray5))
                .cornerRadius(10)
                
                Spacer()
            }
            
            Spacer().frame(height: 20)
            
            GalleryView(
                viewModel: viewModel,
                translationService: translationService,
                selectingEnded: { _ in
                    statusStore.selectedMedia = viewModel.selectedMedia
                    onGallerySelected()
                    viewModel.resetSelectedMedia()
                },
                onDirectSelect: { media in
                    statusStore.selectedMedia = [media]
                    onGallerySelected()
                    viewModel.resetSelectedMedia()
                }
            )
            
            Spacer()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
