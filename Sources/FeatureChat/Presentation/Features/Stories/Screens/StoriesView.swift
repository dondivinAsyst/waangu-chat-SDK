import SwiftUI
import Combine
import WaanguSharedUI
import WaanguCoreKit


struct Story: Identifiable {
    let id = UUID()
    let username: String
    let imageURL: String
    var currentUser: Bool // optional boolean
    let profileImage : String
}

@available(iOS 16.0, *)
struct StoriesView: View {

    @State private var searchText: String = ""
    @State private var selectedURL: [URL] = []
    @State private var showAddStatusSheet: Bool = false
    @State private var activeSheet: ActiveSheet?
    @State private var openStatusEditorAfterGalleryDismiss = false
    @State private var goToStatusEditor: Bool = false
    @State private var navigateToNext = false
    @State private var currentIndex : Int = 0
    /// The channels explainer is a one-time thing, per device: it describes a
    /// feature, it is not a consent the server records.
    @AppStorage("chat.channels.introAccepted") private var channelsIntroAccepted = false
    @State private var showChannelsWelcome = false
    @State private var showCreateChannelIntro = false
    /// What the user asked for before the explainer interrupted, replayed once
    /// they agree.
    @State private var pendingChannelAction: ChannelEntryAction?
    @ObservedObject public var statusStore:StoriesViewModel
    @ObservedObject var channelsViewModel: ChannelsViewModel
    let viewModel: PHMediaManagerViewModel
    let navigationCoordinator: UpdatesTabCoordinator
    let translationService: (any TranslationServiceProtocol)?

    init(
        statusStore: StoriesViewModel,
        channelsViewModel: ChannelsViewModel,
        viewModel: PHMediaManagerViewModel,
        navigationCoordinator: UpdatesTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.statusStore = statusStore
        self.channelsViewModel = channelsViewModel
        self.viewModel = viewModel
        self.navigationCoordinator = navigationCoordinator
        self.translationService = translationService
    }

    let screenWidth = UIScreen.main.bounds.width
    
