//
//  CommunityInfoView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Everything about a community that is not its list of rooms: what it is, who
/// is in it, and the two ways out.
///
/// Leaving and deleting live here rather than on the detail screen — a screen
/// you open to read the announcements should not offer to delete the community
/// in the same breath.
@available(iOS 16.0, *)
struct CommunityInfoView: View {

    @StateObject private var viewModel: CommunityDetailViewModel
    let onShowMembers: (String) -> Void
    let onShowSettings: (String) -> Void
    let onLeft: () -> Void

    @State private var showLeaveConfirmation = false
    @State private var showInviteShare = false

    init(
        viewModel: CommunityDetailViewModel,
        onShowMembers: @escaping (String) -> Void,
        onShowSettings: @escaping (String) -> Void,
        onLeft: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onShowMembers = onShowMembers
        self.onShowSettings = onShowSettings
        self.onLeft = onLeft
    }

    /// Quitter la communauté — ou la supprimer, pour son propriétaire.
    private var leaveConfiguration: DialogConfiguration {
        let isOwner = viewModel.myRole == .owner
        let title = isOwner
            ? t(ChatTranslationKeys.COMMUNITIES_DELETE)
            : t(ChatTranslationKeys.COMMUNITIES_LEAVE)
        return DialogConfiguration(
            title: title,
            style: .destructive,
            buttons: [
                DialogButton(title: title, role: .destructive) {
                    Task {
                        if isOwner {
                            await viewModel.delete()
                        } else {
                            await viewModel.leave()
                        }
                    }
                },
                DialogButton(title: common("cancel"), role: .cancel) {}
            ]
        )
    }

    var body: some View {
        List {
            header()

            if let description = viewModel.community?.description, !description.isEmpty {
                Section {
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(AppColors.textPrimary)
                }
            }

            Section {
                Button {
                    onShowMembers(viewModel.communityId)
                } label: {
                    row(
                        title: t(ChatTranslationKeys.COMMUNITIES_MEMBERS),
                        systemImage: "person.2",
                        detail: "\(viewModel.members.count)"
                    )
                }
                .buttonStyle(.plain)

                if viewModel.canAdminister {
                    Button {
                        onShowSettings(viewModel.communityId)
                    } label: {
                        row(
                            title: t(ChatTranslationKeys.COMMUNITIES_SETTINGS),
                            systemImage: "gearshape",
                            detail: ""
                        )
                    }
                    .buttonStyle(.plain)
                }

                if let code = viewModel.community?.inviteCode, !code.isEmpty {
                    Button {
                        showInviteShare = true
                    } label: {
                        row(
                            title: t(ChatTranslationKeys.COMMUNITIES_INVITE_MEMBERS),
                            systemImage: "person.badge.plus",
                            detail: code
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            Section {
                Button(role: .destructive) {
                    showLeaveConfirmation = true
                } label: {
                    Text(viewModel.myRole == .owner
                         ? t(ChatTranslationKeys.COMMUNITIES_DELETE)
                         : t(ChatTranslationKeys.COMMUNITIES_LEAVE))
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_INFO))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .onAppear { viewModel.onAppear() }
        .onChange(of: viewModel.didLeave) { _, didLeave in
            if didLeave { onLeft() }
        }
        .chatAppearanceSheet(isPresented: $showInviteShare) {
            if let community = viewModel.community, let code = community.inviteCode {
                ActivityShareSheet(activityItems: [
                    t(ChatTranslationKeys.COMMUNITIES_INVITE_SHARE_TEXT, args: [community.name, code])
                ])
            }
        }
        // Le dialogue de l'application et non `confirmationDialog` : celui du
        // système suit le réglage de l'appareil, pas l'apparence choisie ici.
        .chatAppearanceDialog(
            isPresented: $showLeaveConfirmation,
            configuration: leaveConfiguration
        )
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

    // MARK: - Pieces

    @ViewBuilder
    private func header() -> some View {
        Section {
            VStack(spacing: 10) {
                CommunityAvatar(imageUrl: viewModel.community?.image, size: 96)

                Text(viewModel.community?.name ?? "")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(
                    t(ChatTranslationKeys.COMMUNITIES_SUBTITLE)
                    + " · "
                    + t(ChatTranslationKeys.COMMUNITIES_GROUP_COUNT, args: ["\(viewModel.groups.count)"])
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func row(title: String, systemImage: String, detail: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    /// Shared strings live in the common module, not the chat one.
    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
