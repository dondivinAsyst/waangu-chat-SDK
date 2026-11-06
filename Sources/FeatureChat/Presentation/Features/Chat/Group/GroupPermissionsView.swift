import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 17.0, *)
struct GroupPermissionsView: View {
    @StateObject private var viewModel: GroupPermissionsViewModel
    let navigationCoord: ChatsTabCoordinator
    let translationService: (any TranslationServiceProtocol)?

    init(
        group: GroupChat,
        permissionsUseCases: GroupPermissionsUseCasesProtocol,
        navigationCoord: ChatsTabCoordinator,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: GroupPermissionsViewModel(
                group: group,
                permissionsUseCases: permissionsUseCases
            )
        )
        self.navigationCoord = navigationCoord
        self.translationService = translationService
    }

    var body: some View {
        VStack(spacing: 0) {
            permissionsHeader

            List {
                if viewModel.isAdmin {
                    adminSection
                } else {
                    readOnlySection
                }
            }
            .listStyle(.insetGrouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .disabled(viewModel.isUpdating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .overlay {
            if viewModel.isUpdating {
                Color.black.opacity(0.15)
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .controlSize(.large)
                            .padding(20)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                    }
            }
        }
        .alert(common("error"), isPresented: .constant(viewModel.errorMessage != nil)) {
            Button(common("ok")) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    // MARK: - Navigation Header

    private var permissionsHeader: some View {
        HStack {
            Button { navigationCoord.pop() } label: {
                Image(systemName: "chevron.backward")
                    .foregroundColor(AppColors.primary)
            }
            Spacer()
            Text(t(ChatTranslationKeys.GROUP_PERMS_SECTION_TITLE))
                .font(.headline)
                .fontWeight(.semibold)
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

    // MARK: - Admin Section

    private var adminSection: some View {
        Section {
            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_SEND_MESSAGES),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_SEND_MESSAGES_DESC),
                keyPath: \.sendMessages
            )

            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_ADD_MEMBERS),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_ADD_MEMBERS_DESC),
                keyPath: \.addMembers
            )

            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_INVITE_LINK),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_INVITE_LINK_DESC),
                keyPath: \.inviteLink
            )

            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_EDIT_GROUP_INFO),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_EDIT_GROUP_INFO_DESC),
                keyPath: \.changeGroupInfo
            )

            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_APPROVE_NEW_MEMBERS),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_APPROVE_NEW_MEMBERS_DESC),
                keyPath: \.approveNewMembers
            )

            permissionToggle(
                title: t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_POST),
                subtitle: t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_POST_DESC),
                keyPath: \.onlyAdminsCanPost
            )

            permissionToggle(
                title: t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY),
                subtitle: t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY_DESC),
                keyPath: \.sendMessagesHistory
            )
        } header: {
            Text(t(ChatTranslationKeys.GROUP_PERMS_WHO_CAN_MODIFY))
                .textCase(.none)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func permissionToggle(
        title: String,
        subtitle: String,
        keyPath: WritableKeyPath<GroupPermissions, Bool>
    ) -> some View {
        BrandedToggle(isOn: Binding(
            get: { viewModel.permissions[keyPath: keyPath] },
            set: { viewModel.toggle(keyPath, value: $0) }
        )) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Read-Only Section

    private var readOnlySection: some View {
        Section {
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_SEND_MESSAGES),
                value: viewModel.permissions.sendMessages ? t(ChatTranslationKeys.GROUP_PERMS_ALL_PARTICIPANTS) : t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS)
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_ADD_MEMBERS),
                value: viewModel.permissions.addMembers ? t(ChatTranslationKeys.GROUP_PERMS_ALL_PARTICIPANTS) : t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS)
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_INVITE_LINK),
                value: viewModel.permissions.inviteLink ? t(ChatTranslationKeys.GROUP_PERMS_ALL_PARTICIPANTS) : t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS)
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_EDIT_GROUP_INFO),
                value: viewModel.permissions.changeGroupInfo ? t(ChatTranslationKeys.GROUP_PERMS_ALL_PARTICIPANTS) : t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS)
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_APPROVE_NEW_MEMBERS),
                value: viewModel.permissions.approveNewMembers ? "Yes" : "No"
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS_POST),
                value: viewModel.permissions.onlyAdminsCanPost ? "Yes" : "No"
            )
            readOnlyRow(
                title: t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY),
                value: viewModel.permissions.sendMessagesHistory ? "Yes" : "No"
            )
        } header: {
            Text(t(ChatTranslationKeys.GROUP_PERMS_SECTION_TITLE))
                .textCase(.none)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        } footer: {
            Text(t(ChatTranslationKeys.GROUP_PERMS_ONLY_ADMINS))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func readOnlyRow(title: String, value: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.body)
                Text(value)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