    var body: some View {
        ScrollView(.vertical, showsIndicators: false){
                    VStack { // align to leading
                                   // Status title
//                        if #available(iOS 16.0, *) {
//                            Spacer().toolbar(statusStore.isFirstPageStory ? .visible : .hidden,for: .tabBar)
//                        } else {
//                            // Fallback on earlier versions
//                        }
                      
//                            NavigationLink(destination:EditorTabView().navigationBarBackButtonHidden(), isActive: $navigateToNext) {
//                                EmptyView()
//                            }
                        
                      
    //                    NavigationLink(destination: StoryViewer().navigationBarBackButtonHidden(), isActive: $statusStore.navigateToStatusViewer) {
    //                            EmptyView()
    //                        }
                     
                      
//                        if #available(iOS 17.0, *) {
//                            NavigationLink(destination:StatusEditor(viewModel: viewModel,selectedMedia: statusStore.selectedMedia ).navigationBarBackButtonHidden(), isActive: $goToStatusEditor) {
//                                EmptyView()
//                                
//                            }
//                        } else {
//                            // Fallback on earlier versions
//                        }
                      
                                   HStack{
                                       Text(t(ChatTranslationKeys.STORIES_STATUS_TITLE)).font(.title)
                                                         .bold()
                                                         .padding(.top)
                                                         .padding(.horizontal)
                                       Spacer()
                                       HStack(spacing:16){
                                         
//                                               NavigationLink(destination: CameraView(mode: .photo,  onDismiss: {
//                                                   print("CameraView dismissed manually")
//                                               }).navigationBarBackButtonHidden())
                                           Button(action: {
                                               statusStore.openCamera(coord: navigationCoordinator)
                                               
//                                               navigationCoordinator.push(.editTabStoryView(initialTab: .photo))
                                           }
                                               )
                                           {   Image(systemName: "camera").resizable()
                                                       .frame(width: 16,height: 16).padding(10).background(Color(.systemGray6)).clipShape(Circle()).foregroundColor(Color.primary)
                                                   
                                                   //                                               .onTapGesture {
                                                   //                                                   print("Add photo")
                                                   //                                               }
                                           }
                                         
                                           Button(action: {
                                               statusStore.openTextEditor(coord: navigationCoordinator)
//                                               navigationCoordinator.push(.editTabStoryView(initialTab: .text))
                                           }
                                               ){
                                          Image(systemName: "pencil").resizable()
                                              .frame(width: 16,height: 16).padding(10).background(Color(.systemGray6)).clipShape(Circle()).foregroundColor(Color.primary)
                                           }
//                                           NavigationLink(destination: EditorTabView(initialTab: .text))  {
//                                                   Image(systemName: "pencil").resizable()
//                                                       .frame(width: 16,height: 16).padding(10).background(Color(.systemGray6)).clipShape(Circle()).foregroundColor(Color.primary)
//                                                   
//                                                   //                                               .onTapGesture {
//                                                   //                                                                    print("Add Text")
//                                                   //
//                                                   //                                           }
//                                               }
                                         
                                       }.padding(.trailing)
                                       
                                    
                                   }.onAppear{
                                       debugLog("this was fetched my own status from GRDB: \(statusStore.ownStatus)")
                                   }
                                   
                                   // Horizontal stories
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 4) {
                              
                                if #available(iOS 16.0, *) {
                                    let count = statusStore.ownStatus?.status.count ?? 0
                                    
                                  
                                    if count > 0 {
    //                             
                                        let lastStatus = statusStore.ownStatus?.status.last
                                     
                                      ZStack(alignment: .bottomTrailing) {
                                            // Story background
                                            
                                            if lastStatus?.type == .text {
                                                TextStatusViewComponent(
                                                    text: lastStatus?.content ?? "",
                                                    backgroundColor: Color(hex:lastStatus?.background ?? "#00000"),
                                                    width: 100,
                                                    height: 170,
                                                    cornerRadius: 16
                                                )
                                            }else if let lastStatus {
                                                let preview = StatusLocalMediaResolver.stripPreview(
                                                    for: lastStatus,
                                                    ownLocalOnly: true
                                                )
                                                ImageViewComponent(
                                                    url: preview.remoteURL,
                                                    isImageDataUrl: preview.isImageDataUrl,
                                                    width: 100,
                                                    height: 170,
                                                    cornerRadius: 16,
                                                    isFromDisk: preview.usesDisk,
                                                    imageFromDisk: preview.diskImage,
                                                    zoomIn: 3
                                                )
                                                .id("own-\(lastStatus.codeStatus)-\(statusStore.mediaCacheRevision)")
                                            }

                                            // Sync badge — top trailing corner
                                            if let syncStatus = lastStatus?.syncStatus, syncStatus != .synced {
                                                VStack {
                                                    HStack {
                                                        Spacer()
                                                        StatusSyncBadge(syncStatus: syncStatus)
                                                            .padding(6)
                                                    }
                                                    Spacer()
                                                }
                                            }

                                            ZStack(alignment: .bottomTrailing) {
                                                StoryProfileView(story: statusStore.ownStatus,showAddStatusSheet: $activeSheet,currentUser: true)
                                            }
                                            .padding([.top, .leading], 8)
                                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)

                                            Text(t(ChatTranslationKeys.STORIES_MY_STATUS)).foregroundColor(.white).bold() .font(.headline).frame(width:100, alignment: .center).padding(.bottom,10)
                                        }
                                        .frame(width: 100, height: 170)
                                        .background(.red.opacity(0.5))
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
                                        .onTapGesture {
                                            statusStore.openMyStatusList(coord: navigationCoordinator)
                                        }
                                        // Stable identity — live contact inserts must not recycle this card.
                                        .id("stories-own-status-card")
                                        .transaction { $0.animation = nil }
                                        
                                       
                                    } else {
                                        VStack {
                                            Spacer()
                                            StoryProfileView(
                                                story: statusStore.ownStatus,
                                                showAddStatusSheet: $activeSheet,
                                                currentUser: true
                                                
                                            )
                                            Spacer()
                                            Text(t(ChatTranslationKeys.STORIES_MY_STATUS))
                                                .foregroundColor(AppColors.primary)
                                                .bold()
                                                .font(.headline)
                                                .frame(width: 100, alignment: .center)
                                                .padding(.bottom, 10)
                                            
                                        }
                                        .frame(width: 100, height: 170)
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
                                        .onTapGesture {
                                            statusStore.openMyStatusList(coord: navigationCoordinator)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(AppColors.primary, lineWidth: 2)     // your border
                                        )
                                        .id("stories-own-status-card")
                                        .transaction { $0.animation = nil }
                                    }
                                } else {
                                    // Fallback on earlier versions
                                }
                              
                                if statusStore.hasLoadedInitialData, statusStore.contactStatus.isEmpty {
                                    StoriesEmptyIntroView(
                                        header: t(ChatTranslationKeys.STORIES_STATUS_HEADER),
                                        photoLabel: t(ChatTranslationKeys.STORIES_PHOTO_LABEL).capitalized,
                                        videoLabel: t(ChatTranslationKeys.STORIES_VIDEO_LABEL).capitalized,
                                        textLabel: t(ChatTranslationKeys.STORIES_TEXT),
                                        onTap: { activeSheet = .addStatus }
                                    )
                                    // Fill everything to the right of "My status" in the visible row.
                                    .frame(width: max(160, screenWidth - 100 - 24), height: 170)
                                    .transition(.opacity)
                                }

                                ForEach(statusStore.contactStatus, id: \.id) { story in
                                    if !statusStore.isOwnStatus(userId: story.userId) {
                                        ZStack(alignment: .bottom) {
                                            ContactStatusPreviewer(
                                                story: story,
                                                mediaCacheRevision: statusStore.mediaCacheRevision
                                            )

                                            Text(story.userName ?? "User")
                                                .foregroundColor(.white)
                                                .bold()
                                                .font(.caption)
                                                .frame(width: 100, alignment: .center)
                                                .padding(.bottom, 10)
                                        }
                                        .overlay(alignment: .topLeading) {
                                            StoryProfileView(
                                                story: story,
                                                showAddStatusSheet: $activeSheet
                                            )
                                            .padding(8)
                                            // Don't let avatar chrome steal/expand the card tap.
                                            .allowsHitTesting(false)
                                        }
                                        .frame(width: 100, height: 170)
                                        .clipShape(RoundedRectangle(cornerRadius: 16))
                                        .contentShape(RoundedRectangle(cornerRadius: 16))
                                        .transition(
                                            .asymmetric(
                                                insertion: .opacity
                                                    .combined(with: .scale(scale: 0.92, anchor: .leading)),
                                                removal: .opacity
                                                    .combined(with: .scale(scale: 0.9))
                                            )
                                        )
                                        .onTapGesture {
                                            statusStore.viewStatus(
                                                coord: navigationCoordinator,
                                                storyId: story.id
                                            )
                                        }
                                    }
                                }
                                .animation(
                                    statusStore.hasLoadedInitialData
                                        ? .spring(response: 0.42, dampingFraction: 0.78)
                                        : nil,
                                    value: statusStore.contactStatus.map(\.id)
                                )
                                
                            }
                            .padding(.leading,10)
                        }
                        ChannelsSectionView(
                            viewModel: channelsViewModel,
                            onOpenChannel: { channelId in
                                navigationCoordinator.navigate(to: .channelRoom(channelId: channelId))
                            },
                            onExplore: {
                                requestChannelEntry(.explore)
                            }
                        )

                        
                    }
                    
                }
               
                .navigationTitle(t(ChatTranslationKeys.STORIES_UPDATES_TITLE))
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        updatesOverflowMenu()
                    }
                }
                .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: t(ChatTranslationKeys.STORIES_SEARCH))
                .chatAppearanceSheet(isPresented: $showChannelsWelcome) {
                    ChannelsWelcomeSheet(
                        translationService: translationService,
                        onAgree: {
                            channelsIntroAccepted = true
                            showChannelsWelcome = false
                            performPendingChannelAction()
                        },
                        onDismiss: {
                            showChannelsWelcome = false
                            pendingChannelAction = nil
                        }
                    )
                }
                .chatAppearanceSheet(isPresented: $showCreateChannelIntro) {
                    ChannelCreateFlowSheet(
                        viewModel: channelsViewModel,
                        onCreated: { channel in
                            showCreateChannelIntro = false
                            navigationCoordinator.navigate(to: .channelRoom(channelId: channel.id))
                        },
                        onDismiss: { showCreateChannelIntro = false }
                    )
                }
            .onAppear{
                // Once per app session, not once per visit: `hasLoadedInitialData`
                // only ever turns true on a successful load and only resets when
                // `StoriesViewModel` is recreated (app relaunch — it is cached for
                // the app's lifetime otherwise). Live updates still arrive through
                // the MQTT/notification-driven refresh, which calls `getStatusFn()`
                // directly and is not gated by this.
                guard !statusStore.hasLoadedInitialData else { return }
                Task{
                   await statusStore.getStatusFn()
                }
            }
            .fullScreenCover(
                isPresented: Binding(
                    get: { statusStore.navigateToStatusViewer },
                    set: { presented in
                        if !presented {
                            statusStore.closeStatusViewer()
                        } else {
                            statusStore.navigateToStatusViewer = true
                        }
                    }
                )
            ) {
                DraggableFullScreenModal(
                    isPresented: Binding(
                        get: { statusStore.navigateToStatusViewer },
                        set: { presented in
                            if !presented {
                                statusStore.closeStatusViewer()
                            }
                        }
                    ),
                    content: {
                        StoryViewer(
                            statusStore: statusStore,
                            navigationCoord: navigationCoordinator,
                            translationService: translationService
                        )
                    },
                    statusStore: statusStore
                )
                .background(Color.black)
                .ignoresSafeArea()
            }

        // ============================== BOTTOM SHEET
        .chatAppearanceSheet(item: $activeSheet,onDismiss: {
            viewModel.resetSelectedMedia()
            if openStatusEditorAfterGalleryDismiss {
                openStatusEditorAfterGalleryDismiss = false
                statusStore.openStatusEditor(coord: navigationCoordinator)
            }
        }) { sheet in
                switch sheet {
                case .addStatus:
                    if #available(iOS 16.0, *) {
                        NavigationStack {
                            ScrollView {
                                VStack(spacing: 16) {
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
                                                .foregroundColor(.primary)
                                        }
                                        .frame(width: screenWidth * 0.4, height: 100)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(10)
                                        .onTapGesture {
                                            activeSheet = nil
                                            statusStore.openTextEditor(coord: navigationCoordinator)
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
                                                .foregroundColor(.primary)
                                        }
                                        .frame(width: screenWidth * 0.4, height: 100)
                                        .background(Color(.systemGray5))
                                        .cornerRadius(10)
                                        
                                        Spacer()
                                    }
                                    .padding(.horizontal)
                                    
                                    GalleryView(
                                        viewModel: viewModel,
                                        translationService: translationService,
                                        selectingEnded: { _ in
                                            statusStore.selectedMedia = viewModel.selectedMedia
                                            openStatusEditorAfterGalleryDismiss = true
                                            activeSheet = nil
                                        },
                                        onDirectSelect: { media in
                                            statusStore.selectedMedia = [media]
                                            openStatusEditorAfterGalleryDismiss = true
                                            activeSheet = nil
                                        }
                                    )
                                }
                                .padding(.top)
                            }
                            .background(Color(.systemGroupedBackground))
                            .navigationTitle(t(ChatTranslationKeys.STORIES_ADD_STATUS))
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarTrailing) {
                                    Button {
                                        activeSheet = nil
                                    } label: {
                                        Image(systemName: "xmark")
                                            .font(.footnote)
                                            .foregroundStyle(.gray)
                                            .padding(8)
                                            .background(Color(.systemGray5))
                                            .clipShape(Circle())
                                    }
                                }

                            }
                        }
                        .presentationDetents([.fraction(0.99)])
                        .presentationDragIndicator(.visible)
                    } else {
                        // Fallback on earlier versions
                    }
                    
                case .filePicker:
                    if #available(iOS 16.0, *) {
