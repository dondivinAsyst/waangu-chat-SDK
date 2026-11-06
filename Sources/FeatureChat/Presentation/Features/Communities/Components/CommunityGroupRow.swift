//
//  CommunityGroupRow.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// A group inside a community — announcements or a plain sub-group.
///
/// A group whose Core conversation does not exist yet is shown greyed out with
/// a reason rather than hidden: it exists in Identity, and hiding it would make
/// a failed provisioning look like a missing group.
@available(iOS 16.0, *)
struct CommunityGroupRow: View {

    let group: CommunityGroupSummary
    let canWrite: Bool
    /// What was last said in this group. Nil when the conversation has not
    /// reached the inbox yet.
    var preview: ConversationPreview? = nil
    let translationService: (any TranslationServiceProtocol)?

    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(group.image, size: .xSmall)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(group.isAnnouncementGroup
                         ? t(ChatTranslationKeys.COMMUNITIES_ANNOUNCEMENTS)
                         : group.name)
                        .font(.system(size: 16, weight: .medium))
                        .lineLimit(1)

                    if group.isAnnouncementGroup {
                        Image(systemName: "megaphone.fill")
                            .font(.caption2)
                            .foregroundStyle(AppColors.primary)
                    }
                }

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if !group.isOpenable {
                Image(systemName: "clock.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else if let preview, !preview.time.isEmpty {
                VStack(alignment: .trailing, spacing: 6) {
                    Text(preview.time)
                        .font(.caption)
                        .foregroundStyle(preview.unreadCount > 0 ? AppColors.primary : .secondary)

                    if preview.unreadCount > 0 {
                        Text("\(preview.unreadCount)")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColors.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.primary)
                            .clipShape(Capsule())
                    }
                }
            }
        }
        .opacity(group.isOpenable ? 1 : 0.5)
        .contentShape(Rectangle())
    }

    /// What the row says under the name: the reason it cannot be opened, then
    /// the last message, then — for a group with nothing in it yet — who is in
    /// it.
    private var subtitle: String {
        if !group.isOpenable {
            return t(ChatTranslationKeys.COMMUNITIES_CONVERSATION_PENDING)
        }
        if let preview, !preview.text.isEmpty {
            return preview.text
        }
        if group.isAnnouncementGroup && !canWrite {
            return t(ChatTranslationKeys.COMMUNITIES_ADMIN_ONLY_POST)
        }
        return t(ChatTranslationKeys.COMMUNITIES_MEMBER_COUNT, args: ["\(group.memberCount)"])
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
