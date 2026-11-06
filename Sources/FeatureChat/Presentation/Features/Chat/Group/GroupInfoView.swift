import SwiftUI
import Combine
import WaanguSharedUI
import UIKit
import CoreImage.CIFilterBuiltins
import WaanguCoreKit

@available(iOS 17.0, *)
struct GroupInfoView: View {
    /// The parts of chat the host turned on: the call buttons exist only with calls.
    @Environment(\.chatEnabledModules) private var enabledModules

    @StateObject private var viewModel: GroupInfoViewModel
    let navigationCoord: ChatsTabCoordinator
    @State private var showAddParticipant = false
    @State private var showEditGroupInfo = false
    @State private var showChatAppearanceSheet = false
    @State private var showDisappearingMessagesSheet = false
    @State private var showClearChatConfirmation = false
    @State private var showInviteLinkSheet = false
    @State private var showGroupAdminsSheet = false
    @State private var selectedMemberForActions: GroupMember?
    @State private var showSearchMembersSheet = false
    @State private var clearChatError: String?
    @State private var disappearingSaveError: String?
    @State private var memberActionMessage: String?
    @State private var lockChatEnabled = false
    @State private var advancedPrivacyEnabled = false
    @State private var saveToPhotosEnabled = true
    @State private var contactUseCase:ContactsUseCasesProtocol
    @ObservedObject private var chatRoomVM: ChatRoomViewModel
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared

    init(
        discussionId: String,
        groupName: String,
        chatRoomVM: ChatRoomViewModel,
        discussionUseCases: DiscussionUseCasesProtocol,
        groupUseCases: GroupUseCasesProtocol,
        groupPermissionsUseCases: GroupPermissionsUseCasesProtocol,
        contactUseCase:ContactsUseCasesProtocol,
        navigationCoord: ChatsTabCoordinator,
        fileUploadUseCases: FileUplaodUseCasesProtocol? = nil
    ) {
        _viewModel = StateObject(wrappedValue: GroupInfoViewModel(
            discussionId: discussionId,
            groupName: groupName,
            chatRoomVM: chatRoomVM,
            discussionUseCases: discussionUseCases,
            groupUseCases: groupUseCases,
            groupPermissionsUseCases: groupPermissionsUseCases,
            fileUploadUseCases: fileUploadUseCases
        ))
        self.chatRoomVM = chatRoomVM
        self.contactUseCase = contactUseCase
        self.navigationCoord = navigationCoord
    }

