//
//  ExploreChannelsView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// The channel directory — everything Identity lists that this user does not
/// already follow.
@available(iOS 16.0, *)
struct ExploreChannelsView: View {

    @ObservedObject var viewModel: ChannelsViewModel
    let onOpenChannel: (String) -> Void

    @State private var searchText = ""

    var body: some View {
        List {
            if viewModel.isLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text(t(ChatTranslationKeys.CHANNELS_LOADING))
                        .foregroundStyle(.secondary)
                }
            }


            ForEach(filtered) { channel in
                Button {
                    onOpenChannel(channel.id)
                } label: {
                    ChannelListRow(
                        channel: channel,
                        translationService: viewModel.translationService,
                        onToggleSubscription: {
                            Task { await viewModel.toggleSubscription(channel) }
                        },
                        onDismiss: { viewModel.dismissSuggestion(channel) }
                    )
                }
                .buttonStyle(.plain)
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
        .navigationTitle(t(ChatTranslationKeys.CHANNELS_EXPLORE))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText)
        .refreshable { await viewModel.load() }
        .onAppear { viewModel.onAppear() }
    }

    private var filtered: [Channel] {
        let channels = viewModel.suggestions
        guard !searchText.isEmpty else { return channels }
        return channels.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
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
