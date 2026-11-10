//
//  CommunityTabScreen.swift
//  FeatureChat
//
//  The communities tab. The NavigationStack belongs to CommunitiesTabView —
//  this screen is its root content and must not nest another one.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct CommunityTabScreen: View {

    @StateObject private var viewModel: CommunitiesViewModel
    let onNavigate: (CommunitiesTabRoute) -> Void

    @State private var showCreateIntro = false

    init(
        viewModel: CommunitiesViewModel,
        onNavigate: @escaping (CommunitiesTabRoute) -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.onNavigate = onNavigate
    }

    var body: some View {
        List {
            if viewModel.isLoading {
                Section { loadingRow() }
            } else if viewModel.isEmpty {
                Section { emptyState() }
                    .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.communities) { community in
                    communitySection(community)
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_TITLE))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                addMenu()
            }
        }
        .refreshable { await viewModel.refresh() }
        .onAppear { viewModel.onAppear() }
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
        .chatAppearanceSheet(isPresented: $showCreateIntro) {
            CommunityCreateFlowSheet(
                viewModel: viewModel,
                onCreated: { community in
                    showCreateIntro = false
                    onNavigate(.communityDetail(communityId: community.id))
                },
                onDismiss: { showCreateIntro = false }
            )
        }
    }

    // MARK: - Sections

    /// One community: its name with a way into the detail, then the rooms it
    /// holds — announcements first, as the server returns them.
    @ViewBuilder
    private func communitySection(_ community: Community) -> some View {
        Section {
            ForEach(previewGroups(of: community)) { group in
                Button {
                    onNavigate(.communityDetail(communityId: community.id))
                } label: {
                    CommunityGroupRow(
                        group: group,
                        canWrite: group.canWrite(as: community.myRole),
                        preview: viewModel.preview(for: group),
                        translationService: viewModel.translationService
                    )
                }
                .buttonStyle(.plain)
            }
        } header: {
            HStack {
                Text(community.name)
                    .font(.headline)
                    .textCase(nil)
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Button(t(ChatTranslationKeys.COMMUNITIES_SEE_ALL)) {
                    onNavigate(.communityDetail(communityId: community.id))
                }
                .font(.subheadline.weight(.semibold))
                .textCase(nil)
                .foregroundStyle(AppColors.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(AppColors.primary.opacity(0.12))
                .clipShape(Capsule())
            }
        }
    }

    /// Announcements plus the first few groups. The rest is behind "See all" —
    /// a community with forty groups must not push the next one off the screen.
    private func previewGroups(of community: Community) -> [CommunityGroupSummary] {
        Array(community.groups.prefix(4))
    }

    // MARK: - Rows

    @ViewBuilder
    private func loadingRow() -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(t(ChatTranslationKeys.COMMUNITIES_LOADING))
                .foregroundStyle(.secondary)
        }
    }

    /// No community yet: what one is, and both ways in, so the tab is never a
    /// dead end. The same picture band and badge as the create-community sheet.
    @ViewBuilder
    private func emptyState() -> some View {
        VStack(spacing: 0) {
            ChatHeroBand(symbol: "person.3", height: 170, cornerRadius: 26)

            VStack(spacing: 10) {
                Text(t(ChatTranslationKeys.COMMUNITIES_EMPTY_TITLE))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text(t(ChatTranslationKeys.COMMUNITIES_EMPTY_SUBTITLE))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 12)
            .padding(.top, 22)
            .staggeredAppear(1)

            VStack(spacing: 10) {
                Button {
                    showCreateIntro = true
                } label: {
                    Label(t(ChatTranslationKeys.COMMUNITIES_NEW), systemImage: "plus")
                        .font(.headline)
                        .foregroundStyle(Color.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(AppColors.primary, in: Capsule())
                        .shadow(color: AppColors.primary.opacity(0.28), radius: 10, y: 5)
                }
                .buttonStyle(.plain)

                Button {
                    onNavigate(.joinCommunity)
                } label: {
                    Label(t(ChatTranslationKeys.COMMUNITIES_JOIN_WITH_CODE), systemImage: "key")
                        .font(.headline)
                        .foregroundStyle(AppColors.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(Capsule().strokeBorder(AppColors.primary.opacity(0.35), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 24)
            .staggeredAppear(2)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    /// Both ways in, where iOS puts them: the navigation bar, not stacked at the
    /// bottom of the list.
    @ViewBuilder
    private func addMenu() -> some View {
        Menu {
            Button {
                showCreateIntro = true
            } label: {
                Label(t(ChatTranslationKeys.COMMUNITIES_NEW), systemImage: "person.3")
            }

            Button {
                onNavigate(.joinCommunity)
            } label: {
                Label(t(ChatTranslationKeys.COMMUNITIES_JOIN_WITH_CODE), systemImage: "key")
            }
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColors.primary)
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
