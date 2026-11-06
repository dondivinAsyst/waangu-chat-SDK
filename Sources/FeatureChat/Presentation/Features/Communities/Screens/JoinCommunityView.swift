//
//  JoinCommunityView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// Joining a private community. The invite code is the only way in — a public
/// community is joined from its row in the directory.
@available(iOS 16.0, *)
struct JoinCommunityView: View {

    @ObservedObject var viewModel: CommunitiesViewModel
    let onJoined: () -> Void
    let onCancel: () -> Void

    @State private var inviteCode = ""

    var body: some View {
        Form {
            Section {
                TextField(t(ChatTranslationKeys.COMMUNITIES_INVITE_CODE), text: $inviteCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            } footer: {
                Text(t(ChatTranslationKeys.COMMUNITIES_PRIVATE_DESC))
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
        .navigationTitle(t(ChatTranslationKeys.COMMUNITIES_JOIN_WITH_CODE))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t(ChatTranslationKeys.CHAT_CANCEL)) { onCancel() }
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isWorking {
                    ProgressView()
                } else {
                    Button(t(ChatTranslationKeys.COMMUNITIES_JOIN)) { submit() }
                        .disabled(inviteCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func submit() {
        Task {
            if await viewModel.join(inviteCode: inviteCode) {
                onJoined()
            }
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
