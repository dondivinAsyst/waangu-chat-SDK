//
//  CommunityAddGroupSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Adding a group to a community: make a new one, or attach one you own.
///
/// The list is deliberately narrow — active groups this user created, minus the
/// ones already attached. A group that has not synced has no server id, and
/// `groups/link` is keyed on the server id, so an unsynced group is not merely
/// untidy here, it is unlinkable.
@available(iOS 16.0, *)
struct CommunityAddGroupSheet: View {

    @ObservedObject var viewModel: CommunityDetailViewModel
    let onCreateGroup: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: onCreateGroup) {
                        Label(
                            t(ChatTranslationKeys.COMMUNITIES_CREATE_NEW_GROUP),
                            systemImage: "person.2.badge.plus"
                        )
                        .foregroundStyle(AppColors.textPrimary)
                    }
                }

                Section {
                    if viewModel.linkableGroups.isEmpty {
                        Text(t(ChatTranslationKeys.COMMUNITIES_NO_LINKABLE_GROUPS))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.linkableGroups) { group in
                            Button {
                                Task {
                                    await viewModel.attach(group)
                                    onDismiss()
                                }
                            } label: {
                                groupRow(group)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text(t(ChatTranslationKeys.COMMUNITIES_YOUR_GROUPS))
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_ADD_EXISTING_GROUP))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(common("done"), action: onDismiss)
                }
            }
            .task { await viewModel.loadLinkableGroups() }
        }
    }

    @ViewBuilder
    private func groupRow(_ group: GroupChat) -> some View {
        HStack(spacing: 12) {
            CircularProfileImageView(group.avatarUrl, size: .xSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text(group.name)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)
                    .lineLimit(1)

                Text(t(ChatTranslationKeys.COMMUNITIES_MEMBER_COUNT, args: ["\(group.memberCount)"]))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "plus.circle")
                .foregroundStyle(AppColors.primary)
        }
        .contentShape(Rectangle())
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