//                        MediaPicker(selectedItems: $storyVM.selectedImages)
//                            .presentationDetents([.fraction(0.99)])
//                            .presentationDragIndicator(.visible)
//                        DocumentMediaPicker(selectedURLs:$statusStore.selectedMedia , allowMultiple: true)
                    } else {
                        // Fallback on earlier versions
                    }
                }
            }
//        .onChange(of: statusStore.selectedMedia) { newItems in
//                print("selected media was setted======= \(newItems)")
//                withAnimation{
//                    goToStatusEditor = true
//                    statusStore.isFirstPageStory = false
//                }
//                
//            }
    }
}



/// Empty-state intro beside "My status" — no card chrome, just primary-tinted icons + copy.
struct StoriesEmptyIntroView: View {
    let header: String
    let photoLabel: String
    let videoLabel: String
    let textLabel: String
    var onTap: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            HStack(spacing: 28) {
                introIcon(systemName: "camera.fill", label: photoLabel)
                introIcon(systemName: "video.fill", label: videoLabel)
                introTextIcon(label: textLabel)
            }

            Text(header)
                .font(.subheadline)
                .foregroundColor(AppColors.primary)
                .multilineTextAlignment(.center)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(header)
        .accessibilityAddTraits(.isButton)
    }

    private func introIcon(systemName: String, label: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemName)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 32)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.primary)
                .lineLimit(1)
        }
    }

    private func introTextIcon(label: String) -> some View {
        VStack(spacing: 8) {
            Text("Aa")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [AppColors.primary, AppColors.primary.opacity(0.65)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(height: 32)

            Text(label)
                .font(.caption.weight(.medium))
                .foregroundColor(AppColors.primary)
                .lineLimit(1)
        }
    }
}

