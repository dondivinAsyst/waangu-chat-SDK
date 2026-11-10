//
//  ProfileEditView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// The signed-in user's own profile: photo, name and bio, all editable.
///
/// Replaces the two-field alert that used to hang off the settings header and
/// threw the bio away on save.
@available(iOS 16.0, *)
struct ProfileEditView: View {
    @StateObject private var viewModel: ProfileEditViewModel
    private let translationService: (any TranslationServiceProtocol)?

    init(
        useCases: UserProfileUseCasesProtocol,
        translationService: (any TranslationServiceProtocol)? = nil
    ) {
        _viewModel = StateObject(
            wrappedValue: ProfileEditViewModel(
                useCases: useCases,
                translationService: translationService
            )
        )
        self.translationService = translationService
    }

    var body: some View {
        List {
            photoSection
            nameSection
            bioSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle(t(ChatTranslationKeys.PROFILE_TITLE))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isSaving {
                    ProgressView()
                } else {
                    Button(common("save")) {
                        Task { await viewModel.save() }
                    }
                    .bold()
                    .disabled(!viewModel.canSave)
                }
            }
        }
        .disabled(viewModel.isSaving)
        .customAlert(
            title: t(ChatTranslationKeys.PROFILE_SAVE_FAILED),
            message: viewModel.errorMessage,
            isPresented: .init(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            ),
            okTitle: common("ok"),
            animation: .smooth,
            onDismiss: { viewModel.errorMessage = nil }
        )
    }

    // MARK: - Sections

    /// The photo is the button, as in the messaging apps people already use: a
    /// camera badge on its corner says it can be changed, and the text under it
    /// says how.
    private var photoSection: some View {
        Section {
            AvatarPickerButton(
                onPicked: { viewModel.onPhotoPicked($0) },
                onLoadFailed: { viewModel.onPhotoLoadFailed() }
            ) {
                VStack(spacing: 12) {
                    avatar
                        .overlay(alignment: .bottomTrailing) { cameraBadge }

                    Text(t(ChatTranslationKeys.PROFILE_CHANGE_PHOTO))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(AppColors.primary)
                }
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .staggeredAppear(0)
        }
        .listRowBackground(Color.clear)
    }

    private static let avatarSize: CGFloat = 116

    @ViewBuilder
    private var avatar: some View {
        let size = Self.avatarSize
        Group {
            if let photo = viewModel.pendingPhoto {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size)
                    .clipShape(Circle())
            } else if !viewModel.avatarUrl.isEmpty {
                CircularProfileImageView(viewModel.avatarUrl, size: .custom(size))
            } else {
                placeholderAvatar(size: size)
            }
        }
        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
        .shadow(color: AppColors.primary.opacity(0.18), radius: 14, y: 6)
        .accessibilityHidden(true)
    }

    /// No photo yet: the person's initials on the app blue, not a grey silhouette.
    private func placeholderAvatar(size: CGFloat) -> some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [AppColors.centerGradientStart, AppColors.primary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay {
                if let initials = Self.initials(of: viewModel.name) {
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white)
                } else {
                    Image(systemName: "person.fill")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(Color.white.opacity(0.9))
                }
            }
    }

    private var cameraBadge: some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(AppColors.primary, in: Circle())
            .overlay(Circle().strokeBorder(AppColors.background, lineWidth: 3))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }

    /// Up to two letters: the first of the first and last words.
    static func initials(of name: String) -> String? {
        let words = name.split(whereSeparator: { $0.isWhitespace })
        guard let first = words.first?.first else { return nil }
        let last = words.count > 1 ? words.last?.first : nil
        return String([first, last].compactMap { $0 }).uppercased()
    }

    private var nameSection: some View {
        Section {
            HStack(spacing: 12) {
                rowIcon("person.fill")
                TextField(t(ChatTranslationKeys.SETTINGS_USERNAME), text: $viewModel.name)
                    .textInputAutocapitalization(.words)
            }
        } header: {
            Text(t(ChatTranslationKeys.SETTINGS_USERNAME))
        } footer: {
            Text(t(ChatTranslationKeys.PROFILE_NAME_FOOTER))
        }
        .staggeredAppear(1)
    }

    /// The counter only shows once it matters: the last 20 characters.
    private var bioSection: some View {
        let count = viewModel.bio.count
        let limit = ProfileEditViewModel.bioCharacterLimit
        return Section {
            HStack(alignment: .center, spacing: 12) {
                rowIcon("text.quote")
                TextField(
                    t(ChatTranslationKeys.SETTINGS_BIO),
                    text: $viewModel.bio,
                    axis: .vertical
                )
                .lineLimit(1...4)
                .onChange(of: viewModel.bio) { newValue in
                    viewModel.onBioChanged(newValue)
                }
            }
        } header: {
            Text(t(ChatTranslationKeys.SETTINGS_BIO))
        } footer: {
            if count >= limit - 20 {
                Text("\(count)/\(limit)")
                    .monospacedDigit()
                    .foregroundStyle(count >= limit ? AppColors.primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
        .staggeredAppear(2)
    }

    private func rowIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(AppColors.primary)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    // MARK: - Translation

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}
