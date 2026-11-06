//
//  NewGroupSetUpScreen.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 13.01.2025.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct NewGroupSetUpScreen: View {
    @State private var channelName = ""
    @State private var selectedImage: UIImage?
    @State private var showGroupPermissions = false
    @State private var groupSettings = GroupSettings()
    @ObservedObject var viewModel: ChatPartnerPickerViewModel
    let translationService: (any TranslationServiceProtocol)?

    var onCreateGroup: (_ groupName: String, _ members: [UserContactProps], _ image: UIImage?, _ settings: GroupSettings) -> Void

    var body: some View {
        List {
            Section {
                channelSetUpHeaderView()
            }

            Section {
                SelectedChatPartnerView(users: viewModel.selectedChatPartners) { user in
                    viewModel.handleItemSelection(user)
                }
            } header: {
                let count = viewModel.selectedChatPartners.count
                let maxCount = ChannelContants.maxGroupChatMembers

                Text(t(ChatTranslationKeys.NEW_GROUP_PARTICIPANTS, args: ["\(count)", "\(maxCount)"]))
                    .bold()
            }
            .listRowBackground(Color.clear)
            
            // Group Permissions Section
            Section {
                Button {
                    showGroupPermissions = true
                } label: {
                    HStack {
                        Image(systemName: "lock.shield")
                            .foregroundColor(AppColors.primary)
                        Text(t(ChatTranslationKeys.NEW_GROUP_PERMISSIONS))
                            .foregroundColor(.primary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .foregroundColor(.gray)
                            .font(.caption)
                    }
                }
            } header: {
                Text(t(ChatTranslationKeys.NEW_GROUP_SETTINGS))
            } footer: {
                Text(t(ChatTranslationKeys.NEW_GROUP_PERMISSIONS_DESC))
                    .font(.caption)
            }
        }
        .navigationTitle(t(ChatTranslationKeys.CREATE_GROUP_TITLE))
        .toolbar {
            trailNavItem()
        }
        .chatAppearanceSheet(isPresented: $showGroupPermissions) {
            GroupPermissionsSheet(settings: $groupSettings, translationService: translationService)
        }
    }

    private func channelSetUpHeaderView() -> some View {
        HStack {
            profileImageView()

            if #available(iOS 16.0, *) {
                TextField("", text: $channelName, prompt: Text(t(ChatTranslationKeys.NEW_GROUP_NAME)),
                          axis: .vertical)
            } else {
                // Fallback on earlier versions
            }
        }
    }

    private func profileImageView() -> some View {
        AvatarPickerButton(onPicked: { selectedImage = $0 }) {
            ZStack {
                if let selectedImage = selectedImage {
                    Image(uiImage: selectedImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 60, height: 60)
                        .clipShape(Circle())
                } else {
                    Image(systemName: "camera.fill")
                        .imageScale(.large)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 60, height: 60)
            .background(Color(.systemGray5))
            .clipShape(Circle())
        }
    }

    @ToolbarContentBuilder
    private func trailNavItem() -> some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Button(t(ChatTranslationKeys.NEW_GROUP_CREATE)) {
                let name = channelName.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { return }
                onCreateGroup(name, viewModel.selectedChatPartners, selectedImage, groupSettings)
            }
            .bold()
            .disabled(channelName.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.disableNextButton)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}

//#Preview {
//    NavigationStack {
//        NewGroupSetUpScreen(viewModel: ChatPartnerPickerViewModel()) {  _ in
//        
//        }
//    }
//}


// MARK: - Group Permissions Sheet

struct GroupPermissionsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var settings: GroupSettings
    let translationService: (any TranslationServiceProtocol)?
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    BrandedToggle(isOn: $settings.onlyAdminsCanSend) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_SEND))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_SEND_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    BrandedToggle(isOn: $settings.onlyAdminsCanEditInfo) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_EDIT))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_EDIT_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    BrandedToggle(isOn: $settings.onlyAdminsCanAddMembers) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_ADD))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_ADD_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    
                    BrandedToggle(isOn: $settings.approvalRequired) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.GROUP_PERMS_APPROVE_NEW))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.GROUP_PERMS_APPROVE_NEW_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    BrandedToggle(isOn: $settings.sendMessagesHistory) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(t(ChatTranslationKeys.GROUP_PERMS_SECTION_TITLE))
                } footer: {
                    Text(t(ChatTranslationKeys.GROUP_PERMS_SECTION_DESC))
                        .font(.caption)
                }
                
                Section {
                    BrandedToggle(isOn: $settings.allowMediaSharing) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(t(ChatTranslationKeys.GROUP_PERMS_MEDIA_SHARING))
                                .font(.subheadline)
                            Text(t(ChatTranslationKeys.GROUP_PERMS_MEDIA_SHARING_DESC))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(t(ChatTranslationKeys.GROUP_PERMS_MEDIA_SETTINGS))
                }
            }
            .navigationTitle(t(ChatTranslationKeys.NEW_GROUP_PERMISSIONS))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(common("done")) {
                        dismiss()
                    }
                    .bold()
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
