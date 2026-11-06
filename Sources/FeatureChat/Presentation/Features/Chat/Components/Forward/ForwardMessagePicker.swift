//
//  ForwardMessagePicker.swift
//  FeatureChat
//
//  Created by Kiro on 2/12/26.
//  Updated: WhatsApp-style UI with animations
//

import SwiftUI
import Foundation
import WaanguSharedUI
import WaanguCoreKit

#if canImport(UIKit)
import UIKit
#endif

// MARK: - Main View

/// Chooses where the selected messages go: an existing chat, a contact with no
/// chat yet, or the user's own status.
///
/// The view holds no selection state of its own — every tap goes to the picker
/// view model, and the send itself is the chat room's, so what is sent and what
/// is shown can never disagree.
struct ForwardMessagePicker: View {
    /// Whichever room raised the picker — a chat or a channel.
    let source: any ForwardMessageSource
    @ObservedObject var statusStore: StoriesViewModel
    @StateObject private var viewModel: ForwardMessagePickerViewModel
    @Environment(\.dismiss) private var dismiss

    init(source: any ForwardMessageSource,
         statusStore: StoriesViewModel,
         contactsUseCases: ContactsUseCasesProtocol,
         discussionUseCases: DiscussionUseCasesProtocol,
         groupUseCases: GroupUseCasesProtocol? = nil) {
        self.source = source
        self.statusStore = statusStore
        _viewModel = StateObject(wrappedValue: ForwardMessagePickerViewModel(
            contactsUseCases: contactsUseCases,
            discussionUseCases: discussionUseCases,
            groupUseCases: groupUseCases,
            translationService: source.translationService
        ))
    }

    private var forwardedMessages: [MessageDataItem] {
        source.messagesToForward
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                VStack(spacing: 0) {
                    searchBar
                    targetList
                    // Keeps the last row clear of the bottom bar.
                    if !viewModel.selection.isEmpty {
                        Color.clear.frame(height: 120)
                    }
                }

                if !viewModel.selection.isEmpty {
                    bottomBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .zIndex(1)
                }
            }
            .navigationTitle(t(ChatTranslationKeys.FORWARD_SEND_TO))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                #if os(iOS)
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(common("cancel")) { dismiss() }
                        .foregroundColor(.primary)
                        .disabled(viewModel.isSending)
                }
                #else
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) { dismiss() }
                        .disabled(viewModel.isSending)
                }
                #endif
            }
            .animation(.spring(response: 0.35, dampingFraction: 0.75), value: viewModel.selection.count)
            .task {
                viewModel.prepareStatusTarget(for: forwardedMessages)
                await viewModel.load()
            }
        }
    }

    // MARK: - Search Bar

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
                .font(.system(size: 15))

            TextField(t(ChatTranslationKeys.FORWARD_SEARCH_PLACEHOLDER), text: $viewModel.searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 16))

            if !viewModel.searchText.isEmpty {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        viewModel.clearSearch()
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                        .font(.system(size: 15))
                }
                .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray5))
        )
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Target List

    private var targetList: some View {
        List {
            if let status = viewModel.visibleStatusTarget {
                Section {
                    row(for: status, subtitle: statusSubtitle)
                }
            }

            if !viewModel.filteredRecentChats.isEmpty {
                Section {
                    ForEach(viewModel.filteredRecentChats) { target in
                        row(for: target)
                    }
                } header: {
                    sectionHeader(t(ChatTranslationKeys.FORWARD_SECTION_RECENT_CHATS))
                }
            }

            if !viewModel.filteredContacts.isEmpty {
                Section {
                    ForEach(viewModel.filteredContacts) { target in
                        row(for: target)
                    }
                } header: {
                    sectionHeader(t(ChatTranslationKeys.FORWARD_SECTION_OTHER_CONTACTS))
                }
            }

            if viewModel.isLoading {
                Section {
                    HStack(spacing: 10) {
                        ProgressView()
                            .scaleEffect(0.85)
                        Text(t(ChatTranslationKeys.FORWARD_LOADING_CONTACTS))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(.red)
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.center)
                        Button(common("retry")) {
                            Task { await viewModel.refresh() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }

            if viewModel.isEmpty {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.3.sequence")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        Text(t(ChatTranslationKeys.FORWARD_EMPTY_TITLE))
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text(t(ChatTranslationKeys.FORWARD_EMPTY_SUBTITLE))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .refreshable {
            await viewModel.refresh()
        }
    }

    private func row(for target: ForwardTarget, subtitle: String? = nil) -> some View {
        let isSelected = viewModel.isSelected(target)
        return ForwardTargetRow(
            target: target,
            subtitle: subtitle ?? viewModel.subtitle(for: target),
            isSelected: isSelected,
            onTap: {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                    viewModel.toggle(target)
                }
            }
        )
        .listRowBackground(
            isSelected ? Color(.systemGray5).opacity(0.6) : Color(.systemGray6)
        )
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    /// What the status row says under "My status" — the real state of the
    /// user's status, not a placeholder count.
    private var statusSubtitle: String {
        let count = statusStore.ownStatus?.status.count ?? 0
        return count == 0
            ? t(ChatTranslationKeys.FORWARD_STATUS_EMPTY)
            : t(ChatTranslationKeys.FORWARD_STATUS_UPDATE_COUNT, args: ["\(count)"])
    }

    // MARK: - Section Header

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.secondary)
            .textCase(nil)
            .padding(.bottom, 2)
    }

    // MARK: - Bottom Bar

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Divider()

            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    ForwardMessageThumbnail(messages: forwardedMessages)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))

                    TextField(t(ChatTranslationKeys.FORWARD_ADD_MESSAGE_PLACEHOLDER), text: $viewModel.caption)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 22)
                                .fill(Color(.systemGray5))
                        )
                        .font(.system(size: 15))
                        .disabled(viewModel.isSending)
                }

                HStack(alignment: .center) {
                    Text(viewModel.selectedNamesLabel)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .animation(.easeInOut(duration: 0.2), value: viewModel.selectedNamesLabel)

                    Spacer()

                    Button {
                        Task { await send() }
                    } label: {
                        if viewModel.isSending {
                            ProgressView()
                                .scaleEffect(0.8)
                        } else {
                            Text(t(ChatTranslationKeys.FORWARD_SEND))
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundColor(AppColors.primary)
                        }
                    }
                    .disabled(!viewModel.canSend)
                    .opacity(viewModel.canSend ? 1 : 0.5)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
        }
    }

    // MARK: - Send

    private func send() async {
        guard viewModel.canSend else { return }
        viewModel.beginSending()
        await source.forward(
            to: viewModel.selection,
            caption: viewModel.trimmedCaption,
            statusPoster: statusStore
        )
        viewModel.endSending()
    }

    // MARK: - Translation

    private func t(_ key: String, args: [String] = []) -> String {
        source.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }

    private func common(_ key: String) -> String {
        source.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.COMMON_MODULE
        ).value ?? key.capitalized
    }
}

