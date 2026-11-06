//
//  CreateFormScaffold.swift
//  FeatureChat
//
//  The shape both create forms share: cancel, title, avatar, fields, and one
//  primary action pinned to the bottom.
//

import SwiftUI
import WaanguSharedUI
import UIKit

/// A create sheet: `Cancel` and a title across the top, an avatar the user can
/// set, the caller's fields, and a single full-width action at the bottom that
/// stays disabled until the form is worth submitting.
///
/// Pinned rather than in the toolbar because the action is the point of the
/// screen — and because a toolbar button sits behind the keyboard's thumb reach
/// on a form that is all text fields.
@available(iOS 16.0, *)
struct CreateFormScaffold<Fields: View>: View {

    let title: String
    let avatarPlaceholderSymbol: String
    let addPhotoTitle: String
    let actionTitle: String
    let cancelTitle: String
    let isSubmitting: Bool
    let canSubmit: Bool
    @Binding var avatar: UIImage?
    let onSubmit: () -> Void
    let onCancel: () -> Void
    let onPhotoFailed: () -> Void
    @ViewBuilder let fields: () -> Fields

    var body: some View {
        VStack(spacing: 0) {
            header()

            ScrollView {
                VStack(spacing: 20) {
                    avatarPicker()
                    fields()
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 24)
            }

            submitButton()
        }
        .background(AppColors.background)
    }

    // MARK: - Pieces

    @ViewBuilder
    private func header() -> some View {
        ZStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)

            HStack {
                Button(cancelTitle, action: onCancel)
                    .font(.body)
                    .foregroundStyle(AppColors.primary)
                Spacer()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    @ViewBuilder
    private func avatarPicker() -> some View {
        VStack(spacing: 8) {
            AvatarPickerButton(
                onPicked: { avatar = $0 },
                onLoadFailed: onPhotoFailed
            ) {
                avatarLabel()
            }

            Text(addPhotoTitle)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColors.primary)
        }
    }

    @ViewBuilder
    private func avatarLabel() -> some View {
        Group {
            if let avatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: avatarPlaceholderSymbol)
                    .font(.system(size: 40))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .frame(width: 108, height: 108)
        .background(AppColors.primary.opacity(0.12))
        .clipShape(Circle())
    }

    @ViewBuilder
    private func submitButton() -> some View {
        Button(action: onSubmit) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(AppColors.white)
                } else {
                    Text(actionTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(canSubmit ? AppColors.primary : AppColors.primary.opacity(0.25))
            .foregroundStyle(AppColors.white)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
    }
}

/// A field box in a create form: the rounded grey well the app already uses for
/// text entry.
@available(iOS 16.0, *)
struct CreateFormField<Content: View>: View {

    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
    }
}