struct ContactStatusPreviewer:View {
     var story : Status?
     var mediaCacheRevision: Int = 0
    var body: some View {
        VStack{
            if let lastItem = story?.status.last {
                if lastItem.type == .text {
                    TextStatusViewComponent(
                        text: lastItem.content ?? "",
                        backgroundColor: Color(hex: lastItem.background ?? "#00000"),
                        width: 100,
                        height: 170,
                        cornerRadius: 16
                    )
                }else{
                    let preview = StatusLocalMediaResolver.stripPreview(
                        for: lastItem,
                        ownLocalOnly: false
                    )
                    ImageViewComponent(
                        url: preview.remoteURL,
                        isImageDataUrl: preview.isImageDataUrl,
                        width: 100,
                        height: 170,
                        cornerRadius: 16,
                        name: story?.userName ?? "user",
                        isFromDisk: preview.usesDisk,
                        imageFromDisk: preview.diskImage,
                        zoomIn: 3
                    )
                    .id("\(lastItem.codeStatus)-\(mediaCacheRevision)")
                }
            }
        }
    }
}

struct StoryProfileView: View {
    var story: Status?
    @Binding var showAddStatusSheet : ActiveSheet?
    var currentUser : Bool = false
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {

            ZStack {
                ImageViewComponent(
                    url: URL(string: story?.userImage ?? ""),
                    width: 50,
                    height: 50,
                    name: story?.userName ?? "User",
                    borderWidth: 0,
                    isMyStatusEmpty: currentUser && (story?.status.isEmpty ?? true)
                )
                if !(story?.viewed ?? false) && !currentUser {
                    Circle()
                        .stroke(AppColors.primary, lineWidth: 3)
                        .frame(width: 55, height: 55)
                }
               
            }

            if currentUser {
                ZStack {
                    Image(systemName: "plus")
                        .resizable()
                        .foregroundColor(.white)
                        .frame(width: 10, height: 10)
                        .padding(4)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                        .offset(x: 20, y: 20)
                }
                .frame(width: 50, height: 50)
                .background(Color.white.opacity(0.01))
                .onTapGesture {
                    showAddStatusSheet = .addStatus
                }
            }
        }
//        .frame(width: 50,height: 50)

    }
}