// MARK: - Message Thumbnail

/// Preview of what is being forwarded: the first message's own media when it is
/// on disk, its type icon otherwise, badged with how many more come with it.
private struct ForwardMessageThumbnail: View {
    let messages: [MessageDataItem]

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGray4))
                .frame(width: 52, height: 52)
                .overlay {
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    } else {
                        typeIcon
                            .font(.title2)
                            .foregroundColor(.secondary)
                    }
                }

            if messages.count > 1 {
                Text("+\(messages.count - 1)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(AppColors.primary))
                    .offset(x: 6, y: 4)
            }
        }
    }

    private var preview: UIImage? {
        guard let first = messages.first else { return nil }
        switch first.typeMessage {
        case .IMAGE, .VIDEO, .VIDEO_NOTE:
            return DiskMediaManager.shared.loadImageFromDisk(
                fileName: first.codeMessage,
                pathName: .CHAT
            )
        default:
            return nil
        }
    }

    @ViewBuilder
    private var typeIcon: some View {
        switch messages.first?.typeMessage {
        case .TEXT:          Image(systemName: "text.bubble")
        case .IMAGE:         Image(systemName: "photo")
        case .VIDEO, .VIDEO_NOTE: Image(systemName: "video")
        case .AUDIO, .VOICE: Image(systemName: "mic")
        case .DOCUMENT:      Image(systemName: "doc")
        case .LOCATION:      Image(systemName: "mappin.circle")
        case .CONTACT:       Image(systemName: "person.crop.circle")
        default:             Image(systemName: "ellipsis.bubble")
        }
    }
}

// MARK: - Target Row

private struct ForwardTargetRow: View {
    let target: ForwardTarget
    let subtitle: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                avatar

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                Spacer()

                if target.isBlocked {
                    Image(systemName: "hand.raised.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                }

                SelectionCircle(isSelected: isSelected)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!target.isSelectable)
        .opacity(target.isSelectable ? 1.0 : 0.5)
    }

    @ViewBuilder
    private var avatar: some View {
        AsyncImage(url: target.avatar.flatMap { URL(string: $0) }) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            Circle()
                .fill(target.isGroup ? AppColors.primary.opacity(0.8) : Color(.systemGray3))
                .overlay {
                    if target.isStatus {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    } else if target.isGroup {
                        Image(systemName: "person.3.fill")
                            .font(.system(size: 16))
                            .foregroundColor(.white)
                    } else {
                        Text(String(target.name.prefix(1)).uppercased())
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
        }
        .frame(width: 48, height: 48)
        .clipShape(Circle())
        .overlay {
            // The status ring, the same cue the stories strip uses.
            if target.isStatus {
                Circle()
                    .strokeBorder(
                        LinearGradient(
                            colors: [Color.white, AppColors.primary, AppColors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        lineWidth: 2.5
                    )
            }
        }
    }
}

// MARK: - SelectionCircle (animated WhatsApp-style checkmark)

private struct SelectionCircle: View {
    let isSelected: Bool

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(isSelected ? Color.clear : Color(.systemGray3), lineWidth: 1.5)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(isSelected ? AppColors.primary : Color.clear)
                )

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(width: 24, height: 24)
        .animation(.spring(response: 0.25, dampingFraction: 0.6), value: isSelected)
    }
}
