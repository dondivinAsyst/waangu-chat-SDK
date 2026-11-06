//
//  CommunitySettingsView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// A community's permissions: who adds members, who adds groups.
///
/// Identity has no `/communities/settings` yet, so these are served from the
/// debug mock store. The screen, the use case and the endpoint are the real
/// ones — only the datasource short-circuits, and only in DEBUG.
@available(iOS 16.0, *)
struct CommunitySettingsView: View {

    @StateObject private var viewModel: CommunitySettingsViewModel

    init(viewModel: CommunitySettingsViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            Section {
                permissionRow(
                    title: t(ChatTranslationKeys.COMMUNITIES_WHO_ADDS_MEMBERS),
                    selection: Binding(
                        get: { viewModel.settings.whoCanAddMembers },
                        set: { viewModel.setWhoCanAddMembers($0) }
                    )
                )

                permissionRow(
                    title: t(ChatTranslationKeys.COMMUNITIES_WHO_ADDS_GROUPS),
                    selection: Binding(
                        get: { viewModel.settings.whoCanAddGroups },
                        set: { viewModel.setWhoCanAddGroups($0) }
                    )
                )
            } header: {
                Text(t(ChatTranslationKeys.COMMUNITIES_SETTINGS))
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_SETTINGS))
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load() }
        .customAlert(
            title: common("error"),
            message: viewModel.errorMessage,
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.dismissError() } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { viewModel.dismissError() }
        )
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        selection: Binding<CommunityPermission>
    ) -> some View {
        Picker(title, selection: selection) {
            Text(t(ChatTranslationKeys.COMMUNITIES_EVERYONE)).tag(CommunityPermission.everyone)
            Text(t(ChatTranslationKeys.COMMUNITIES_ADMINS_ONLY)).tag(CommunityPermission.adminsOnly)
        }
        .pickerStyle(.navigationLink)
        .tint(AppColors.primary)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
