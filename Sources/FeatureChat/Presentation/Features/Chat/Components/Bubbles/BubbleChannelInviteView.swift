//
//  BubbleChannelInviteView.swift
//  FeatureChat
//
//  Created by Kiro on 9/30/26.
//  Displays channel invitation cards in chat messages
//

import SwiftUI
import WaanguSharedUI
import WaanguCoreKit

@available(iOS 16.0, *)
struct BubbleChannelInviteView: View {
    let message: MessageDataItem
    let isSelectionMode: Bool
    let onJoin: (String) -> Void // Called with channelId when user taps Join
    
    /// Held, not observed: the room view model is a service locator here
    let chatVM: ChatRoomViewModel
    
    @Environment(\.colorScheme) private var colorScheme
    @State private var isJoining: Bool = false
    
    var body: some View {
        if let inviteContent = message.message.channelInvite {
            HStack {
                if message.direction == .sent {
                    Spacer()
                }
                
                VStack(alignment: .leading, spacing: 0) {
                    // Forwarded indicator inside the bubble
                    forwardedIndicator(for: message, forwardedLabel: chatVM.translationService?.resolve(key: ChatTranslationKeys.FORWARDED, module: ChatTranslationKeys.MODULE).value ?? "Forwarded")
                    
                    VStack(spacing: 0) {
                        // Channel info section
                        HStack(alignment: .top, spacing: 12) {
                            // Channel avatar
                            channelAvatar(inviteContent)
                            
                            // Channel details
                            VStack(alignment: .leading, spacing: 6) {
                                // Channel name with verified badge
                                HStack(spacing: 4) {
                                    Text(inviteContent.channelName)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(ChatBubbleStyle.foreground(for: colorScheme))
                                        .lineLimit(2)
                                    
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 14))
                                        .foregroundColor(.blue)
                                }
                                
                                // Follower count
                                HStack(spacing: 4) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 12))
                                        .foregroundColor(.secondary)
                                    
                                    Text(formatFollowerCount(inviteContent.followerCount))
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                }
                                
                                // Channel description (if available)
                                if let description = inviteContent.channelDescription, !description.isEmpty {
                                    Text(description)
                                        .font(.system(size: 14))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .padding(.top, 4)
                                }
                            }
                            .padding(.trailing, 60) // Space for metadata overlay
                            .padding(.bottom, 2)
                            .overlay(alignment: .bottomTrailing) {
                                BubbleMetaOverlay(
                                    message: message,
                                    style: .bubble(colorScheme: colorScheme),
                                    translationService: chatVM.translationService
                                )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        
                        // Divider
                        Divider()
                            .background(Color.secondary.opacity(0.2))
                        
                        // Join button section
                        joinButtonSection(inviteContent)
                    }
                }
                .background(ChatBubbleStyle.mutedOverlay(for: colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .padding(8)
                .background(message.backgroundColor)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .applyStrokeOnBubbleView()
                .applyTailView(message.direction)
                .shadow(color: Color(.systemGray3).opacity(0.1), radius: 5, x: 0, y: 20)
                
                if message.direction == .received {
                    Spacer()
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.alignment)
            .padding(.leading, message.direction == .received ? 10 : 60)
            .padding(.trailing, message.direction == .received ? 60 : 10)
            .id(message.id)
        }
    }
    
    // MARK: - Channel Avatar
    
    @ViewBuilder
    private func channelAvatar(_ invite: ChannelInviteContent) -> some View {
        if let imageUrl = invite.channelImage, !imageUrl.isEmpty {
            AsyncImage(url: URL(string: imageUrl)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 54, height: 54)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                case .failure, .empty:
                    channelPlaceholder(invite.channelName)
                @unknown default:
                    channelPlaceholder(invite.channelName)
                }
            }
        } else {
            channelPlaceholder(invite.channelName)
        }
    }
    
    private func channelPlaceholder(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(AppColors.primary.opacity(0.15))
                .frame(width: 54, height: 54)
            
            Image(systemName: "megaphone.fill")
                .font(.system(size: 24))
                .foregroundColor(AppColors.primary)
        }
    }
    
    // MARK: - Join Button Section
    
    private func joinButtonSection(_ invite: ChannelInviteContent) -> some View {
        HStack(spacing: 0) {
            Button {
                guard !isSelectionMode, !isJoining else { return }
                isJoining = true
                onJoin(invite.channelId)
                // Reset after a delay to allow UI feedback
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    isJoining = false
                }
            } label: {
                HStack(spacing: 6) {
                    if isJoining {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                        
                        Text(t("channel.invite.join_button"))
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
                .foregroundColor(isSelectionMode ? .secondary : AppColors.primary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .disabled(isSelectionMode || isJoining)
            .allowsHitTesting(!isSelectionMode && !isJoining)
        }
        .overlay(alignment: .top) {
            // Top divider is already rendered above this section
        }
    }
    
    // MARK: - Forwarded Indicator
    
    @ViewBuilder
    private func forwardedIndicator(for message: MessageDataItem, forwardedLabel: String) -> some View {
        if message.forwarded {
            HStack(spacing: 4) {
                Image(systemName: "arrowshape.turn.up.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text(forwardedLabel)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .padding(.bottom, 2)
        }
    }
    
    // MARK: - Helpers
    
    private func formatFollowerCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM %@", Double(count) / 1_000_000.0, t("channel.invite.followers"))
        } else if count >= 1_000 {
            return String(format: "%.1fK %@", Double(count) / 1_000.0, t("channel.invite.followers"))
        } else {
            return "\(count) \(t(count == 1 ? "channel.invite.follower" : "channel.invite.followers"))"
        }
    }
    
    // MARK: - Translation Helper
    
    private func t(_ key: String, args: [String] = []) -> String {
        chatVM.translationService?.resolve(
            key: key,
            module: ChatTranslationKeys.MODULE,
            args: args
        ).value ?? key
    }
}

// MARK: - Preview

#if DEBUG
// Preview commented out - requires complex MessageDataItem setup
// @available(iOS 16.0, *)
// struct BubbleChannelInviteView_Previews: PreviewProvider {
//    static var previews: some View {
//        Group {
//            // Received invite
//            previewBubble(direction: .received)
//                .previewDisplayName("Received Invite")
//            
//            // Sent invite
//            previewBubble(direction: .sent)
//                .previewDisplayName("Sent Invite")
//            
//            // Dark mode
//            previewBubble(direction: .received)
//                .preferredColorScheme(.dark)
//                .previewDisplayName("Dark Mode")
//        }
//        .padding()
//        .background(Color(.systemGroupedBackground))
//    }
//    
//    // Preview disabled until proper mocking is set up
//    // static func previewBubble(direction: MessageDirection) -> some View {
//    //     // Preview code removed - needs proper MessageDataItem initialization
//    // }
// }

#endif

