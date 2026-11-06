import SwiftUI
import UIKit
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct ContactProfileView: View {
    /// The parts of chat the host turned on: the call buttons exist only with calls.
    @Environment(\.chatEnabledModules) private var enabledModules
    let imageTransitionNamespace: Namespace.ID
    @StateObject private var viewModel: ContactProfileViewModel
    let uploadVM: FileUploadViewModel
    @ObservedObject var chatRoomVM: ChatRoomViewModel
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @State private var showStickyTitle = false
    @State private var isMediaSheetOpened: Bool = false
    @State private var showEditContact = false
    @State private var showDisappearingMessagesSheet = false
    @State private var disappearingSaveError: String?
    @State private var showChatAppearanceSheet = false
    @State private var showShareSheet = false
    @State private var shareItems: [Any] = []
    @State private var showClearChatConfirmation = false
    @State private var showBlockConfirmation = false
    @State private var clearChatError: String?
    @State private var animationProgress: CGFloat = 0
    let navigationCoord: ChatsTabCoordinator
    /// Conversation this profile was opened from — carried into calls so they
    /// attach to the existing thread instead of creating a new one.
    private let discussionId: String

    init(
        imageTransitionNamespace: Namespace.ID,
        contactId: String,
        discussionId: String,
        chatPickerVM: ChatPartnerPickerViewModel,
        discussionUseCases: DiscussionUseCasesProtocol,
        messagesUseCases: MessagesUseCasesProtocol,
        contactsUseCases: ContactsUseCasesProtocol?,
        chatRoomVM: ChatRoomViewModel,
        fallbackPhone: String?,
        fallbackDisplayName: String?,
        uploadVM: FileUploadViewModel,
        navigationCoord: ChatsTabCoordinator
    ) {
        let user = Self.resolveProfileContact(
            contactId: contactId,
            chatPickerVM: chatPickerVM,
            fallbackPhone: fallbackPhone,
            fallbackDisplayName: fallbackDisplayName
        )
        _viewModel = StateObject(
            wrappedValue: ContactProfileViewModel(
                discussionId: discussionId,
                user: user,
                discussionUseCases: discussionUseCases,
                messagesUseCases: messagesUseCases,
                contactsUseCases: contactsUseCases,
                conversationRoomUseCases: navigationCoord.feature.conversationRoomUseCases,
                translationService: chatRoomVM.translationService
            )
        )
        self.discussionId = discussionId
        self.chatRoomVM = chatRoomVM
        self.imageTransitionNamespace = imageTransitionNamespace
        self.uploadVM = uploadVM
        self.navigationCoord = navigationCoord
    }

    private static func resolveProfileContact(
        contactId: String,
        chatPickerVM: ChatPartnerPickerViewModel,
        fallbackPhone: String?,
        fallbackDisplayName: String?
    ) -> UserContactProps? {
        if !contactId.isEmpty,
           let byId = chatPickerVM.waanguUsers.first(where: { $0.idContact == contactId }) {
            return byId
        }

        let phone = fallbackPhone?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !phone.isEmpty,
           let byPhone = chatPickerVM.waanguUsers.first(where: { $0.phone == phone }) {
            return byPhone
        }
        
        let isBlocked = chatPickerVM.waanguUsers.first(where: { $0.id == contactId })?.isBlocked ?? false
        let avatar = chatPickerVM.waanguUsers.first(where: { $0.id == contactId })?.avatar ?? ""
        let description = chatPickerVM.waanguUsers.first(where: { $0.id == contactId })?.description ?? ""
        let userId = chatPickerVM.waanguUsers.first(where: { $0.id == contactId })?.userId ?? ""
        

        let nameTrim = fallbackDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !phone.isEmpty || !nameTrim.isEmpty {
            let displayName = !nameTrim.isEmpty ? nameTrim : (!phone.isEmpty ? phone : "Unknown")
            return UserContactProps(
                idContact: contactId.isEmpty ? nil : contactId,
                userId: userId,
                name: displayName,
                avatar: avatar,
                phone: phone,
                description: description,
                isBlocked: isBlocked
            )
        }

        return nil
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Custom Navigation Bar
            contactInfoHeader

            List {
                // MARK: - HEADER (Avatar + Name + Status)
                Section {
                    VStack(spacing: 8) {
                        Circle()
                            .fill(Color.black)
                            .frame(width: 100, height: 100)
                            .overlay {
                                Group {
                                    if let imageUrl = viewModel.user?.avatar {
                                        CircularProfileImageView(imageUrl, size: .xLarge)
                                            .foregroundColor(.black.opacity(0.5))
                                    } else {
                                        Image(systemName: "person.fill")
                                            .resizable()
                                            .scaledToFit()
                                            .foregroundColor(.white)
                                            .padding(20)
                                    }
                                }
                            }

                        Text(viewModel.displayTitle)
                            .font(.title2)
                            .fontWeight(.semibold)
                            .background(
                                GeometryReader { geo in
                                    Color.clear
                                        .preference(
                                            key: ViewFrameKey.self,
                                            value: ["name": geo.frame(in: .global)]
                                        )
                                }
                            )

                        if let about = viewModel.user?.description.trimmingCharacters(in: .whitespacesAndNewlines), !about.isEmpty {
                            Text(about)
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: ViewFrameKey.self,
                                                value: ["status": geo.frame(in: .global)]
                                            )
                                    }
                                )
                        } else {
                            Color.clear
                                .frame(height: 1)
                                .background(
                                    GeometryReader { geo in
                                        Color.clear
                                            .preference(
                                                key: ViewFrameKey.self,
                                                value: ["status": geo.frame(in: .global)]
                                            )
                                    }
                                )
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .listRowBackground(Color.clear)

                // MARK: - ACTION BUTTONS
                quickActionsSection

                // MARK: - PHONE NUMBER
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(t(ChatTranslationKeys.CONTACT_INFO_MOBILE))
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        Text(viewModel.user?.phone ?? "")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }

                Section {
                    IconTitleRow(icon: "photo", title: t(ChatTranslationKeys.CONTACT_INFO_MEDIA_LINKS_DOCS), mediaCount: viewModel.totalMedia)
                        .onTapGesture {
                            isMediaSheetOpened = true
                        }
                        .chatAppearanceFullScreenCover(isPresented: $isMediaSheetOpened) {
                            ImageGallery(isMediaSheetOpened: $isMediaSheetOpened, contactVM: viewModel, uploadVM: uploadVM, chatRoomVM: chatRoomVM, userName: viewModel.displayTitle)
                        }
                }

                // MARK: - SETTINGS
                Section {
                    BrandedToggle(
                        t(ChatTranslationKeys.CONTACT_INFO_MUTE_NOTIFICATIONS),
                        systemImage: "bell.slash",
                        isOn: Binding(
                            get: { viewModel.isMuted },
                            set: { newValue in
                                Task { @MainActor in
                                    try? await viewModel.setMuted(newValue)
                                    viewModel.reloadMuteFromStore()
                                }
                            }
                        )
                    )
                    IconTitleRow(
                        icon: "paintpalette",
                        title: t(ChatTranslationKeys.CONTACT_INFO_CHAT_APPEARANCE),
                        subtitle: appearanceStore.defaultAppearance.displayName(
                            translationService: chatRoomVM.translationService
                        )
                    )
                    .onTapGesture {
                        showChatAppearanceSheet = true
                    }
                    IconTitleRow(
                        icon: "timer",
                        title: t(ChatTranslationKeys.CONTACT_INFO_DISAPPEARING),
                        subtitle: viewModel.disappearingDuration.displayName
                    )
                    .onTapGesture {
                        showDisappearingMessagesSheet = true
                    }
                }

                Section {
                    IconTitleRow(icon: "square.and.arrow.up", title: t(ChatTranslationKeys.CONTACT_INFO_SHARE_CONTACT))
                        .onTapGesture {
                            let name = viewModel.displayTitle
                            let phone = viewModel.user?.phone ?? ""
                            let lines = [name, phone].filter { !$0.isEmpty }
                            shareItems = [lines.joined(separator: "\n")]
                            showShareSheet = true
                        }
                }

                Section {
                    VStack(spacing: 12){
                        
                        IconTitleRow(icon: "trash", title: t(ChatTranslationKeys.CONTACT_INFO_CLEAR_CHAT_ACTION), isDestructive: true)
                                              .onTapGesture {
                                                  withAnimation{
                                                      showClearChatConfirmation = true
                                                  }
                                                  
                                              }
                        IconTitleRow(
                            icon: viewModel.user?.isBlocked == true ? "checkmark.circle" : "nosign", 
                            title: "\(viewModel.user?.isBlocked == true ? t(ChatTranslationKeys.CONTACT_INFO_UNBLOCK_TITLE) : t(ChatTranslationKeys.CONTACT_INFO_BLOCK_TITLE)) \(viewModel.user?.name ?? "")", 
                            isDestructive: true
                        )
                                              .onTapGesture {
                                                  withAnimation{
                                                      showBlockConfirmation = true
                                                  }
                                                  
                                              }
                    }
                  
                }
            }
            .listStyle(.insetGrouped)

            // MARK: - Scroll listener
            .onPreferenceChange(ViewFrameKey.self) { frames in
                if let nameFrame = frames["name"], let statusFrame = frames["status"] {
                    let navigationBarBottom: CGFloat = 100

                    let nameIsCompletelyHidden = nameFrame.maxY < navigationBarBottom
                    let statusIsCompletelyHidden = statusFrame.maxY < navigationBarBottom

                    let maxY = max(nameFrame.maxY, statusFrame.maxY)
                    let distanceFromTop = max(navigationBarBottom - maxY, 0)
                    let progress = min(distanceFromTop / 30, 1)

                    animationProgress = progress

                    let newSticky = nameIsCompletelyHidden && statusIsCompletelyHidden
                    if newSticky != showStickyTitle {
                        withAnimation(.easeOut(duration: 0.3)) {
                            showStickyTitle = newSticky
                        }
                    }
                }
            }
        }
        .onAppear {
            appearanceStore.reloadFromPersistence()
            viewModel.reloadDisappearingFromStore()
            viewModel.reloadMuteFromStore()
        }
        .onChange(of: chatRoomVM.messages) { _ in
            viewModel.onUpdateNewMessages(chatRoomVM.messages)
        }
        .chatAppearanceSheet(isPresented: $showDisappearingMessagesSheet) {
            NavigationView {
                List {
                    ForEach(DisappearingDuration.allCases, id: \.rawValue) { option in
                        Button {
                            Task { @MainActor in
                                do {
                                    try await viewModel.setDisappearingMessages(option)
                                    showDisappearingMessagesSheet = false
                                    disappearingSaveError = nil
                                } catch {
                                    disappearingSaveError = error.localizedDescription
                                }
                            }
                        } label: {
                            HStack {
                                Text(option.displayName)
                                    .foregroundColor(.primary)
                                Spacer()
                                if viewModel.disappearingDuration == option {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(t(ChatTranslationKeys.CONTACT_INFO_DISAPPEARING))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(common("done")) {
                            showDisappearingMessagesSheet = false
                        }
                    }
                }
            }
        }
        .alert(t(ChatTranslationKeys.CONTACT_INFO_COULD_NOT_SAVE), isPresented: .init(
            get: { disappearingSaveError != nil },
            set: { if !$0 { disappearingSaveError = nil } }
        )) {
            Button(common("ok"), role: .cancel) { disappearingSaveError = nil }
        } message: {
            Text(disappearingSaveError ?? "")
        }
        .chatAppearanceSheet(isPresented: $showChatAppearanceSheet) {
            NavigationStack {
                ChatAppearancePickerView(
                    translationService: chatRoomVM.translationService
                )
            }
        }
        .chatAppearanceSheet(isPresented: $showShareSheet) {
            ActivityShareSheet(activityItems: shareItems)
        }
        // MARK: - Custom Dialogs with Full Animation Control
        .customDialog(
            isPresented: $showClearChatConfirmation,
            configuration: DialogConfiguration(
                title: t(ChatTranslationKeys.CONTACT_INFO_CLEAR_CHAT_TITLE),
                message: t(ChatTranslationKeys.CONTACT_INFO_CLEAR_CHAT_MESSAGE),
                style: .destructive,
                buttons: [
                    DialogButton(title: t(ChatTranslationKeys.CONTACT_INFO_CLEAR_CHAT_ACTION), role: .destructive) {
                        Task {
                            do {
                                try await chatRoomVM.clearAllMessagesLocally()
                                viewModel.onUpdateNewMessages(chatRoomVM.messages)
                            } catch {
                                clearChatError = error.localizedDescription
                            }
                        }
                    },
                    DialogButton(title: common("cancel"), role: .cancel) {}
                ],
                animation: .spring
            )
        )
        .customDialog(
            isPresented: $showBlockConfirmation,
            configuration: DialogConfiguration(
                title: viewModel.user?.isBlocked == true ? t(ChatTranslationKeys.CONTACT_INFO_UNBLOCK_TITLE) : t(ChatTranslationKeys.CONTACT_INFO_BLOCK_TITLE),
                message: viewModel.user?.isBlocked == true
                    ? t(ChatTranslationKeys.CONTACT_INFO_UNBLOCK_MESSAGE, args: [viewModel.user?.name ?? ""])
                    : t(ChatTranslationKeys.CONTACT_INFO_BLOCK_MESSAGE, args: [viewModel.user?.name ?? ""]),
                style: viewModel.user?.isBlocked == true ? .standard : .destructive,
                buttons: [
                    DialogButton(
                        title: viewModel.user?.isBlocked == true ? t(ChatTranslationKeys.CONTACT_INFO_UNBLOCK_TITLE) : t(ChatTranslationKeys.CONTACT_INFO_BLOCK_TITLE),
                        role: viewModel.user?.isBlocked == true ? .primary : .destructive
                    ) {
                        Task {
                            await viewModel.toggleBlockContact()
                            if viewModel.blockError == nil {
                                showBlockConfirmation = false
                            }
                        }
                    },
                    DialogButton(title: common("cancel"), role: .cancel) {}
                ],
                animation: .bouncy
            )
        )
        .customAlert(
            title: t(ChatTranslationKeys.CONTACT_INFO_CLEAR_CHAT_TITLE),
            message: clearChatError,
            isPresented: .init(
                get: { clearChatError != nil },
                set: { if !$0 { clearChatError = nil } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { clearChatError = nil }
        )
        .customAlert(
            title: t(ChatTranslationKeys.CONTACT_INFO_BLOCK_ERROR),
            message: viewModel.blockError,
            isPresented: .init(
                get: { viewModel.blockError != nil },
                set: { if !$0 { viewModel.blockError = nil } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { viewModel.blockError = nil }
        )
    }

    // MARK: - Custom Navigation Header
    @ViewBuilder
    private var contactInfoHeader: some View {
        HStack {
            Button {
                navigationCoord.pop()
            } label: {
                Image(systemName: "chevron.backward")
                    .foregroundColor(.blue)
            }

            Spacer()

            ZStack {
                Text(t(ChatTranslationKeys.CONTACT_INFO_TITLE))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .offset(y: animationProgress * -15)
                    .opacity(1 - animationProgress)

                VStack(spacing: 2) {
                    Text(viewModel.displayTitle)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .offset(y: (1 - animationProgress) * 10)

                    if let about = viewModel.user?.description.trimmingCharacters(in: .whitespacesAndNewlines), !about.isEmpty {
                        Text(about)
                            .font(.caption)
                            .foregroundColor(.gray)
                            .offset(y: (1 - animationProgress) * 8)
                    }
                }
                .offset(y: animationProgress * -5)
                .opacity(animationProgress)
            }
            .frame(height: 40)
            .clipped()

            Spacer()

            if viewModel.user != nil {
                Button(t(ChatTranslationKeys.CONTACT_INFO_EDIT)) {
                    showEditContact = true
                }
                .chatAppearanceSheet(isPresented: $showEditContact) {
                    NewContactView(
                        draft: viewModel.user.map(ContactDraft.init(user:)),
                        translationService: chatRoomVM.translationService
                    )
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }
    
    private var quickActionsSection: some View {
        Section {
            HStack(spacing: 10) {
                if enabledModules.contains(.calls) {
                    quickActionButton(icon: "phone", title: t(ChatTranslationKeys.CONTACT_INFO_AUDIO)) {
                        VoipManager.shared.startOutgoingCall(
                            to: viewModel.user?.phone ?? "",
                            hasVideo: false,
                            name: viewModel.displayTitle,
                            image: viewModel.user?.avatar,
                            conversationId: discussionId,
                            userId: viewModel.user?.userId
                        )
                    }
                    Divider()
                    quickActionButton(icon: "video", title: t(ChatTranslationKeys.CONTACT_INFO_VIDEO)) {
                        VoipManager.shared.startOutgoingCall(
                            to: viewModel.user?.phone ?? "",
                            hasVideo: true,
                            name: viewModel.displayTitle,
                            image: viewModel.user?.avatar,
                            conversationId: discussionId,
                            userId: viewModel.user?.userId
                        )
                    }
                }
           
//                quickActionButton(icon: "person.badge.plus", title: "Add") {
//                    showAddParticipant = true
//                }
//                quickActionButton(icon: "magnifyingglass", title: "Search") {
//                    showSearchMembersSheet = true
//                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .listRowInsets(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
    }
    
    // MARK: - Action Button Component
//    func actionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
//        Button(action: action) {
//            VStack(spacing: 6) {
//                Image(systemName: icon)
//                    .resizable()
//                    .scaledToFit()
//                    .frame(width: 25, height: 25)
//                    .foregroundColor(.blue)
//
//                Text(title)
//                    .font(.caption)
//                    .foregroundColor(.primary)
//            }
//            .frame(maxHeight: .infinity)
//            .frame(width: UIScreen.main.bounds.width / 6.5)
//            .background(Color.white)
//            .cornerRadius(12)
//            .shadow(color: .gray.opacity(0.3), radius: 4, x: 0, y: 2)
//        }
//    }
    
    private func quickActionButton(icon: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(AppColors.primary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        chatRoomVM.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }

    private func common(_ key: String) -> String {
        chatRoomVM.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? key.capitalized
    }
}

// MARK: - Preference Key
struct ViewFrameKey: PreferenceKey {
    static var defaultValue: [String: CGRect] = [:]
    
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}


struct IconTitleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    var isDestructive = false
    var mediaCount : Int = 0
    var body: some View {
        HStack {
//            if !isDestructive {
                Image(systemName: icon)
                   .foregroundColor(isDestructive ? .red : .secondary)
                    .font(.system(size: 24, weight: .regular))
//            }
           
                 
            VStack(alignment: .leading) {
                Text(title)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(isDestructive ? .red : .primary)
                if let descr = subtitle {
                    Text(descr)
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }
               
                   
            }
            if !isDestructive {
                HStack {
                    if mediaCount > 0 {
                        Text("\(mediaCount)")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
               
            }
           
         }
        .contentShape(Rectangle())
    }
}






