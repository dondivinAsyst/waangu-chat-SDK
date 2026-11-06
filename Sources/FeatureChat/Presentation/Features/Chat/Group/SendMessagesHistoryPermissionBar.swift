//
//  SendMessagesHistoryPermissionBar.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Reactive share-history toggle used in add-participant flows.
struct SendMessagesHistoryPermissionBar: View {
    let groupLocalId: String
    let groupServerId: String?
    let isAdmin: Bool
    let permissionsUseCases: GroupPermissionsUseCasesProtocol
    let translationService: (any TranslationServiceProtocol)?

    @State private var permissions = GroupPermissions()
    @State private var isLoading = true
    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text(t(ChatTranslationKeys.PERMISSIONS_LOADING))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            } else if isAdmin {
                BrandedToggle(isOn: Binding(
                    get: { permissions.sendMessagesHistory },
                    set: { toggleSendMessagesHistory($0) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY))
                            .font(.subheadline)
                        Text(t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY_DESC))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(isUpdating || groupServerId == nil)
            } else {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t(ChatTranslationKeys.PERMISSIONS_SHARE_HISTORY))
                            .font(.subheadline)
                        Text(permissions.sendMessagesHistory ? t(ChatTranslationKeys.PERMISSIONS_ENABLED) : t(ChatTranslationKeys.PERMISSIONS_DISABLED))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .overlay(alignment: .top) {
            Divider()
        }
        .task {
            await loadPermissions()
        }
        .alert(common("error"), isPresented: .constant(errorMessage != nil)) {
            Button(common("ok")) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func loadPermissions() async {
        isLoading = true
        defer { isLoading = false }
        if let stored = try? await permissionsUseCases.getPermissions.execute(groupLocalId: groupLocalId) {
            permissions = stored
        }
    }

    private func toggleSendMessagesHistory(_ value: Bool) {
        guard let groupServerId else {
            errorMessage = t(ChatTranslationKeys.PERMISSIONS_GROUP_NOT_SYNCED)
            return
        }

        var updated = permissions
        updated.sendMessagesHistory = value

        Task {
            isUpdating = true
            defer { isUpdating = false }
            do {
                try await permissionsUseCases.updatePermissions.execute(
                    permissions: updated,
                    groupLocalId: groupLocalId,
                    groupServerId: groupServerId
                )
                permissions = updated
            } catch {
                errorMessage = t(ChatTranslationKeys.PERMISSIONS_UPDATE_FAILED, args: [error.localizedDescription])
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
