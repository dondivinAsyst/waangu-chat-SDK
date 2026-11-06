//
//  CommunityDetailView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// One community: announcements, then the groups you are in, then the ones you
/// could join.
///
/// Tapping any of them opens its Core conversation, which lives in the chats
/// tab — this screen asks for it and the coordinator switches tabs. Nothing
/// destructive lives here: leaving and deleting are in community info.
@available(iOS 16.0, *)
struct CommunityDetailView: View {

    @StateObject private var viewModel: CommunityDetailViewModel
    let partnerPicker: ChatPartnerPickerViewModel
    let onOpenConversation: (String) -> Void
    let onShowInfo: (String) -> Void
    let onLeft: () -> Void

    @State private var showAddGroup = false
    @State private var showCreateGroup = false
    @State private var showInviteShare = false

    init(
        viewModel: CommunityDetailViewModel,
        partnerPicker: ChatPartnerPickerViewModel,
        onOpenConversation: @escaping (String) -> Void,
        onShowInfo: @escaping (String) -> Void,
        onLeft: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.partnerPicker = partnerPicker
        self.onOpenConversation = onOpenConversation
        self.onShowInfo = onShowInfo
        self.onLeft = onLeft
    }

    var body: some View {
        VStack(spacing: 0) {
            List {
                header()

                if let announcement = viewModel.announcementGroup {
                    Section { groupRow(announcement) }
                }

                Section {
                    if viewModel.joinedGroups.isEmpty {
                        Text(t(ChatTranslationKeys.COMMUNITIES_OTHER_GROUPS_HINT))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(viewModel.joinedGroups) { group in
                            groupRow(group)
                                .swipeActions(edge: .trailing) {
                                    detachAction(group)
                                }
                        }
                    }
                } header: {
                    Text(t(ChatTranslationKeys.COMMUNITIES_GROUPS_YOURE_IN))
                }

                if !viewModel.joinableGroups.isEmpty {
                    Section {
                        ForEach(viewModel.joinableGroups) { group in
                            HStack(spacing: 10) {
                                groupRow(group)

                                Button(t(ChatTranslationKeys.COMMUNITIES_JOIN_GROUP)) {
                                    Task { await viewModel.join(group) }
                                }
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(AppColors.primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(AppColors.primary.opacity(0.12))
                                .clipShape(Capsule())
                                .buttonStyle(.plain)
                            }
                            .swipeActions(edge: .trailing) {
                                detachAction(group)
                            }
                        }
                    } header: {
                        Text(t(ChatTranslationKeys.COMMUNITIES_OTHER_GROUPS))
                    } footer: {
                        Text(t(ChatTranslationKeys.COMMUNITIES_OTHER_GROUPS_HINT))
                    }
                }
            }
            .listStyle(.insetGrouped)

            if viewModel.canAdminister {
                addGroupButton()
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                overflowMenu()
            }
        }
        .refreshable { await viewModel.load() }
        .onAppear { viewModel.onAppear() }
        .onChange(of: viewModel.didLeave) { _, didLeave in
            if didLeave { onLeft() }
        }
        .chatAppearanceSheet(isPresented: $showAddGroup) {
            CommunityAddGroupSheet(
                viewModel: viewModel,
                onCreateGroup: {
                    showAddGroup = false
                    showCreateGroup = true
                },
                onDismiss: { showAddGroup = false }
            )
        }
        .chatAppearanceSheet(isPresented: $showCreateGroup) {
            CommunityCreateGroupSheet(
                viewModel: viewModel,
                partnerPicker: partnerPicker,
                onDismiss: { showCreateGroup = false }
            )
        }
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

    // MARK: - Header

    /// Avatar, name and one word for what this is — the same shape a group
    /// header has, so the two read as siblings.
    @ViewBuilder
    private func header() -> some View {
        Section {
            HStack(spacing: 14) {
                CommunityAvatar(imageUrl: viewModel.community?.image, size: 56)

                VStack(alignment: .leading, spacing: 2) {
                    Text(viewModel.community?.name ?? "")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(2)

                    Text(t(ChatTranslationKeys.COMMUNITIES_SUBTITLE))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
    }

    // MARK: - Rows

    @ViewBuilder
    private func groupRow(_ group: CommunityGroupSummary) -> some View {
        Button {
            open(group)
        } label: {
            CommunityGroupRow(
                group: group,
                canWrite: group.canWrite(as: viewModel.myRole),
                preview: viewModel.preview(for: group),
                translationService: viewModel.translationService
            )
        }
        .buttonStyle(.plain)
        .disabled(!group.isOpenable)
    }

    @ViewBuilder
    private func detachAction(_ group: CommunityGroupSummary) -> some View {
        if viewModel.canAdminister {
            Button(role: .destructive) {
                Task { await viewModel.detach(group) }
            } label: {
                Label(
                    t(ChatTranslationKeys.COMMUNITIES_DETACH_GROUP),
                    systemImage: "minus.circle"
                )
            }
        }
    }

    /// The screen's primary action, pinned rather than buried in a menu.
    @ViewBuilder
    private func addGroupButton() -> some View {
        Button {
            showAddGroup = true
        } label: {
            Label(t(ChatTranslationKeys.COMMUNITIES_ADD_GROUP), systemImage: "plus")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(AppColors.primary)
                .foregroundStyle(AppColors.white)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
        .padding(.top, 8)
        .background(.bar)
    }

    @ViewBuilder
    private func overflowMenu() -> some View {
        Menu {
            Button {
                onShowInfo(viewModel.communityId)
            } label: {
                Label(t(ChatTranslationKeys.COMMUNITIES_INFO), systemImage: "info.circle")
            }

            if let code = viewModel.community?.inviteCode, !code.isEmpty {
                Button {
                    showInviteShare = true
                } label: {
                    Label(
                        t(ChatTranslationKeys.COMMUNITIES_INVITE_MEMBERS),
                        systemImage: "person.badge.plus"
                    )
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.textPrimary)
                .padding(8)
                .background(Circle().fill(Color(.systemGray5)))
        }
        .chatAppearanceSheet(isPresented: $showInviteShare) {
            if let community = viewModel.community, let code = community.inviteCode {
                ActivityShareSheet(activityItems: [
                    t(
                        ChatTranslationKeys.COMMUNITIES_INVITE_SHARE_TEXT,
                        args: [community.name, code]
                    )
                ])
            }
        }
    }

    private func open(_ group: CommunityGroupSummary) {
        Task {
            if let conversationId = await viewModel.conversationId(for: group) {
                onOpenConversation(conversationId)
            }
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