    var body: some View {
        VStack(spacing: 0) {
            groupInfoHeader
            List {
                groupHeaderSection
                if !viewModel.hasLeftGroup {
                    quickActionsSection
                    settingsSection
                    mediaSection
                }
                membersSection
                if !viewModel.hasLeftGroup {
                    pendingJoinRequestsSection
                    permissionsNavigationSection
                }
                actionsSection
            }
            .listStyle(.insetGrouped)
            .disabled(viewModel.isLoading)
        }
        .overlay {
            if viewModel.isLoading {
                ZStack {
                    Color.black.opacity(0.25)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.large)
                        if let message = viewModel.loadingMessage {
                            Text(message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .onAppear {
            appearanceStore.reloadFromPersistence()
            viewModel.reloadDisappearingFromStore()
            viewModel.reloadMuteFromStore()
            viewModel.reloadGroupFromStore()
            lockChatEnabled = viewModel.loadLocalBoolSetting(key: "lockChat")
            advancedPrivacyEnabled = viewModel.loadLocalBoolSetting(key: "advancedPrivacy")
            saveToPhotosEnabled = viewModel.loadLocalBoolSetting(key: "saveToPhotos", defaultValue: true)
            Task {
                await viewModel.refreshPendingJoinRequests()
            }
        }
        .alert(t(ChatTranslationKeys.GROUP_INFO_ERROR_TITLE), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button(common("ok")) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
        .chatAppearanceSheet(isPresented: $showAddParticipant) {
            addParticipantSheet
        }
        .chatAppearanceSheet(isPresented: $showEditGroupInfo) {
            EditGroupInfoSheet(
                groupName: viewModel.group.name,
                groupDescription: viewModel.group.description ?? "",
                currentAvatarUrl: viewModel.group.avatarUrl,
                translationService: chatRoomVM.translationService,
                onSave: { name, description, avatarEdit in
                    viewModel.updateGroupInfo(
                        name: name,
                        description: description,
                        avatarEdit: avatarEdit
                    )
                }
            )
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
                                        .foregroundColor(AppColors.primary)
                                }
                            }
                        }
                    }
                }
                .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_DISAPPEARING))
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
        .chatAppearanceSheet(isPresented: $showChatAppearanceSheet) {
            NavigationStack {
                ChatAppearancePickerView(
                    translationService: chatRoomVM.translationService
                )
            }
        }
        .chatAppearanceSheet(isPresented: $showInviteLinkSheet) {
            GroupInviteLinkSheet(
                inviteLink: chatRoomVM.groupInviteLink,
                hasInviteLink: chatRoomVM.hasInviteLink,
                isLoading: $chatRoomVM.isLoadingInviteLink,
                loadingMessage: chatRoomVM.inviteLinkLoadingMessage,
                translationService: chatRoomVM.translationService,

                onRegenerate: { chatRoomVM.regenerateInviteLink() }
            )
        }
        .chatAppearanceSheet(isPresented: $showGroupAdminsSheet) {
            GroupAdminsSheet(
                admins: viewModel.sortedMembers.filter { $0.role == .ADMIN },
                discussionId: viewModel.discussionId,
                translationService: chatRoomVM.translationService
            )
        }
        .chatAppearanceSheet(isPresented: $showSearchMembersSheet) {
            GroupMembersSearchSheet(
                members: viewModel.sortedMembers,
                translationService: chatRoomVM.translationService,
                onSelectMember: { member in
                    selectedMemberForActions = member
                }
            )
        }
        .chatAppearanceSheet(item: $selectedMemberForActions) { member in
            GroupMemberActionsSheet(
                member: member,
                isCurrentUserAdmin: viewModel.isAdmin,
                currentUserId: CurrentSessionInfo.shared.currentUid,
                translationService: chatRoomVM.translationService,
                onMessage: {
                    memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_MEMBER_DM_SOON)
                },
                onAudio: {
                    memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_MEMBER_AUDIO_SOON)
                },
                onVideo: {
                    memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_MEMBER_VIDEO_SOON)
                },
                onInfo: {
                    memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_MEMBER_PROFILE_SOON)
                },
                onMakeAdmin: {
                    selectedMemberForActions = nil
                    viewModel.promoteToAdmin(member)
                },
                onDismissAdmin: {
                    selectedMemberForActions = nil
                    viewModel.demoteFromAdmin(member)
                },
                onRemoveMember: {
                    selectedMemberForActions = nil
                    viewModel.removeMember(member)
                }
            )
            .presentationDetents([.fraction(0.52)])
            .presentationDragIndicator(.visible)
        }
        .customDialog(
            isPresented: $showClearChatConfirmation,
            configuration: DialogConfiguration(
                title: t(ChatTranslationKeys.GROUP_INFO_CLEAR_CHAT_TITLE),
                message: t(ChatTranslationKeys.GROUP_INFO_CLEAR_CHAT_MESSAGE),
                style: .destructive,
                buttons: [
                    DialogButton(title: t(ChatTranslationKeys.GROUP_INFO_CLEAR_CHAT_ACTION), role: .destructive) {
                        Task {
                            do {
                                try await chatRoomVM.clearAllMessagesLocally()
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
        .customAlert(
            title: t(ChatTranslationKeys.GROUP_INFO_COULD_NOT_CLEAR_CHAT),
            message: clearChatError,
            isPresented: .init(
                get: { clearChatError != nil },
                set: { if !$0 { clearChatError = nil } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { clearChatError = nil }
        )
        .alert(t(ChatTranslationKeys.GROUP_INFO_COULD_NOT_SAVE), isPresented: .init(
            get: { disappearingSaveError != nil },
            set: { if !$0 { disappearingSaveError = nil } }
        )) {
            Button(common("ok"), role: .cancel) { disappearingSaveError = nil }
        } message: {
            Text(disappearingSaveError ?? "")
        }
        .alert(t(ChatTranslationKeys.GROUP_INFO_ACTION_UNAVAILABLE), isPresented: .init(
            get: { memberActionMessage != nil },
            set: { if !$0 { memberActionMessage = nil } }
        )) {
            Button(common("ok"), role: .cancel) { memberActionMessage = nil }
        } message: {
            Text(memberActionMessage ?? "")
        }
        .discussionDeletionDialog(
            context: $viewModel.deletionDialog,
            translationService: chatRoomVM.translationService,
            onPrimary: {
                Task {
                    let shouldPop = await viewModel.confirmDeletionPrimaryAction()
                    if shouldPop {
                        navigationCoord.popToRoot()
                    }
                }
            },
            onDeleteLocalContent: {
                Task {
                    let shouldPop = await viewModel.confirmDeleteLocalContent()
                    if shouldPop {
                        navigationCoord.popToRoot()
                    }
                }
            },
            onLeaveGroup: {
                Task {
                    _ = await viewModel.confirmLeaveGroupFromDialog()
                }
            },
            onExitKeepLocally: {
                Task {
                    await viewModel.confirmExitAndKeepLocally()
                }
            },
            onExitDeleteLocally: {
                Task {
                    let shouldPop = await viewModel.confirmExitAndDeleteLocally()
                    if shouldPop {
                        navigationCoord.popToRoot()
                    }
                }
            }
        )
        .alert(
            t(ChatTranslationKeys.GROUP_INFO_DELETION_FAILED),
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
    }

    private var addParticipantSheet: some View {
        AddParticipantSheet(
            existingPhones: Set(viewModel.group.members.map { $0.phone }),
            onAdd: { contacts in
                let added = await viewModel.addMembers(contacts)
                if added {
                    showAddParticipant = false
                }
                return added
            },
            contactUseCase: contactUseCase,
            groupLocalId: viewModel.group.localId,
            groupServerId: viewModel.group.serverId,
            isAdmin: viewModel.isAdmin,
            permissionsUseCases: viewModel.groupPermissionsUseCases,
            translationService: chatRoomVM.translationService
        )
    }

    // MARK: - Navigation Header

    private var groupInfoHeader: some View {
        HStack {
            Button {
                navigationCoord.pop()
            } label: {
                Image(systemName: "chevron.backward")
                    .foregroundColor(AppColors.primary)
            }

            Spacer()

            Text(viewModel.hasLeftGroup ? viewModel.group.name : t(ChatTranslationKeys.GROUP_INFO_TITLE))
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Spacer()

            Color.clear.frame(width: 24)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: 50)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea(edges: .top)
        }
    }

    // MARK: - Header

    private var groupHeaderSection: some View {
        Section {
            GroupChatIntroHeaderView(
                name: viewModel.group.name,
                description: viewModel.group.description,
                memberCount: viewModel.hasLeftGroup
                    ? viewModel.activeMemberCount
                    : viewModel.group.memberCount,
                avatarUrl: viewModel.group.avatarUrl,
                showsLeftGroupNotice: viewModel.hasLeftGroup,
                showsEditButton: !viewModel.hasLeftGroup && viewModel.canEditGroupInfo,
                onEditTapped: { showEditGroupInfo = true },
                translationService: chatRoomVM.translationService
            )
            .padding(.vertical)
        }
    }
    
    // MARK: - Quick Actions

    /// Active group members except this device, converted to call invitees and
    /// capped at the room limit. Matches §11: all callees ride the initial
    /// `call-offer`, so the waiting grid is populated the instant you tap call.
    private var groupCallInvitees: [CallInvitee] {
        let selfId = CurrentSessionInfo.shared.currentUid
        let selfPhone = CurrentSessionInfo.shared.userPhoneNumber
        return viewModel.group.members
            .filter { $0.isActive && $0.userId != selfId && $0.phone != selfPhone }
            .prefix(VoipManager.maxParticipants)
            .map { CallInvitee(userId: $0.userId, name: $0.name, phone: $0.phone) }
    }

    private var quickActionsSection: some View {
        Section {
            HStack(spacing: 10) {
                if enabledModules.contains(.calls) {
                    quickActionButton(icon: "phone", title: t(ChatTranslationKeys.CONTACT_INFO_AUDIO)) {
                        let invitees = groupCallInvitees
                        guard !invitees.isEmpty else {
                            memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_AUDIO_SOON)
                            return
                        }
                        VoipManager.shared.startGroupCall(
                            invitees,
                            hasVideo: false,
                            conversationId: viewModel.discussionId
                        )
                    }
                    quickActionButton(icon: "video", title: t(ChatTranslationKeys.CONTACT_INFO_VIDEO)) {
                        let invitees = groupCallInvitees
                        guard !invitees.isEmpty else {
                            memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_VIDEO_SOON)
                            return
                        }
                        VoipManager.shared.startGroupCall(
                            invitees,
                            hasVideo: true,
                            conversationId: viewModel.discussionId
                        )
                    }
                }
                quickActionButton(icon: "person.badge.plus", title: t(ChatTranslationKeys.GROUP_INFO_ADD_PARTICIPANTS)) {
                    showAddParticipant = true
                }
                quickActionButton(icon: "magnifyingglass", title: t(ChatTranslationKeys.GROUP_INFO_SEARCH)) {
                    showSearchMembersSheet = true
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 2)
        }
        .listRowInsets(.init(top: 10, leading: 12, bottom: 10, trailing: 12))
    }

    // MARK: - Media

    private var mediaSection: some View {
        Section {
            HStack {
                Image(systemName: "photo")
                    .foregroundColor(.secondary)
                    .font(.system(size: 24))

                Text(t(ChatTranslationKeys.GROUP_INFO_MEDIA_LINKS_DOCS))
                    .frame(maxWidth: .infinity, alignment: .leading)

                let count = viewModel.mediaCount
                if count > 0 {
                    Text("\(count)")
                        .font(.headline)
                        .foregroundColor(.primary)
                }
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
        }
    }

    // MARK: - Members

    private var membersSection: some View {
        Section {
            if !viewModel.hasLeftGroup {
                if viewModel.canAddMembers {
                    Button {
                        showAddParticipant = true
                    } label: {
                        Label(t(ChatTranslationKeys.GROUP_INFO_ADD_PARTICIPANT), systemImage: "person.badge.plus")
                            .foregroundStyle(AppColors.primary)
                    }
                }
                
                Button {
                    showInviteLinkSheet = true
                } label: {
                    Label(t(ChatTranslationKeys.GROUP_INFO_INVITE_VIA_LINK), systemImage: "link")
                        .foregroundStyle(AppColors.primary)
                }
                
                Button {
                    showGroupAdminsSheet = true
                } label: {
                    Label(t(ChatTranslationKeys.GROUP_INFO_ADMINS), systemImage: "person.2.badge.gearshape")
                        .foregroundStyle(AppColors.primary)
                }
            }

            ForEach(viewModel.sortedMembers) { member in
                memberRow(member)
            }
        } header: {
            Text(t(ChatTranslationKeys.GROUP_INFO_PARTICIPANT_COUNT, args: ["\(viewModel.activeMemberCount)"]))
        }
    }

    private func memberRow(_ member: GroupMember) -> some View {
        HStack(spacing: 12) {
            if let avatar = member.avatar, !avatar.isEmpty {
                CircularProfileImageView(avatar, size: .xSmall)
            } else {
                Circle()
                    .fill(Color(.systemGray4))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Text(String(member.name.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(member.userId == CurrentSessionInfo.shared.currentUid ? common("you") : member.name)
                        .font(.subheadline.weight(.medium))
                    if member.role == .ADMIN {
                        Text(t(ChatTranslationKeys.GROUP_INFO_ADMIN_BADGE))
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.12))
                            .foregroundStyle(AppColors.primary)
                            .clipShape(Capsule())
                    }
                }
                Text(member.phone)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .contextMenu {
            if viewModel.isAdmin && member.userId != CurrentSessionInfo.shared.currentUid {
                if member.role == .MEMBER {
                    Button {
                        viewModel.promoteToAdmin(member)
                    } label: {
                        Label(t(ChatTranslationKeys.GROUP_INFO_MAKE_ADMIN), systemImage: "shield.checkered")
                    }
                } else {
                    Button {
                        viewModel.demoteFromAdmin(member)
                    } label: {
                        Label(t(ChatTranslationKeys.GROUP_INFO_DISMISS_ADMIN), systemImage: "shield.slash")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    viewModel.removeMember(member)
                } label: {
                    Label(t(ChatTranslationKeys.GROUP_INFO_REMOVE_FROM_GROUP), systemImage: "person.badge.minus")
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedMemberForActions = member
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        Section {
            BrandedToggle(
                t(ChatTranslationKeys.GROUP_INFO_MUTE_NOTIFICATIONS),
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
                title: t(ChatTranslationKeys.GROUP_INFO_CHAT_APPEARANCE),
                subtitle: appearanceStore.defaultAppearance.displayName(
                    translationService: chatRoomVM.translationService
                )
            )
            .onTapGesture {
                showChatAppearanceSheet = true
            }
            
            IconTitleRow(
                icon: "timer",
                title: t(ChatTranslationKeys.GROUP_INFO_DISAPPEARING),
                subtitle: viewModel.disappearingDuration.displayName
            )
            .onTapGesture {
                showDisappearingMessagesSheet = true
            }
            
            IconTitleRow(icon: "star", title: t(ChatTranslationKeys.GROUP_INFO_STARRED), subtitle: t(ChatTranslationKeys.GROUP_INFO_NONE))
            
            BrandedToggle(
                t(ChatTranslationKeys.GROUP_INFO_SAVE_TO_PHOTOS),
                systemImage: "square.and.arrow.down",
                isOn: Binding(
                    get: { saveToPhotosEnabled },
                    set: { newValue in
                        saveToPhotosEnabled = newValue
                        viewModel.persistLocalBoolSetting(key: "saveToPhotos", value: newValue)
                    }
                )
            )
            
            BrandedToggle(
                t(ChatTranslationKeys.GROUP_INFO_LOCK_CHAT),
                systemImage: "lock",
                isOn: Binding(
                    get: { lockChatEnabled },
                    set: { newValue in
                        lockChatEnabled = newValue
                        viewModel.persistLocalBoolSetting(key: "lockChat", value: newValue)
                    }
                )
            )
            
            BrandedToggle(
                t(ChatTranslationKeys.GROUP_INFO_ADVANCED_PRIVACY),
                systemImage: "shield.lefthalf.filled",
                isOn: Binding(
                    get: { advancedPrivacyEnabled },
                    set: { newValue in
                        advancedPrivacyEnabled = newValue
                        viewModel.persistLocalBoolSetting(key: "advancedPrivacy", value: newValue)
                    }
                )
            )
            
            // B61 — pas de ligne « chiffré de bout en bout » tant que c'est faux.
            if ChatEncryptionClaim.messagesAreEndToEndEncrypted {
                IconTitleRow(
                    icon: "lock.shield",
                    title: t(ChatTranslationKeys.GROUP_INFO_ENCRYPTION),
                    subtitle: t(ChatTranslationKeys.GROUP_INFO_ENCRYPTION_SUBTITLE)
                )
            }
            
            IconTitleRow(
                icon: "person.3",
                title: t(ChatTranslationKeys.GROUP_INFO_ADD_TO_COMMUNITY)
            )
            .onTapGesture {
                memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_COMMUNITY_SOON)
            }
            
            IconTitleRow(
                icon: "plus.bubble",
                title: t(ChatTranslationKeys.GROUP_INFO_CREATE_SIMILAR_GROUP)
            )
            .onTapGesture {
                memberActionMessage = t(ChatTranslationKeys.GROUP_INFO_SIMILAR_GROUP_SOON)
            }
        }
    }

    // MARK: - Pending Join Requests

    @ViewBuilder
    private var pendingJoinRequestsSection: some View {
        if viewModel.isAdmin && viewModel.isJoinApprovalRequired {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: "person.badge.clock")
                        .foregroundColor(.black.opacity(0.6))
                        .font(.system(size: 24))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(t(ChatTranslationKeys.GROUP_INFO_PENDING_JOIN_REQUESTS))
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if viewModel.pendingJoinRequestCount > 0 {
                            Text(t(ChatTranslationKeys.GROUP_INFO_WAITING_APPROVAL, args: ["\(viewModel.pendingJoinRequestCount)"]))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text(t(ChatTranslationKeys.GROUP_INFO_REVIEW_REQUESTS))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    if viewModel.pendingJoinRequestCount > 0 {
                        Text("\(viewModel.pendingJoinRequestCount)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColors.primary, in: Capsule())
                    }

                    Image(systemName: "chevron.right")
                        .foregroundColor(.gray)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    let route: ChatsTabRoute = .pendingJoinRequests(
                        discussionId: viewModel.discussionId,
                        groupName: viewModel.group.name
                    )
                    navigationCoord.push(route)
                }
            }
        }
    }

    // MARK: - Permissions Navigation

    private var permissionsNavigationSection: some View {
        Section {
            HStack {
                Image(systemName: "lock.shield")
                    .foregroundColor(.black.opacity(0.6))
                    .font(.system(size: 24))
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(t(ChatTranslationKeys.GROUP_INFO_PERMISSIONS))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    
                    if viewModel.isAdmin {
                        Text(t(ChatTranslationKeys.GROUP_INFO_MANAGE_PERMISSIONS))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text(t(ChatTranslationKeys.GROUP_INFO_VIEW_PERMISSIONS))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.gray)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                let route: ChatsTabRoute = .groupPermissions(
                    discussionId: viewModel.discussionId,
                    groupName: viewModel.group.name
                )
                navigationCoord.push(route)
            }
        }
    }

    // MARK: - Actions

    private var actionsSection: some View {
        Section {
            if viewModel.hasLeftGroup {
                Button(role: .destructive) {
                    Task {
                        let shouldPop = await viewModel.deleteLocalGroupCopy()
                        if shouldPop {
                            navigationCoord.popToRoot()
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(t(ChatTranslationKeys.GROUP_INFO_DELETE_GROUP))
                    }
                    .foregroundStyle(.red)
                }
            } else {
                IconTitleRow(icon: "trash", title: t(ChatTranslationKeys.GROUP_INFO_CLEAR_CHAT), isDestructive: true)
                    .onTapGesture {
                        showClearChatConfirmation = true
                    }
                
                if viewModel.isCurrentUserActiveMember {
                    Button(role: .destructive) {
                        viewModel.beginDeletion(intent: .exitGroup)
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.portrait.and.arrow.right")
                            Text(t(ChatTranslationKeys.GROUP_INFO_EXIT_GROUP))
                        }
                        .foregroundStyle(.red)
                    }
                }

                Button(role: .destructive) {
                    viewModel.beginDeletion(intent: .deleteFromGroupInfo)
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text(t(ChatTranslationKeys.GROUP_INFO_DELETE_CONVERSATION))
                    }
                    .foregroundStyle(.red)
                }
            }
        }
    }
    
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

// MARK: - Add Participant Sheet

@available(iOS 17.0, *)
struct AddParticipantSheet: View {
    @Environment(\.dismiss) private var dismiss
    let existingPhones: Set<String>
    let onAdd: ([UserContactProps]) async -> Bool
    let groupLocalId: String?
    let groupServerId: String?
    let isAdmin: Bool
    let permissionsUseCases: GroupPermissionsUseCasesProtocol?
    let translationService: (any TranslationServiceProtocol)?

    @State private var selected: [UserContactProps] = []
    @State private var searchText = ""
    @State private var isAdding = false
    @ObservedObject private var contactsVM:AddParticipantContactsVM
    
    init(
        existingPhones: Set<String>,
        onAdd: @escaping ([UserContactProps]) async -> Bool,
        contactUseCase: ContactsUseCasesProtocol,
        groupLocalId: String? = nil,
        groupServerId: String? = nil,
        isAdmin: Bool = false,
        permissionsUseCases: GroupPermissionsUseCasesProtocol? = nil,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        self.existingPhones = existingPhones
        self.onAdd = onAdd
        self.groupLocalId = groupLocalId
        self.groupServerId = groupServerId
        self.isAdmin = isAdmin
        self.permissionsUseCases = permissionsUseCases
        self.translationService = translationService
        self.contactsVM = AddParticipantContactsVM(contactUseCases: contactUseCase)
    }

    private var availableContacts: [UserContactProps] {
        let filtered = contactsVM.waanguUsers.filter { !existingPhones.contains($0.phone) }
        if searchText.isEmpty { return filtered }
        return filtered.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.contains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if !selected.isEmpty {
                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(selected) { contact in
                                    VStack(spacing: 4) {
                                        ZStack(alignment: .topTrailing) {
                                            Circle()
                                                .fill(Color(.systemGray4))
                                                .frame(width: 44, height: 44)
                                                .overlay {
                                                    Text(String(contact.name.prefix(1)).uppercased())
                                                        .font(.headline)
                                                        .foregroundStyle(.white)
                                                }
                                            Button {
                                                selected.removeAll { $0.id == contact.id }
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.caption)
                                                    .foregroundStyle(.white, .gray)
                                            }
                                        }
                                        Text(contact.name.components(separatedBy: " ").first ?? "")
                                            .font(.caption2)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }

                Section {
                    ForEach(availableContacts) { contact in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                toggleSelection(contact)
                            }
                        } label: {
                            contactRow(contact)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .animation(.easeInOut(duration: 0.3), value: !selected.isEmpty)
            .animation(.easeInOut(duration: 0.2), value: selected.count)
            .searchable(text: $searchText, prompt: t(ChatTranslationKeys.GROUP_INFO_SEARCH_CONTACTS))
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_ADD_PARTICIPANTS_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) { dismiss() }
                        .disabled(isAdding)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(t(ChatTranslationKeys.GROUP_INFO_ADD_ACTION)) {
                        Task {
                            isAdding = true
                            defer { isAdding = false }
                            let didAdd = await onAdd(selected)
                            if didAdd {
                                dismiss()
                            }
                        }
                    }
                    .bold()
                    .disabled(selected.isEmpty || isAdding)
                }
            }
            .overlay {
                if isAdding {
                    ZStack {
                        Color.black.opacity(0.2)
                            .ignoresSafeArea()
                        VStack(spacing: 12) {
                            ProgressView()
                            Text(t(ChatTranslationKeys.GROUP_INFO_ADDING_PARTICIPANTS))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
            .interactiveDismissDisabled(isAdding)
            .safeAreaInset(edge: .bottom) {
                if let groupLocalId,
                   let permissionsUseCases {
                    SendMessagesHistoryPermissionBar(
                        groupLocalId: groupLocalId,
                        groupServerId: groupServerId,
                        isAdmin: isAdmin,
                        permissionsUseCases: permissionsUseCases,
                        translationService: translationService
                    )
                }
            }
        }
    }
    
    // MARK: - Contact Row with Enhanced UI
    
    private func contactRow(_ contact: UserContactProps) -> some View {
        HStack(spacing: 12) {
            // Avatar
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 45, height: 45)
                .overlay {
                    if let avatar = contact.avatar, !avatar.isEmpty {
                        CircularProfileImageView(avatar, size: .xSmall)
                    } else {
                        Text(String(contact.name.prefix(1)).uppercased())
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
            
            // Name and Bio
            VStack(alignment: .leading, spacing: 3) {
                Text(contact.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                // ✅ Enhanced bio display with fallback
                Text(bioText(for: contact))
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            // ✅ Animated checkbox with primary color
            let isSelected = selected.contains(where: { $0.id == contact.id })
            ZStack {
                // Background circle
                Circle()
                    .stroke(isSelected ? AppColors.primary : Color(.systemGray4), lineWidth: 2)
                    .frame(width: 24, height: 24)
                
                // Checkmark with scale animation
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(AppColors.primary)
                        .clipShape(Circle())
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: isSelected)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
    
    /// Returns the appropriate bio text (description or phone number)
    private func bioText(for contact: UserContactProps) -> String {
        if !contact.description.isEmpty && contact.description != "No status" {
            return contact.description
        } else if !contact.phone.isEmpty {
            return contact.phone
        } else {
            return t(ChatTranslationKeys.GROUP_INFO_DEFAULT_STATUS)
        }
    }

    private func toggleSelection(_ contact: UserContactProps) {
        if let idx = selected.firstIndex(where: { $0.id == contact.id }) {
            selected.remove(at: idx)
        } else {
            selected.append(contact)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

@MainActor
final class AddParticipantContactsVM: ObservableObject {
    @Published var waanguUsers: [UserContactProps] = []

    init(contactUseCases: ContactsUseCasesProtocol) {
        Task { await loadContacts(contactUseCases) }
    }

    private func loadContacts(_ useCases: ContactsUseCasesProtocol) async {
        do {
            if let result = try await useCases.getPersistedContacts.execute() {
                waanguUsers = result.UserContactProps
            }
        } catch {
            debugLog("Failed to load contacts for add participant: \(error)")
        }
    }
}

// MARK: - ViewModel

@MainActor
final class GroupInfoViewModel: ObservableObject {

    @Published var group: GroupChat
    @Published var isLoading = false
    @Published var loadingMessage: String?
    @Published var errorMessage: String?
    @Published var isMuted: Bool = false
    @Published var disappearingDuration: DisappearingDuration = .off
    @Published var deletionDialog: DeletionDialogContext?
    @Published var deletionErrorMessage: String?
    @Published private(set) var pendingJoinRequestCount = 0
    
    let discussionId: String
    private let chatRoomVM: ChatRoomViewModel
    private let discussionUseCases: DiscussionUseCasesProtocol
    private let groupUseCases: GroupUseCasesProtocol
    let groupPermissionsUseCases: GroupPermissionsUseCasesProtocol
    private let fileUploadUseCases: FileUplaodUseCasesProtocol?

    @Published private(set) var isJoinApprovalRequired = false

    var isAdmin: Bool {
        group.isCurrentUserAdmin(currentUserId: CurrentSessionInfo.shared.currentUid)
    }
    
    var isCurrentUserActiveMember: Bool {
        group.members.first(where: { $0.userId == CurrentSessionInfo.shared.currentUid })?.isActive ?? false
    }
    
    var hasLeftGroup: Bool {
        let currentUid = CurrentSessionInfo.shared.currentUid
        guard let member = group.members.first(where: { $0.userId == currentUid }) else {
            return false
        }
        return !member.isActive
    }
    
    var activeMemberCount: Int {
        group.members.filter(\.isActive).count
    }

    var canAddMembers: Bool {
        if isAdmin { return true }
        return !group.settings.onlyAdminsCanAddMembers
    }
    
    var canEditGroupInfo: Bool {
        if isAdmin { return true }
        return !group.settings.onlyAdminsCanEditInfo
    }
    
    var canSendMessages: Bool {
        if isAdmin { return true }
        return !group.settings.onlyAdminsCanSend
    }

    var mediaCount: Int {
        chatRoomVM.messages.filter {
            ($0.typeMessage == .IMAGE || $0.typeMessage.isVideo) && !$0.isViewOnce
        }.count
    }
    
    // MARK: - Sorted Members
    // Creator first, then other admins, then regular members
    var sortedMembers: [GroupMember] {
        let activeMembers = group.members.filter(\.isActive)
        let creator = activeMembers.filter { $0.userId == group.createdBy }
        let otherAdmins = activeMembers.filter { $0.role == .ADMIN && $0.userId != group.createdBy }
        let regularMembers = activeMembers.filter { $0.role == .MEMBER }
        
        return creator + otherAdmins + regularMembers
    }

    init(
        discussionId: String,
        groupName: String,
        chatRoomVM: ChatRoomViewModel,
        discussionUseCases: DiscussionUseCasesProtocol,
        groupUseCases: GroupUseCasesProtocol,
        groupPermissionsUseCases: GroupPermissionsUseCasesProtocol,
        fileUploadUseCases: FileUplaodUseCasesProtocol? = nil
    ) {
        self.discussionId = discussionId
        self.chatRoomVM = chatRoomVM
        self.discussionUseCases = discussionUseCases
        self.groupUseCases = groupUseCases
        self.groupPermissionsUseCases = groupPermissionsUseCases
        self.fileUploadUseCases = fileUploadUseCases

        // Nobody, until the stored group says otherwise. Seeding this with the
        // current user made `isCurrentUserAdmin` true on the way in — every member
        // opened the screen as the group's creator, with the admin controls to match.
        self.group = GroupChat(localId: discussionId, name: groupName, createdBy: "")
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                if let saved = try await groupUseCases.getGroup.execute(groupId: discussionId) {
                    self.group = saved
                }
                await self.refreshJoinApprovalRequired()
            } catch {
                debugLog("Failed to load group: \(error)")
            }
        }
    }
    
    private func refreshJoinApprovalRequired() async {
        isJoinApprovalRequired = await GroupJoinApprovalResolver.isApprovalRequired(
            groupLocalId: discussionId,
            legacySettings: group.settings,
            permissionsUseCases: groupPermissionsUseCases
        )
    }
    
    func refreshPendingJoinRequests() async {
        guard isAdmin, isJoinApprovalRequired else {
            pendingJoinRequestCount = 0
            return
        }
        pendingJoinRequestCount = await chatRoomVM.refreshJoinRequestsIfNeeded()
    }

    // MARK: - Translation

    private func t(_ key: String, args: [String] = []) -> String {
        chatRoomVM.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }

    // MARK: - Mute and Disappearing Messages
    
    func reloadMuteFromStore() {
        Task { @MainActor in
            do {
                guard let list = try await discussionUseCases.getDiscussions.execute(),
                      let discussion = list.first(where: { $0.conversationId == discussionId }) else {
                    return
                }
                isMuted = discussion.setting?.isMuted ?? false
            } catch {
                debugLog("Failed to load mute setting: \(error)")
            }
        }
    }

    func setMuted(_ muted: Bool) async throws {
        guard let list = try await discussionUseCases.getDiscussions.execute(),
              var discussion = list.first(where: { $0.conversationId == discussionId }) else {
            throw NSError(domain: "GroupInfo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Discussion not found"])
        }

        if discussion.setting == nil {
            discussion.setting = UserConversationSetting()
        }
        discussion.setting?.isMuted = muted

        try await discussionUseCases.updateDiscussionSetting.execute(discussion: discussion)
        isMuted = muted
    }

    func reloadDisappearingFromStore() {
        Task { @MainActor in
            do {
                guard let list = try await discussionUseCases.getDiscussions.execute(),
                      let discussion = list.first(where: { $0.conversationId == discussionId }) else {
                    return
                }
                if let duration = discussion.setting?.ephemeralMessageDuration {
                    disappearingDuration = DisappearingDuration(rawValue: duration) ?? .off
                }
            } catch {
                debugLog("Failed to load disappearing setting: \(error)")
            }
        }
    }

    func setDisappearingMessages(_ duration: DisappearingDuration) async throws {
        guard let list = try await discussionUseCases.getDiscussions.execute(),
              var discussion = list.first(where: { $0.conversationId == discussionId }) else {
            throw NSError(domain: "GroupInfo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Discussion not found"])
        }

        if discussion.setting == nil {
            discussion.setting = UserConversationSetting()
        }
        discussion.setting?.ephemeralMessageDuration = duration.rawValue

        try await discussionUseCases.updateDiscussionSetting.execute(discussion: discussion)
        disappearingDuration = duration
    }

    // MARK: - Member management with backend sync

    func reloadGroupFromStore() {
        Task { @MainActor in
            guard let updated = try? await groupUseCases.getGroup.execute(groupId: group.localId) else {
                return
            }
            group = updated
            await refreshJoinApprovalRequired()
        }
    }

    func promoteToAdmin(_ member: GroupMember) {
        guard group.members.contains(where: { $0.userId == member.userId }) else { return }
        var updatedMember = member
        updatedMember.role = .ADMIN
        debugLog("member to br promoted:  \(member)")
        Task {
            isLoading = true
            loadingMessage = t(ChatTranslationKeys.GROUP_INFO_UPDATING_ROLE)
            defer {
                isLoading = false
                loadingMessage = nil
            }
            
            do {
                try await groupUseCases.updateMemberRole.execute(
                    member: updatedMember,
                    in: group.id,
                    ownerId: group.createdBy
                )
                reloadGroupFromStore()
            } catch {
                errorMessage = t(ChatTranslationKeys.GROUP_INFO_PROMOTE_FAILED, args: [error.localizedDescription])
            }
        }
    }

    func demoteFromAdmin(_ member: GroupMember) {
        guard group.members.contains(where: { $0.id == member.id }) else { return }
        var updatedMember = member
        updatedMember.role = .MEMBER
        
        Task {
            isLoading = true
            loadingMessage = t(ChatTranslationKeys.GROUP_INFO_UPDATING_ROLE)
            defer {
                isLoading = false
                loadingMessage = nil
            }
            
            do {
                try await groupUseCases.updateMemberRole.execute(
                    member: updatedMember,
                    in: group.id,
                    ownerId: group.createdBy
                )
                reloadGroupFromStore()
            } catch {
                errorMessage = t(ChatTranslationKeys.GROUP_INFO_DEMOTE_FAILED, args: [error.localizedDescription])
            }
        }
    }

    func removeMember(_ member: GroupMember) {
        Task {
            isLoading = true
            loadingMessage = t(ChatTranslationKeys.GROUP_INFO_REMOVING_MEMBER)
            defer {
                isLoading = false
                loadingMessage = nil
            }
            
            do {
                try await groupUseCases.removeMember.execute(
                    userId: member.userId,
                    from: group.id,
                    ownerId: group.createdBy
                )
                reloadGroupFromStore()
            } catch {
                errorMessage = t(ChatTranslationKeys.GROUP_INFO_REMOVE_MEMBER_FAILED, args: [error.localizedDescription])
            }
        }
    }

    @discardableResult
    func addMembers(_ contacts: [UserContactProps]) async -> Bool {
        
        let newMembers = contacts.compactMap { contact -> GroupMember? in
            let alreadyExists = group.members.contains { $0.userId == contact.userId }
            guard !alreadyExists else { return nil }
            return GroupMember(
                userId: contact.userId,
                name: contact.name,
                phone: contact.phone,
                avatar: contact.avatar,
                role: .MEMBER
            )
        }
        
        guard !newMembers.isEmpty else { return false }
        
        isLoading = true
        loadingMessage = newMembers.count == 1
            ? t(ChatTranslationKeys.GROUP_INFO_ADDING_PARTICIPANT)
            : t(ChatTranslationKeys.GROUP_INFO_ADDING_PARTICIPANTS)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            for member in newMembers {
                try await groupUseCases.addMember.execute(
                    member: member,
                    to: group.id,
                    ownerId: group.createdBy
                )
            }
            reloadGroupFromStore()
            return true
        } catch {
            errorMessage = t(ChatTranslationKeys.GROUP_INFO_ADD_MEMBERS_FAILED, args: [error.localizedDescription])
            return false
        }
    }

    // MARK: - Settings with backend sync

    func updateSetting<V>(_ keyPath: WritableKeyPath<GroupSettings, V>, value: V) {
        group.settings[keyPath: keyPath] = value
        
        Task {
            do {
                try await groupUseCases.updateGroupInfo.execute(group)
            } catch {
                errorMessage = t(ChatTranslationKeys.GROUP_INFO_SETTINGS_FAILED, args: [error.localizedDescription])
            }
        }
    }
    
    func loadLocalBoolSetting(key: String, defaultValue: Bool = false) -> Bool {
        let fullKey = "group.\(discussionId).\(key)"
        if UserDefaults.standard.object(forKey: fullKey) == nil {
            return defaultValue
        }
        return UserDefaults.standard.bool(forKey: fullKey)
    }
    
    func persistLocalBoolSetting(key: String, value: Bool) {
        UserDefaults.standard.set(value, forKey: "group.\(discussionId).\(key)")
    }
    
    /// Saves the edited group header. Nothing is written to `group` until the
    /// avatar upload and the persist both succeed, so a failed save leaves the
    /// screen showing what the group actually still is.
    func updateGroupInfo(name: String, description: String?, avatarEdit: GroupAvatarEdit) {
        Task {
            isLoading = true
            loadingMessage = t(ChatTranslationKeys.GROUP_INFO_SAVING)
            defer {
                isLoading = false
                loadingMessage = nil
            }

            var edited = group
            edited.name = name
            edited.description = description

            switch avatarEdit {
            case .unchanged:
                break
            case .removed:
                // Empty rather than nil: the update request encodes optionals with
                // `encodeIfPresent`, so nil would omit the field and the server
                // would keep the old photo.
                edited.avatarUrl = ""
            case .replaced(let image):
                guard let fileUploadUseCases else {
                    errorMessage = t(ChatTranslationKeys.GROUP_INFO_AVATAR_UPLOAD_FAILED)
                    return
                }
                guard let url = await uploadAvatar(image, using: fileUploadUseCases) else {
                    return
                }
                edited.avatarUrl = url
            }

            do {
                try await groupUseCases.updateGroupInfo.execute(edited)
                group = edited
            } catch {
                errorMessage = t(
                    ChatTranslationKeys.GROUP_INFO_UPDATE_FAILED,
                    args: [error.localizedDescription]
                )
            }
        }
    }

    /// Uploads a picked group photo, downscaled and JPEG-encoded so a full
    /// resolution camera shot doesn't go up as a multi-megabyte PNG.
    private func uploadAvatar(
        _ image: UIImage,
        using fileUploadUseCases: FileUplaodUseCasesProtocol
    ) async -> String? {
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
            return url
        case .failure(let error):
            errorMessage = t(
                ChatTranslationKeys.GROUP_INFO_AVATAR_UPLOAD_FAILED_REASON,
                args: [error.localizedDescription]
            )
            return nil
        }
    }

    // MARK: - Deletion validation
    
    func beginDeletion(intent: DeletionDialogIntent) {
        Task { @MainActor in
            do {
                let eligibility = try await groupUseCases.getDiscussionDeletionEligibility.execute(
                    discussionId: discussionId,
                    currentUserId: CurrentSessionInfo.shared.currentUid
                )
                deletionDialog = DeletionDialogContext(
                    discussionId: discussionId,
                    eligibility: eligibility,
                    intent: intent
                )
            } catch {
                deletionErrorMessage = t(ChatTranslationKeys.GROUP_INFO_ELIGIBILITY_FAILED, args: [error.localizedDescription])
            }
        }
    }
    
    @discardableResult
    func confirmDeletionPrimaryAction() async -> Bool {
        guard let context = deletionDialog else { return false }
        
        isLoading = true
        loadingMessage = context.intent == .exitGroup
            ? t(ChatTranslationKeys.GROUP_INFO_LEAVING_GROUP)
            : t(ChatTranslationKeys.GROUP_INFO_DELETING)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            switch context.intent {
            case .exitGroup:
                return false
            case .deleteFromList, .deleteFromGroupInfo:
                try await performValidatedDelete(eligibility: context.eligibility)
                deletionDialog = nil
                return true
            }
        } catch {
            deletionErrorMessage = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func confirmDeleteLocalContent() async -> Bool {
        isLoading = true
        loadingMessage = isCurrentUserActiveMember
            ? t(ChatTranslationKeys.GROUP_INFO_CLEARING_MESSAGES)
            : t(ChatTranslationKeys.GROUP_INFO_DELETING)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            if isCurrentUserActiveMember {
                try await chatRoomVM.clearAllMessagesLocally()
                deletionDialog = nil
                return false
            } else {
                try await groupUseCases.deleteLocalGroupCopy.execute(groupId: discussionId)
                deletionDialog = nil
                return true
            }
        } catch {
            deletionErrorMessage = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func confirmLeaveGroupFromDialog() async -> Bool {
        isLoading = true
        loadingMessage = t(ChatTranslationKeys.GROUP_INFO_LEAVING_GROUP)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            try await performServerLeave()
            deletionDialog = nil
            return false
        } catch {
            deletionErrorMessage = error.localizedDescription
            return false
        }
    }
    
    func confirmExitAndKeepLocally() async {
        isLoading = true
        loadingMessage = t(ChatTranslationKeys.GROUP_INFO_LEAVING_GROUP)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            try await performServerLeave()
            deletionDialog = nil
        } catch {
            deletionErrorMessage = error.localizedDescription
        }
    }
    
    @discardableResult
    func confirmExitAndDeleteLocally() async -> Bool {
        isLoading = true
        loadingMessage = t(ChatTranslationKeys.GROUP_INFO_LEAVING_GROUP)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            try await performServerLeave()
            try await groupUseCases.deleteLocalGroupCopy.execute(groupId: discussionId)
            deletionDialog = nil
            return true
        } catch {
            deletionErrorMessage = error.localizedDescription
            return false
        }
    }
    
    @discardableResult
    func deleteLocalGroupCopy() async -> Bool {
        isLoading = true
        loadingMessage = t(ChatTranslationKeys.GROUP_INFO_DELETING)
        defer {
            isLoading = false
            loadingMessage = nil
        }
        
        do {
            try await groupUseCases.deleteLocalGroupCopy.execute(groupId: discussionId)
            return true
        } catch {
            deletionErrorMessage = error.localizedDescription
            return false
        }
    }
    
    private func performValidatedDelete(eligibility: DeletionEligibility) async throws {
        switch eligibility.suggestedAction {
        case .deleteNow, .deleteLocalContent:
            let result = try await groupUseCases.validateAndDeleteDiscussion.execute(
                discussionId: discussionId,
                currentUserId: CurrentSessionInfo.shared.currentUid
            )
            switch result {
            case .success:
                return
            case .blocked(let reason):
                throw NSError(domain: "Deletion", code: 1, userInfo: [NSLocalizedDescriptionKey: reason])
            case .requiresLeaveAndDelete:
                try await performServerLeave()
                return
            case .requiresLeave:
                throw NSError(
                    domain: "Deletion",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: eligibility.userMessage]
                )
            case .error(let message):
                throw NSError(domain: "Deletion", code: 3, userInfo: [NSLocalizedDescriptionKey: message])
            }
        case .leaveAndDelete:
            try await performServerLeave()
            return
        case .leaveGroupFirst, .cannotDelete:
            throw NSError(
                domain: "Deletion",
                code: 4,
                userInfo: [NSLocalizedDescriptionKey: eligibility.userMessage]
            )
        }
    }
    
    private func performServerLeave() async throws {
        _ = try await groupUseCases.leaveGroup.execute(
            groupId: discussionId,
            userId: CurrentSessionInfo.shared.currentUid
        )
        reloadGroupFromStore()
        chatRoomVM.refreshGroupMembershipStatus()
    }
}


// MARK: - Edit Group Info Sheet

/// What the edit sheet decided to do with the group photo. `unchanged` is the
/// default so a save that only renames the group never re-uploads — or wipes —
/// the avatar the group already has.
enum GroupAvatarEdit: Equatable {
    case unchanged
    case replaced(UIImage)
    case removed
}

@available(iOS 17.0, *)
struct EditGroupInfoSheet: View {
    @Environment(\.dismiss) private var dismiss
    let translationService: (any TranslationServiceProtocol)?

    /// Avatar the group is currently wearing, so the sheet opens showing the
    /// real photo instead of an empty camera placeholder.
    private let currentAvatarUrl: String?

    @State private var groupName: String
    @State private var groupDescription: String
    @State private var pickedAvatar: UIImage?
    @State private var didRemoveAvatar = false

    let onSave: (String, String?, GroupAvatarEdit) -> Void

    init(
        groupName: String,
        groupDescription: String,
        currentAvatarUrl: String?,
        translationService: (any TranslationServiceProtocol)?,
        onSave: @escaping (String, String?, GroupAvatarEdit) -> Void
    ) {
        _groupName = State(initialValue: groupName)
        _groupDescription = State(initialValue: groupDescription)
        self.currentAvatarUrl = currentAvatarUrl
        self.translationService = translationService
        self.onSave = onSave
    }

    private var hasAvatar: Bool {
        if pickedAvatar != nil { return true }
        if didRemoveAvatar { return false }
        return !(currentAvatarUrl ?? "").isEmpty
    }

    private var avatarEdit: GroupAvatarEdit {
        if let pickedAvatar { return .replaced(pickedAvatar) }
        if didRemoveAvatar { return .removed }
        return .unchanged
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 16) {
                        AvatarPickerButton(onPicked: { pickedAvatar = $0 }) {
                            avatarThumbnail
                        }
                        .buttonStyle(.plain)

                        VStack(spacing: 8) {
                            TextField(t(ChatTranslationKeys.GROUP_INFO_GROUP_NAME), text: $groupName)
                                .textFieldStyle(.roundedBorder)
                            TextField(t(ChatTranslationKeys.GROUP_INFO_GROUP_DESCRIPTION), text: $groupDescription)
                                .textFieldStyle(.roundedBorder)
                                .font(.subheadline)
                        }
                    }
                    .padding(.vertical, 8)

                    if hasAvatar {
                        Button(role: .destructive) {
                            pickedAvatar = nil
                            didRemoveAvatar = true
                        } label: {
                            Label(
                                t(ChatTranslationKeys.GROUP_INFO_REMOVE_PHOTO),
                                systemImage: "trash"
                            )
                        }
                    }
                }
            }
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_EDIT_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(common("save")) {
                        let trimmedName = groupName.trimmingCharacters(in: .whitespaces)
                        let trimmedDesc = groupDescription.trimmingCharacters(in: .whitespaces)
                        onSave(
                            trimmedName,
                            trimmedDesc.isEmpty ? nil : trimmedDesc,
                            avatarEdit
                        )
                        dismiss()
                    }
                    .bold()
                    .disabled(groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onChange(of: pickedAvatar) { _, newValue in
                // Picking a photo overrides a pending removal.
                if newValue != nil { didRemoveAvatar = false }
            }
        }
    }

    @ViewBuilder
    private var avatarThumbnail: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray5))
                .frame(width: 64, height: 64)

            if let pickedAvatar {
                Image(uiImage: pickedAvatar)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(Circle())
            } else if let currentAvatarUrl, !currentAvatarUrl.isEmpty, !didRemoveAvatar {
                CircularProfileImageView(currentAvatarUrl, size: .custom(64))
            } else {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "pencil.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, AppColors.primary)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

@available(iOS 17.0, *)
struct GroupInviteLinkSheet: View {
    @Environment(\.dismiss) private var dismiss

    let inviteLink: String
    let hasInviteLink: Bool
    @Binding var isLoading: Bool
    let loadingMessage: String?
    let translationService: (any TranslationServiceProtocol)?
    let onRegenerate: () -> Void

    @State private var showShare = false

    var body: some View {
        NavigationStack {
            List {
                if isLoading {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()

                            Text(loadingMessage ?? t(ChatTranslationKeys.GROUP_INFO_INVITE_LINK_LOADING))
                                .foregroundStyle(.secondary)
                        }
                       
                    }
                } else if hasInviteLink {
                    Section(t(ChatTranslationKeys.GROUP_INFO_INVITE_LINK_SECTION)) {
                        Text(inviteLink)
                            .font(.footnote)
                            .textSelection(.enabled)

                        Button {
                            UIPasteboard.general.string = inviteLink
                        } label: {
                            Label(t(ChatTranslationKeys.GROUP_INFO_COPY_LINK), systemImage: "doc.on.doc")
                        }

                        Button {
                            showShare = true
                        } label: {
                            Label(t(ChatTranslationKeys.GROUP_INFO_SHARE_LINK), systemImage: "square.and.arrow.up")
                        }

                        Button {
                            debugLog("🔗 📱 Reset link button tapped in sheet")
                            onRegenerate()
                        } label: {
                            Label(t(ChatTranslationKeys.GROUP_INFO_RESET_LINK), systemImage: "arrow.clockwise")
                        }
                    }
                    

                    Section(t(ChatTranslationKeys.GROUP_INFO_QR_SECTION)) {
                        if let image = qrCode(from: inviteLink) {
                            Image(uiImage: image)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity, maxHeight: 240)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                } else {
                    Section {
                        ContentUnavailableView(
                            t(ChatTranslationKeys.GROUP_INFO_NO_INVITE_LINK),
                            systemImage: "link.badge.plus",
                            description: Text(t(ChatTranslationKeys.GROUP_INFO_GENERATE_INVITE_DESC))
                        )

                        Button {
                            debugLog("🔗 📱 Generate link button tapped in sheet")
                            onRegenerate()
                        } label: {
                            Label(t(ChatTranslationKeys.GROUP_INFO_GENERATE_INVITE), systemImage: "plus")
                        }
                    }
                
                }
            }
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_INVITE_VIA_LINK_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("done")) {
                        dismiss()
                    }
                }
            }
            .chatAppearanceSheet(isPresented: $showShare) {
                ActivityShareSheet(activityItems: [inviteLink])
            }
        }
    }

    private func qrCode(from text: String) -> UIImage? {
        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()

        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let outputImage = filter.outputImage?
            .transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cgImage = context.createCGImage(
                outputImage,
                from: outputImage.extent
              ) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
@available(iOS 17.0, *)
private struct GroupAdminsSheet: View {
    let admins: [GroupMember]
    let discussionId: String
    let translationService: (any TranslationServiceProtocol)?
    
    var body: some View {
        NavigationStack {
            List(admins) { admin in
                HStack(spacing: 12) {
                    if let avatar = admin.avatar, !avatar.isEmpty {
                        CircularProfileImageView(avatar, size: .xSmall)
                    } else {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 40, height: 40)
                            .overlay {
                                Text(String(admin.name.prefix(1)).uppercased())
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(admin.userId == CurrentSessionInfo.shared.currentUid ? common("you") : admin.name)
                            .font(.subheadline.weight(.medium))
                        Text(admin.phone)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(t(ChatTranslationKeys.GROUP_INFO_ADMIN))
                        .font(.caption2)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_GROUP_ADMINS_TITLE))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

@available(iOS 17.0, *)
private struct GroupMembersSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let members: [GroupMember]
    let translationService: (any TranslationServiceProtocol)?
    let onSelectMember: (GroupMember) -> Void
    @State private var searchText = ""
    
    private var filteredMembers: [GroupMember] {
        if searchText.isEmpty { return members }
        return members.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.phone.localizedCaseInsensitiveContains(searchText)
        }
    }
    
    var body: some View {
        NavigationStack {
            List(filteredMembers) { member in
                Button {
                    onSelectMember(member)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Circle()
                            .fill(Color(.systemGray4))
                            .frame(width: 36, height: 36)
                            .overlay {
                                Text(String(member.name.prefix(1)).uppercased())
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.white)
                            }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.userId == CurrentSessionInfo.shared.currentUid ? common("you") : member.name)
                                .foregroundStyle(.primary)
                            Text(member.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $searchText, prompt: t(ChatTranslationKeys.GROUP_INFO_SEARCH_MEMBERS))
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_SEARCH_MEMBERS_TITLE))
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

@available(iOS 17.0, *)
private struct GroupMemberActionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    
    let member: GroupMember
    let isCurrentUserAdmin: Bool
    let currentUserId: String
    let translationService: (any TranslationServiceProtocol)?
    let onMessage: () -> Void
    let onAudio: () -> Void
    let onVideo: () -> Void
    let onInfo: () -> Void
    let onMakeAdmin: () -> Void
    let onDismissAdmin: () -> Void
    let onRemoveMember: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: 12) {
                        if let avatar = member.avatar, !avatar.isEmpty {
                            CircularProfileImageView(avatar, size: .xSmall)
                        } else {
                            Circle()
                                .fill(Color(.systemGray4))
                                .frame(width: 44, height: 44)
                                .overlay {
                                    Text(String(member.name.prefix(1)).uppercased())
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                }
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.userId == currentUserId ? common("you") : member.name)
                                .font(.headline)
                            Text(member.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                
                Section {
                    actionRow(icon: "message", title: t(ChatTranslationKeys.GROUP_INFO_MESSAGE), isDestructive: false, action: onMessage)
                    actionRow(icon: "phone", title: t(ChatTranslationKeys.CONTACT_INFO_AUDIO), isDestructive: false, action: onAudio)
                    actionRow(icon: "video", title: t(ChatTranslationKeys.CONTACT_INFO_VIDEO), isDestructive: false, action: onVideo)
                    actionRow(icon: "info.circle", title: t(ChatTranslationKeys.CONTACT_INFO_TITLE), isDestructive: false, action: onInfo)
                }
                
                if isCurrentUserAdmin && member.userId != currentUserId {
                    Section {
                        if member.role == .MEMBER {
                            actionRow(icon: "person.badge.shield.checkmark", title: t(ChatTranslationKeys.GROUP_INFO_MAKE_ADMIN), isDestructive: false, action: onMakeAdmin)
                        } else {
                            actionRow(icon: "shield.slash", title: t(ChatTranslationKeys.GROUP_INFO_DISMISS_ADMIN), isDestructive: false, action: onDismissAdmin)
                        }
                        actionRow(icon: "person.fill.xmark", title: t(ChatTranslationKeys.GROUP_INFO_REMOVE_FROM_GROUP), isDestructive: true, action: onRemoveMember)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t(ChatTranslationKeys.GROUP_INFO_MEMBER_ACTIONS_TITLE))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(t(ChatTranslationKeys.GROUP_INFO_CLOSE)) { dismiss() }
                }
            }
        }
    }
    
    @ViewBuilder
    private func actionRow(icon: String, title: String, isDestructive: Bool, action: @escaping () -> Void) -> some View {
        Button {
            action()
            dismiss()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Text(title)
                    .foregroundStyle(isDestructive ? .red : .primary)
                Spacer()
            }
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