extension StoriesView {
    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    /// What the user was heading for when the explainer got in the way.
    enum ChannelEntryAction {
        case explore
        case create
    }

    /// Shows the one-time explainer before the first channel action, then does
    /// what was asked. Every later call goes straight through.
    func requestChannelEntry(_ action: ChannelEntryAction) {
        guard channelsIntroAccepted else {
            pendingChannelAction = action
            showChannelsWelcome = true
            return
        }
        perform(action)
    }

    func performPendingChannelAction() {
        guard let action = pendingChannelAction else { return }
        pendingChannelAction = nil
        perform(action)
    }

    private func perform(_ action: ChannelEntryAction) {
        switch action {
        case .explore:
            navigationCoordinator.navigate(to: .exploreChannels)
        case .create:
            // The create explainer is not one-time: it is the first step of
            // creating, and it states rules that apply every time.
            showCreateChannelIntro = true
        }
    }

    /// Tab-wide actions. Creating a channel lives here, not beside the
    /// "Channels" heading — a heading labels a list, it does not act on one.
    @ViewBuilder
    func updatesOverflowMenu() -> some View {
        Menu {
            Button {
                requestChannelEntry(.create)
            } label: {
                Label(t(ChatTranslationKeys.CHANNELS_NEW), systemImage: "dot.radiowaves.left.and.right")
            }

            Button {
                requestChannelEntry(.explore)
            } label: {
                Label(t(ChatTranslationKeys.CHANNELS_FIND_TO_FOLLOW), systemImage: "magnifyingglass")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(9)
                .background(Circle().fill(Color(.systemGray5)))
        }
    }
}
