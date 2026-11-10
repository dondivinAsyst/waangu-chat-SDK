//
//  CreateChannelView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit
import UIKit

/// Creating a channel also creates its Core `BROADCAST` conversation, on
/// Identity's side. A channel that comes back without one is refused by the use
/// case rather than shown as working.
///
/// The description is held by the debug mock store until Identity carries the
/// field — the request already has it, so nothing here changes when it lands.
@available(iOS 16.0, *)
struct CreateChannelView: View {

    @ObservedObject var viewModel: ChannelsViewModel
    let onCreated: (Channel) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var avatar: UIImage?

    var body: some View {
        CreateFormScaffold(
            title: t(ChatTranslationKeys.CHANNELS_NEW),
            avatarPlaceholderSymbol: "dot.radiowaves.left.and.right",
            addPhotoTitle: t(ChatTranslationKeys.CHANNELS_ADD_PHOTO),
            actionTitle: t(ChatTranslationKeys.CHANNELS_CREATE),
            cancelTitle: common("cancel"),
            isSubmitting: viewModel.isWorking,
            canSubmit: !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            avatar: $avatar,
            onSubmit: submit,
            onCancel: onCancel,
            onPhotoFailed: {}
        ) {
            CreateFormField(symbol: "pencil") {
                TextField(t(ChatTranslationKeys.CHANNELS_NAME), text: $name)
            }

            CreateFormField(symbol: "text.alignleft", iconAlignment: .top) {
                TextField(
                    t(ChatTranslationKeys.CHANNELS_DESCRIPTION_HINT),
                    text: $description,
                    axis: .vertical
                )
                .lineLimit(3...6)
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

    private func submit() {
        Task {
            let draft = NewChannelDraft(
                name: name,
                description: description.isEmpty ? nil : description
            )
            if let channel = await viewModel.create(draft, avatar: avatar) {
                onCreated(channel)
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
