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
    @FocusState private var fieldFocused: Bool

    private var trimmedCode: String {
        inviteCode.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ChatHeroBand(symbol: "key", height: 160, cornerRadius: 26)

                VStack(spacing: 8) {
                    // The full title lives here, where it can wrap: in the
                    // navigation bar it was cut to "Join with an inv…".
                    Text(t(ChatTranslationKeys.COMMUNITIES_JOIN_WITH_CODE))
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(t(ChatTranslationKeys.COMMUNITIES_JOIN_CODE_HINT))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 12)
                .padding(.top, 22)
                .staggeredAppear(1)

                codeField()
                    .padding(.top, 24)
                    .staggeredAppear(2)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(Color(.systemGroupedBackground))
        .safeAreaInset(edge: .bottom) { joinButton() }
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
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        // Cancel is the way out; a back arrow next to it said the same thing twice.
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(t(ChatTranslationKeys.CHAT_CANCEL)) { onCancel() }
            }
        }
    }

    // MARK: - Pieces

    private func codeField() -> some View {
        HStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColors.primary)
                .accessibilityHidden(true)

            TextField(t(ChatTranslationKeys.COMMUNITIES_INVITE_CODE), text: $inviteCode)
                .font(.title3.weight(.semibold))
                // The code in a fixed-width face, so 0/O and 1/I stay apart; the
                // placeholder in the normal one.
                .fontDesign(inviteCode.isEmpty ? .default : .monospaced)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($fieldFocused)
                .submitLabel(.join)
                .onSubmit { if !trimmedCode.isEmpty { submit() } }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.primary.opacity(fieldFocused ? 0.6 : 0.12), lineWidth: 1.5)
        )
        .animation(.easeOut(duration: 0.2), value: fieldFocused)
        .contentShape(Rectangle())
        .onTapGesture { fieldFocused = true }
    }

    /// At the bottom, full width, where a thumb reaches it: the one thing to do
    /// on this screen. It lights up once there is a code to send.
    private func joinButton() -> some View {
        Button(action: submit) {
            ZStack {
                if viewModel.isWorking {
                    ProgressView().tint(Color.white)
                } else {
                    Text(t(ChatTranslationKeys.COMMUNITIES_JOIN))
                        .font(.headline)
                        .foregroundStyle(trimmedCode.isEmpty ? Color(.secondaryLabel) : Color.white)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(trimmedCode.isEmpty ? Color(.tertiarySystemFill) : AppColors.primary, in: Capsule())
            .shadow(color: AppColors.primary.opacity(trimmedCode.isEmpty ? 0 : 0.30), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .disabled(trimmedCode.isEmpty || viewModel.isWorking)
        .animation(.easeOut(duration: 0.2), value: trimmedCode.isEmpty)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .background(Color(.systemGroupedBackground).opacity(0.95))
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
