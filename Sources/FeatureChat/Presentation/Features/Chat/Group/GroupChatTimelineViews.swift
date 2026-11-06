import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

struct GroupChatIntroContent: Equatable {
    static let rowId = "group-intro-timeline"
    
    let groupName: String
    let description: String?
    let memberCount: Int
    let avatarUrl: String?
    let createdByCurrentUser: Bool
    let canAddMembers: Bool
    let canShowInviteLink: Bool
}

struct ChatEncryptionNoticeView: View {
    let translationService: (any TranslationServiceProtocol)?
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.yellow)
                Text(t(ChatTranslationKeys.GROUP_INFO_ENCRYPTION_SUBTITLE))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func t(_ key: String) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE).value ?? key
    }
}

struct GroupChatTimelineIntroCard: View {
    let content: GroupChatIntroContent
    let translationService: (any TranslationServiceProtocol)?
    var onAddMembers: (() -> Void)?
    var onInviteLink: (() -> Void)?
    
    private var headline: String {
        content.createdByCurrentUser
            ? t(ChatTranslationKeys.GROUP_INTRO_CREATED_YOU)
            : t(ChatTranslationKeys.GROUP_INTRO_CREATED_OTHER, args: [content.groupName])
    }
    
    var body: some View {
        VStack(spacing: 14) {
            groupAvatar
            
            Text(headline)
                .font(.headline.weight(.semibold))
                .multilineTextAlignment(.center)
            
            Text(t(ChatTranslationKeys.GROUP_INTRO_MEMBERS, args: ["\(content.memberCount)"]))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            
            if let description = content.description, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else {
                Text(t(ChatTranslationKeys.GROUP_INTRO_ADD_DESCRIPTION))
                    .font(.subheadline)
                    .foregroundStyle(AppColors.primary.opacity(0.9))
            }
            
            if content.canAddMembers || content.canShowInviteLink {
                VStack(spacing: 10) {
                    if content.canAddMembers {
                        introActionButton(
                            title: t(ChatTranslationKeys.GROUP_INTRO_ADD_MEMBERS),
                            systemImage: "person.badge.plus",
                            action: { onAddMembers?() }
                        )
                    }
                    if content.canShowInviteLink {
                        introActionButton(
                            title: t(ChatTranslationKeys.GROUP_INFO_INVITE_VIA_LINK),
                            systemImage: "link",
                            action: { onInviteLink?() }
                        )
                    }
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 24)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
    
    @ViewBuilder
    private var groupAvatar: some View {
        if let avatarUrl = content.avatarUrl, !avatarUrl.isEmpty {
            CircularProfileImageView(avatarUrl, size: .large)
                .frame(width: 72, height: 72)
        } else {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColors.primary.opacity(0.85), AppColors.primary.opacity(0.55)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 72, height: 72)
                .overlay {
                    Image(systemName: "person.2.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
        }
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
    
    private func introActionButton(
        title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(AppColors.primary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .stroke(AppColors.primary.opacity(0.35), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
