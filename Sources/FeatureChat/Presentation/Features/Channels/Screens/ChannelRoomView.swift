//
//  ChannelRoomView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// A channel, read.
///
/// Lives in the Updates tab, where the channel was found — opening one used to
/// throw the reader into the chats tab, which is where their conversations are,
/// not their subscriptions.
@available(iOS 16.0, *)
struct ChannelRoomView: View {

    @StateObject private var viewModel: ChannelRoomViewModel
    /// The media manager and gallery the composer's sheets are built from.
    let mediaViewModel: PHMediaManagerViewModel
    let galleryViewModel: GalleryViewModel
    let financeSurface: ChatFinanceSurface
    /// The forward picker needs somewhere to offer "my status", and the contacts
    /// and discussions it lists.
    let statusStore: StoriesViewModel
    let contactsUseCases: ContactsUseCasesProtocol
    let discussionUseCases: DiscussionUseCasesProtocol
    /// Searching a channel searches what the room has loaded, so the room is
    /// where it belongs — the info screen holds no posts.
    let makeSearchViewModel: () -> MessageSearchViewModel
    let onShowInfo: (String) -> Void
    /// Opens the status composer, so a new channel can be announced where the
    /// owner's followers already look.
    let onShareToStatus: () -> Void
    let onUnfollowed: () -> Void

    @State private var draft = ""
    @State private var showShare = false
    @State private var showSearch = false
    @State private var composerHeight: CGFloat = 44
    @ObservedObject private var appearanceStore = ChatAppearanceStore.shared
    @Environment(\.colorScheme) private var colorScheme

    init(
        viewModel: ChannelRoomViewModel,
        mediaViewModel: PHMediaManagerViewModel,
        galleryViewModel: GalleryViewModel,
        financeSurface: ChatFinanceSurface,
        statusStore: StoriesViewModel,
        contactsUseCases: ContactsUseCasesProtocol,
        discussionUseCases: DiscussionUseCasesProtocol,
        makeSearchViewModel: @escaping () -> MessageSearchViewModel,
        onShowInfo: @escaping (String) -> Void,
        onShareToStatus: @escaping () -> Void,
        onUnfollowed: @escaping () -> Void
    ) {
        self._viewModel = StateObject(wrappedValue: viewModel)
        self.mediaViewModel = mediaViewModel
        self.galleryViewModel = galleryViewModel
        self.financeSurface = financeSurface
        self.statusStore = statusStore
        self.contactsUseCases = contactsUseCases
        self.discussionUseCases = discussionUseCases
        self.makeSearchViewModel = makeSearchViewModel
        self.onShowInfo = onShowInfo
        self.onShareToStatus = onShareToStatus
        self.onUnfollowed = onUnfollowed
    }

