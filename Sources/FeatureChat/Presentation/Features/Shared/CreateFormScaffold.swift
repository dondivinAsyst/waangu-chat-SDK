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
                VStack(spacing: 14) {
                    avatarPicker()
                        .padding(.bottom, 10)
                        .staggeredAppear(0)

                    fields()
                        .staggeredAppear(1)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)

            submitButton()
        }
        .background(alignment: .top) { wash() }
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

    /// A soft wash of the app blue behind the top of the form, fading into the
    /// page — the same light the intro sheet before it ends on.
    private func wash() -> some View {
        LinearGradient(
            colors: [AppColors.primary.opacity(0.12), AppColors.primary.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 260)
        .ignoresSafeArea(edges: .top)
        .allowsHitTesting(false)
    }

    /// The avatar is the button: the whole disc and the text under it open the
    /// picker, and a camera badge on its corner says so.
    @ViewBuilder
    private func avatarPicker() -> some View {
        AvatarPickerButton(
            onPicked: { avatar = $0 },
            onLoadFailed: onPhotoFailed
        ) {
            VStack(spacing: 10) {
                avatarLabel()
                    .overlay(alignment: .bottomTrailing) { cameraBadge() }

                Text(addPhotoTitle)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColors.primary)
            }
        }
        .buttonStyle(.plain)
    }

    private static var avatarSize: CGFloat { 112 }

    @ViewBuilder
    private func avatarLabel() -> some View {
        let size = Self.avatarSize
        Group {
            if let avatar {
                Image(uiImage: avatar)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: avatarPlaceholderSymbol)
                    .font(.system(size: size * 0.34, weight: .semibold))
                    .symbolVariant(.fill)
                    .foregroundStyle(Color.white)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        LinearGradient(
                            colors: [AppColors.centerGradientStart, AppColors.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 3))
        .shadow(color: AppColors.primary.opacity(0.22), radius: 14, y: 6)
        .accessibilityHidden(true)
    }

    private func cameraBadge() -> some View {
        Image(systemName: "camera.fill")
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: 36, height: 36)
            .background(AppColors.primary, in: Circle())
            .overlay(Circle().strokeBorder(AppColors.background, lineWidth: 3))
            .offset(x: 2, y: 2)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private func submitButton() -> some View {
        Button(action: onSubmit) {
            Group {
                if isSubmitting {
                    ProgressView()
                        .tint(Color.white)
                } else {
                    Text(actionTitle)
                        .font(.headline)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            // White on blue when it can be sent; the system's grey fill and
            // secondary text while it cannot, which stay readable in light and
            // dark. Before, `AppColors.white` (dark in dark mode) sat on a 25 %
            // blue, and "Create" could not be read in either mode.
            .background(canSubmit ? AppColors.primary : Color(.tertiarySystemFill))
            .foregroundStyle(canSubmit ? Color.white : Color(.secondaryLabel))
            .clipShape(Capsule())
            .shadow(color: AppColors.primary.opacity(canSubmit ? 0.30 : 0), radius: 12, y: 6)
            .animation(.easeOut(duration: 0.2), value: canSubmit)
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit || isSubmitting)
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 20)
    }
}

/// A field box in a create form: a rounded well with an optional leading icon in
/// the app blue, so each field says what it is at a glance.
@available(iOS 16.0, *)
struct CreateFormField<Content: View>: View {

    var symbol: String? = nil
    /// `.top` for a multi-line field, so the icon sits beside its first line.
    var iconAlignment: VerticalAlignment = .center
    @ViewBuilder let content: () -> Content

    var body: some View {
        HStack(alignment: iconAlignment, spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColors.primary)
                    .frame(width: 22, height: 22)
                    .accessibilityHidden(true)
            }
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AppColors.primary.opacity(0.08), lineWidth: 1)
        )
    }
}
