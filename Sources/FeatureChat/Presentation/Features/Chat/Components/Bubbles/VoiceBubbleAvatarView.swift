//
//  VoiceBubbleAvatarView.swift
//  FeatureChat
//

import SwiftUI
import WaanguSharedUI

struct VoiceBubbleAvatarView: View {
    let imageUrl: String?
    let fallbackName: String
    let isOutgoing: Bool

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            avatarContent
            micBadge
        }
        .frame(width: 36, height: 36)
    }

    @ViewBuilder
    private var avatarContent: some View {
        if let imageUrl, !imageUrl.isEmpty {
            CircularProfileImageView(imageUrl, size: .custom(34))
        } else {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 34, height: 34)
                .overlay {
                    Text(String(fallbackName.prefix(1)).uppercased())
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                }
        }
    }

    private var micBadge: some View {
        Image(systemName: "mic.fill")
            .font(.system(size: 7, weight: .bold))
            .foregroundStyle(.white)
            .padding(4)
            .background(isOutgoing ? AppColors.primary : Color(.systemGray))
            .clipShape(Circle())
            .offset(x: 3, y: 3)
    }
}
