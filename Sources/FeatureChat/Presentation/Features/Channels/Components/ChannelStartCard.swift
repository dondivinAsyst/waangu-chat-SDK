//
//  ChannelStartCard.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// What a channel shows its owner before the first post.
///
/// Not an empty state — an empty state says "nothing here". This says what to
/// do next, and stops appearing the moment there is a post, because by then the
/// channel has started.
@available(iOS 16.0, *)
struct ChannelStartCard: View {

    let channel: Channel
    let translationService: (any TranslationServiceProtocol)?
    let onAddPhoto: () -> Void
    let onShareToStatus: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            systemNotice(t(ChatTranslationKeys.CHANNELS_SYSTEM_PUBLIC_NOTICE), symbol: "dot.radiowaves.left.and.right")
            systemNotice(t(ChatTranslationKeys.CHANNELS_SYSTEM_CREATED, args: [channel.name]), symbol: nil)

            card()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
    }

    /// The grey pill the room uses for anything the system says rather than
    /// anyone posting.
    @ViewBuilder
    private func systemNotice(_ text: String, symbol: String?) -> some View {
        HStack(alignment: .top, spacing: 6) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.caption)
            }

            Text(text)
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(AppColors.cardBackground.opacity(0.92))
        )
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func card() -> some View {
        VStack(spacing: 14) {
            Button(action: onAddPhoto) {
                VStack(spacing: 8) {
                    CircularProfileImageView(channel.image, size: .large)

                    Text(t(ChatTranslationKeys.CHANNELS_ADD_PHOTO))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColors.primary)
                }
            }
            .buttonStyle(.plain)

            Text(t(ChatTranslationKeys.CHANNELS_START_GROWING, args: [channel.name]))
                .font(.headline)
                .foregroundStyle(AppColors.textPrimary)
                .multilineTextAlignment(.center)

            // This card's actions are the ones that grow a channel — publishing
            // it to your status, and inviting admins. Plain "share" is not one
            // of them: it already sits in the room's menu and in channel info,
            // and putting it here took the place of an action that belongs.
            //
            // "Invite admins" and "Add description" are missing rather than
            // faked: there is no channel-admin endpoint, and Identity's channel
            // record has no description field. Both are a few lines here the day
            // the backend has them.

            actionRow(
                title: t(ChatTranslationKeys.CHANNELS_SHARE_TO_STATUS),
                systemImage: "circle.dashed.inset.filled",
                action: onShareToStatus
            )
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(AppColors.cardBackground)
        )
    }

    /// A full-width row, the way the reference card stacks its actions.
    @ViewBuilder
    private func actionRow(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppColors.primary.opacity(0.12))
                )
                .foregroundStyle(AppColors.primary)
        }
        .buttonStyle(.plain)
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

}
