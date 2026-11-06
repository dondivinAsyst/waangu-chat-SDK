//
//  FollowedChannelRow.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// A followed channel in the Updates tab: avatar, name, last message, time and
/// unread count — the same shape as a chats-list row, because that is what it
/// is. The directory row with a Follow button is `ChannelListRow`.
@available(iOS 16.0, *)
struct FollowedChannelRow: View {

    let item: FollowedChannel
    let translationService: (any TranslationServiceProtocol)?

    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(item.channel.image, size: .small)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.channel.name)
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColors.textPrimary)
                        .lineLimit(1)

                    if item.channel.isOwned(by: CurrentSessionInfo.shared.currentUid) {
                        // The one channel in this list you can actually post to.
                        Text(t(ChatTranslationKeys.CHANNELS_YOURS))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppColors.primary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 4) {
                    if let icon = previewIcon {
                        Image(systemName: icon)
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Text(previewText)
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 6) {
                Text(item.preview.time)
                    .font(.system(size: 13))
                    .foregroundStyle(item.preview.unreadCount > 0 ? AppColors.primary : .secondary)

                if item.preview.unreadCount > 0 {
                    Text("\(item.preview.unreadCount)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColors.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColors.primary)
                        .clipShape(Capsule())
                }
            }
        }
        .opacity(item.channel.isOpenable ? 1 : 0.6)
        .contentShape(Rectangle())
    }

    /// Empty preview means the conversation has not synced yet — say so rather
    /// than leaving the row blank.
    private var previewText: String {
        if !item.channel.isOpenable {
            return t(ChatTranslationKeys.CHANNELS_NOT_READY)
        }
        return item.preview.text.isEmpty
            ? t(ChatTranslationKeys.CHANNELS_NO_POSTS_YET)
            : item.preview.text
    }

    /// The little glyph before a non-text preview, as the chats list does it.
    private var previewIcon: String? {
        switch item.preview.messageType {
        case .IMAGE:    return "camera.fill"
        case .VIDEO, .VIDEO_NOTE:    return "video.fill"
        case .AUDIO:    return "mic.fill"
        case .DOCUMENT: return "doc.fill"
        default:        return nil
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
