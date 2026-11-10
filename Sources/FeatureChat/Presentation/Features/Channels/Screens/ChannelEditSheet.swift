//
//  ChannelEditSheet.swift
//  FeatureChat
//

import SwiftUI
import WaanguCoreKit
import UIKit

/// Renaming a channel or changing its picture — `PUT /channels`.
///
/// Owner only, and reached from channel info. The same scaffold as creating one,
/// because it is the same two fields.
@available(iOS 16.0, *)
struct ChannelEditSheet: View {

    let channel: Channel
    @ObservedObject var viewModel: ChannelRoomViewModel
    let onDismiss: () -> Void

    @State private var name: String
    @State private var description: String
    @State private var avatar: UIImage?

    init(channel: Channel, viewModel: ChannelRoomViewModel, onDismiss: @escaping () -> Void) {
        self.channel = channel
        self.viewModel = viewModel
        self.onDismiss = onDismiss
        self._name = State(initialValue: channel.name)
        self._description = State(initialValue: channel.description ?? "")
    }

    var body: some View {
        CreateFormScaffold(
            title: t(ChatTranslationKeys.CHANNELS_EDIT_TITLE),
            avatarPlaceholderSymbol: "dot.radiowaves.left.and.right",
            addPhotoTitle: t(ChatTranslationKeys.CHANNELS_ADD_PHOTO),
            actionTitle: t(ChatTranslationKeys.CHANNELS_SAVE),
            cancelTitle: common("cancel"),
            isSubmitting: viewModel.isSending,
            canSubmit: hasChanges,
            avatar: $avatar,
            onSubmit: submit,
            onCancel: onDismiss,
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
    }

    /// Saving an unchanged channel would be a request that says nothing.
    private var hasChanges: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return trimmed != channel.name
            || description != (channel.description ?? "")
            || avatar != nil
    }

    private func submit() {
        Task {
            await viewModel.updateChannel(
                name: name,
                description: description.isEmpty ? nil : description,
                avatar: avatar
            )
            onDismiss()
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        viewModel.translationService?
            .resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
