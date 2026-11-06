//
//  CommunityMembersView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Members of a community, read off the announcements group roster — every
/// member of the community is a participant of that conversation.
///
/// Administration is only offered to owners and admins; the actions themselves
/// are still enforced by Identity.
@available(iOS 16.0, *)
struct CommunityMembersView: View {

    @StateObject private var viewModel: CommunityDetailViewModel

    @State private var pendingTransfer: CommunityMember?

    init(viewModel: CommunityDetailViewModel) {
        self._viewModel = StateObject(wrappedValue: viewModel)
    }

    var body: some View {
        List {
            if viewModel.members.isEmpty {
                Text(t(ChatTranslationKeys.COMMUNITIES_NO_MEMBERS))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(viewModel.members) { member in
                memberRow(member)
            }

        }
        .listStyle(.insetGrouped)
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
        .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_MEMBERS))
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await viewModel.load() }
        .onAppear { viewModel.onAppear() }
        // Le dialogue de l'application et non `confirmationDialog` : celui du
        // système suit le réglage de l'appareil, pas l'apparence choisie ici.
        .chatAppearanceDialog(
            isPresented: Binding(
                get: { pendingTransfer != nil },
                set: { if !$0 { pendingTransfer = nil } }
            ),
            configuration: transferConfiguration
        )
    }

    /// Céder la propriété à `pendingTransfer`.
    ///
    /// Le membre est capturé à la construction : l'action s'exécute après la
    /// fermeture du dialogue, quand `pendingTransfer` est déjà remis à `nil`.
    private var transferConfiguration: DialogConfiguration {
        let title = t(ChatTranslationKeys.COMMUNITIES_TRANSFER_OWNER)
        var buttons: [DialogButton] = []
        if let member = pendingTransfer {
            buttons.append(DialogButton(title: title, role: .destructive) {
                Task { await viewModel.transferOwnership(to: member.userId) }
            })
        }
        buttons.append(DialogButton(title: t(ChatTranslationKeys.CHAT_CANCEL), role: .cancel) {})
        return DialogConfiguration(title: title, style: .destructive, buttons: buttons)
    }

    @ViewBuilder
    private func memberRow(_ member: CommunityMember) -> some View {
        HStack(spacing: 12) {
            CircularProfileImageView(member.avatar, size: .xSmall)

            VStack(alignment: .leading, spacing: 2) {
                Text(member.userName.isEmpty ? member.userId : member.userName)
                    .font(.system(size: 16, weight: .medium))
                    .lineLimit(1)

                Text(roleLabel(member.role))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if viewModel.canAdminister && member.role != .owner {
                menu(for: member)
            }
        }
    }

    @ViewBuilder
    private func menu(for member: CommunityMember) -> some View {
        Menu {
            if member.role == .admin {
                Button(t(ChatTranslationKeys.COMMUNITIES_MAKE_MEMBER)) {
                    Task { await viewModel.updateRole(userId: member.userId, to: .member) }
                }
            } else {
                Button(t(ChatTranslationKeys.COMMUNITIES_MAKE_ADMIN)) {
                    Task { await viewModel.updateRole(userId: member.userId, to: .admin) }
                }
            }

            if viewModel.myRole == .owner {
                Button(t(ChatTranslationKeys.COMMUNITIES_TRANSFER_OWNER)) {
                    pendingTransfer = member
                }
            }

            Button(t(ChatTranslationKeys.COMMUNITIES_REMOVE_MEMBER), role: .destructive) {
                Task { await viewModel.removeMember(userId: member.userId) }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .foregroundStyle(.secondary)
        }
    }

    private func roleLabel(_ role: CommunityRole) -> String {
        switch role {
        case .owner:     return t(ChatTranslationKeys.COMMUNITIES_ROLE_OWNER)
        case .admin:     return t(ChatTranslationKeys.COMMUNITIES_ROLE_ADMIN)
        case .moderator: return t(ChatTranslationKeys.COMMUNITIES_ROLE_MODERATOR)
        case .member:    return t(ChatTranslationKeys.COMMUNITIES_ROLE_MEMBER)
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    /// Shared strings live in the common module, not the chat one.
    private func common(_ key: String) -> String {
        viewModel.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
