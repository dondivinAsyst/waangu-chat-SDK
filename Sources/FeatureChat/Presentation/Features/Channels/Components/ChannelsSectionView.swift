//
//  ChannelsSectionView.swift
//  FeatureChat
//
//  The channels block of the Updates tab.
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Channels this user follows, with a way into the directory.
///
/// Creating a channel is deliberately *not* here — it lives in the tab's
/// overflow menu, next to the other channel-wide actions. This block is a list
/// with a heading, and a heading is not a place to put a create button.
///
/// A followed channel is one whose broadcast conversation is in the inbox, so
/// the list fills in after the first sync that follows a subscribe.
@available(iOS 16.0, *)
struct ChannelsSectionView: View {

    @ObservedObject var viewModel: ChannelsViewModel
    let onOpenChannel: (String) -> Void
    let onExplore: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()

            if viewModel.isLoading && viewModel.followed.isEmpty {
                loadingRow()
            } else if let loadError = viewModel.loadError, viewModel.followed.isEmpty {
                loadErrorRow(loadError)
            } else if viewModel.followed.isEmpty {
                emptyState()
            } else {
                ForEach(viewModel.followed) { item in
                    Button {
                        onOpenChannel(item.channel.id)
                    } label: {
                        FollowedChannelRow(
                            item: item,
                            translationService: viewModel.translationService
                        )
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                }
            }


            findChannelsRow()
        }
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
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header() -> some View {
        HStack {
            Text(t(ChatTranslationKeys.STORIES_CHANNELS))
                .font(.title2.weight(.bold))
                .foregroundStyle(AppColors.textPrimary)

            Spacer()

            Button(action: onExplore) {
                Text(t(ChatTranslationKeys.CHANNELS_EXPLORE))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AppColors.primary.opacity(0.12))
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private func loadingRow() -> some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(t(ChatTranslationKeys.CHANNELS_LOADING))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }

    /// The list could not be read: say so where the list would be, with a way
    /// to try again — not a modal over the whole tab.
    private func loadErrorRow(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.icloud")
                .font(.system(size: 20))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(common("retry")) {
                Task { await viewModel.load() }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(AppColors.primary)
            .buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .transition(.opacity)
    }

    @ViewBuilder
    private func emptyState() -> some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 34))
                .foregroundStyle(AppColors.primary.opacity(0.6))

            Text(t(ChatTranslationKeys.CHANNELS_NONE_FOLLOWED))
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(t(ChatTranslationKeys.STORIES_NO_CHANNELS_DESC))
                .font(.subheadline)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    /// Closes the list the way the rest of the app closes a section: a row that
    /// leads somewhere, not a floating button.
    @ViewBuilder
    private func findChannelsRow() -> some View {
        Button(action: onExplore) {
            HStack {
                Text(t(ChatTranslationKeys.CHANNELS_FIND_TO_FOLLOW))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColors.textPrimary)

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
