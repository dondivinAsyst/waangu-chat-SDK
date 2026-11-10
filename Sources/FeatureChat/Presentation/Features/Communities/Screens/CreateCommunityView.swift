//
//  CreateCommunityView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit
import UIKit

/// Creates a community and, optionally, the groups it starts with.
///
/// The announcements group is never listed here: Identity creates it with the
/// community and refuses to detach it afterwards.
@available(iOS 16.0, *)
struct CreateCommunityView: View {

    @ObservedObject var viewModel: CommunitiesViewModel
    let onCreated: (Community) -> Void
    let onCancel: () -> Void

    @State private var name = ""
    @State private var description = ""
    @State private var isPrivate = false
    @State private var avatar: UIImage?

    var body: some View {
        CreateFormScaffold(
            title: t(ChatTranslationKeys.COMMUNITIES_CREATE_TITLE),
            avatarPlaceholderSymbol: "person.3.fill",
            addPhotoTitle: t(ChatTranslationKeys.COMMUNITIES_ADD_PHOTO),
            actionTitle: t(ChatTranslationKeys.COMMUNITIES_CREATE),
            cancelTitle: common("cancel"),
            isSubmitting: viewModel.isWorking,
            canSubmit: canSubmit,
            avatar: $avatar,
            onSubmit: submit,
            onCancel: onCancel,
            onPhotoFailed: {}
        ) {
            fields()
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

    // MARK: - Fields

    @ViewBuilder
    private func fields() -> some View {
        CreateFormField(symbol: "pencil") {
            TextField(t(ChatTranslationKeys.COMMUNITIES_NAME), text: $name)
                .textInputAutocapitalization(.words)
        }

        CreateFormField(symbol: "text.alignleft", iconAlignment: .top) {
            TextField(
                t(ChatTranslationKeys.COMMUNITIES_DESCRIPTION_HINT),
                text: $description,
                axis: .vertical
            )
            .lineLimit(3...6)
        }

        CreateFormField(symbol: "lock.fill") {
            Toggle(t(ChatTranslationKeys.COMMUNITIES_PRIVATE), isOn: $isPrivate)
                .tint(AppColors.primary)
        }
    }


    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        // No groups here. A community is created empty and its groups are added
        // afterwards, from the community itself — where creating one goes
        // through the app's real group flow, with members, a photo and settings,
        // rather than a bare name in a text field.
        let draft = NewCommunityDraft(
            name: name,
            description: description.isEmpty ? nil : description,
            isPrivate: isPrivate
        )

        Task {
            if let community = await viewModel.create(draft, avatar: avatar) {
                onCreated(community)
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
