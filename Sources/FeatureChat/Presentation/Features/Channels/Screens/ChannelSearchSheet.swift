//
//  ChannelSearchSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit

/// Searching inside a channel.
///
/// `MessageSearchViewModel.searchInChat(messages:)` searches what a room has
/// loaded rather than the whole store, so this is raised from the room — which
/// holds the posts — and seeded with them on appear.
@available(iOS 16.0, *)
struct ChannelSearchSheet: View {

    let posts: [MessageDataItem]
    let makeViewModel: () -> MessageSearchViewModel
    let translationService: (any TranslationServiceProtocol)?

    @State private var viewModel: MessageSearchViewModel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    MessageSearchView(
                        viewModel: viewModel,
                        onSelectResult: { _ in dismiss() },
                        translationService: translationService
                    )
                } else {
                    ProgressView()
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(common("cancel")) { dismiss() }
                }
            }
        }
        .onAppear {
            guard viewModel == nil else { return }
            let model = makeViewModel()
            model.searchInChat(messages: posts)
            viewModel = model
        }
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
