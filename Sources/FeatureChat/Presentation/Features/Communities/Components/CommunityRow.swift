//
//  CommunityRow.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

/// One community in the tab's list.
@available(iOS 16.0, *)
struct CommunityRow: View {

    let community: Community
    let translationService: (any TranslationServiceProtocol)?

    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(community.image, size: .small)

            VStack(alignment: .leading, spacing: 4) {
                Text(community.name)
                    .font(.system(size: 17, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    if community.isPrivate {
                        Image(systemName: "lock.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }

                    Text(t(ChatTranslationKeys.COMMUNITIES_MEMBER_COUNT, args: ["\(community.memberCount)"]))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .contentShape(Rectangle())
    }

    private func t(_ key: String, args: [String] = []) -> String {
        translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }
}