    var body: some View {
        ZStack {
            // The chat wallpaper, not a flat fill: a channel is read in the
            // same place conversations are, and MessageListView draws exactly
            // this behind every other room.
            Image("chatBackground", bundle: .module)
                .resizable()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                postList()

                if viewModel.canPost {
                    composer()
                } else {
                    followerBar()
                }
            }
        }
        .preferredColorScheme(appearanceStore.defaultAppearance.preferredColorScheme)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { titleView() }
            ToolbarItem(placement: .topBarTrailing) { trailingButtons() }
        }
        .onAppear { viewModel.onAppear() }
        .onDisappear { viewModel.onDisappear() }
        .modifier(
            ChannelMediaSheets(
                viewModel: viewModel,
                mediaViewModel: mediaViewModel,
                galleryViewModel: galleryViewModel,
                financeSurface: financeSurface
            )
        )
        .chatAppearanceSheet(isPresented: .init(
            get: { viewModel.postBeingForwarded != nil },
            set: { if !$0 { viewModel.postBeingForwarded = nil } }
        )) {
            ForwardMessagePicker(
                source: viewModel,
                statusStore: statusStore,
                contactsUseCases: contactsUseCases,
                discussionUseCases: discussionUseCases
            )
        }
        .chatAppearanceSheet(isPresented: $showSearch) {
            ChannelSearchSheet(
                posts: viewModel.posts,
                makeViewModel: makeSearchViewModel,
                translationService: viewModel.translationService
            )
        }
        .chatAppearanceSheet(isPresented: $showShare) {
            if let channel = viewModel.channel {
                ActivityShareSheet(activityItems: [channel.name])
            }
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

    // MARK: - Posts

    /// Oldest at the top, newest at the bottom, opened at the bottom — the same
    /// reading order as every other room, so a new post appears just above the
    /// composer that wrote it.
    @ViewBuilder
    private func postList() -> some View {
        if viewModel.isLoading && viewModel.posts.isEmpty {
            Spacer()
            ProgressView()
            Spacer()
        } else if viewModel.posts.isEmpty {
            emptyState()
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(viewModel.posts) { post in
                            ChannelPostCard(
                                post: post,
                                views: viewModel.views(of: post),
                                translationService: viewModel.translationService,
                                onReact: { reaction in
                                    Task { await viewModel.react(to: post, with: reaction) }
                                },
                                onForward: { viewModel.beginForwarding(post) }
                            )
                            .id(post.id)
                            .onAppear {
                                // The top of the list is where the older posts
                                // are now that the newest sit at the bottom.
                                if post.id == viewModel.posts.first?.id {
                                    Task { await viewModel.loadOlderPosts() }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 12)
                }
                .onAppear { scrollToLatest(proxy, animated: false) }
                .onChange(of: viewModel.posts.last?.id) { _, _ in
                    scrollToLatest(proxy, animated: true)
                }
            }
        }
    }

    private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool) {
        guard let last = viewModel.posts.last?.id else { return }
        if animated {
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(last, anchor: .bottom) }
        } else {
            proxy.scrollTo(last, anchor: .bottom)
        }
    }

    @ViewBuilder
    private func emptyState() -> some View {
        ScrollView {
            if let channel = viewModel.channel {
                ChannelStartCard(
                    channel: channel,
                    translationService: viewModel.translationService,
                    onAddPhoto: { onShowInfo(channel.id) },
                    onShareToStatus: onShareToStatus
                )
                .opacity(viewModel.canPost ? 1 : 0)
                .frame(height: viewModel.canPost ? nil : 0)

                if !viewModel.canPost {
                    Text(t(ChatTranslationKeys.CHANNELS_NO_POSTS_YET))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                }
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func titleView() -> some View {
        Button {
            onShowInfo(viewModel.channel?.id ?? "")
        } label: {
            HStack(spacing: 8) {
                CircularProfileImageView(viewModel.channel?.image, size: .mini)

                VStack(alignment: .leading, spacing: 0) {
                    Text(viewModel.channel?.name ?? "")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    Text(t(
                        ChatTranslationKeys.CHANNELS_FOLLOWER_COUNT,
                        args: [ChannelListRow.compact(viewModel.followerCount)]
                    ))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailingButtons() -> some View {
        HStack(spacing: 4) {
            Button {
                Task { await viewModel.toggleMute() }
            } label: {
                Image(systemName: viewModel.isMuted ? "bell.slash.fill" : "bell")
                    .foregroundStyle(viewModel.isMuted ? AppColors.primary : AppColors.textPrimary)
            }

            Menu {
                Button {
                    onShowInfo(viewModel.channel?.id ?? "")
                } label: {
                    Label(t(ChatTranslationKeys.CHANNELS_INFO), systemImage: "info.circle")
                }

                Button {
                    showSearch = true
                } label: {
                    Label(t(ChatTranslationKeys.CHANNELS_SEARCH_POSTS), systemImage: "magnifyingglass")
                }

                Button {
                    showShare = true
                } label: {
                    Label(t(ChatTranslationKeys.CHANNELS_SHARE_CHANNEL), systemImage: "square.and.arrow.up")
                }

                if let channel = viewModel.channel,
                   !channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
                    Button(role: .destructive) {
                        Task {
                            await viewModel.unfollow()
                            onUnfollowed()
                        }
                    } label: {
                        Label(t(ChatTranslationKeys.CHANNELS_UNFOLLOW), systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(AppColors.textPrimary)
            }
        }
    }

    // MARK: - Bottom

    /// The owner's composer — the app's real input bar, the same UIKit toolbar
    /// every chat uses, driven by this room's own view model.
    @ViewBuilder
    private func composer() -> some View {
        TextInputToolbarAreaViewWrapper(
            text: $draft,
            voiceRecordingViewModel: viewModel.voiceRecordingViewModel,
            translationService: viewModel.translationService,
            userInterfaceStyle: appearanceStore.defaultAppearance.userInterfaceStyle,
            onPresentSheet: { viewModel.onOpenAttachments() },
            onOpenCamera: { viewModel.onOpenCamera() },
            onSendMessage: { text in
                draft = ""
                Task { await viewModel.post(text) }
            },
            onSendAudio: {
                Task { await viewModel.stopVoiceRecordingAndSend() }
            },
            onStartRecording: {
                Task { await viewModel.startVoiceRecording() }
            },
            onStopRecording: {
                Task { await viewModel.cancelVoiceRecording() }
            },
            onPauseOrResumeRecording: { isPaused in
                Task {
                    if isPaused {
                        await viewModel.resumeVoiceRecording()
                    } else {
                        await viewModel.pauseVoiceRecording()
                    }
                }
            },
            contentHeight: $composerHeight
        )
        .frame(height: composerHeight)
        .background(Material.regular)
    }

    /// What a follower gets instead of a composer. It says why, rather than
    /// leaving the bottom of the screen mysteriously empty.
    @ViewBuilder
    private func followerBar() -> some View {
        Text(t(ChatTranslationKeys.CHANNELS_ONLY_OWNER_POSTS))
            .font(.footnote)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Material.regular)
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


