//
//  ReplyView.swift
//  Pods
//
//  Created by Don divin on 2/11/26.
//


import SwiftUI
import WaanguCoreKit

// MARK: - Reply View
struct ReplyViewSwiftUI: View {
    // MARK: - Properties
    @ObservedObject var chatRoomVM: ChatRoomViewModel
    @ObservedObject var uploadVM: FileUploadViewModel

    // MARK: - State
    @State private var thumbnailImage: UIImage?

    init(chatRoomVM: ChatRoomViewModel, uploadVM: FileUploadViewModel, onClose: (() -> Void)? = nil) {
        self.chatRoomVM = chatRoomVM
        self.uploadVM = uploadVM
    }
    
    // MARK: - Body
    var body: some View {
        if let replyMessage = chatRoomVM.replyMessage {
         

            Group {
                if #available(iOS 16.0, *) {
                    ZStack {
                        // Glass background
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                            )
                    }
                    .frame(maxHeight: 60)
                    .overlay(alignment: .leading) {
                        switch replyMessage {
                        case .mediaGroup(_, let media):
                            let isYou = media.first?.senderId == CurrentSessionInfo.shared.currentUid
                            imagesContent(isYou: isYou, media: media)

                        case .message(let msg):
                            let isYou = msg.senderId == CurrentSessionInfo.shared.currentUid
                            contentView(isYou: isYou, replyMessage: msg)
                            
                        case .checkpoint, .encryptionBanner, .groupIntro:
                            EmptyView()
                        }
                    }

                } else if #available(iOS 15.0, *) {
                    // iOS 15 fallback material
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.regularMaterial)
                        .frame(maxHeight: 60)
                        .overlay(alignment: .leading) {
                            switch replyMessage {
                            case .mediaGroup(_, let media):
                                let isYou = media.first?.senderId == CurrentSessionInfo.shared.currentUid
                                imagesContent(isYou: isYou, media: media)

                            case .message(let msg):
                                let isYou = msg.senderId == CurrentSessionInfo.shared.currentUid
                                contentView(isYou: isYou, replyMessage: msg)
                                
                            case .checkpoint, .encryptionBanner, .groupIntro:
                                EmptyView()
                            }
                        }

                } else {
                    // iOS 14 fallback (solid color)
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                        .frame(maxHeight: 60)
                        .overlay(alignment: .leading) {
                            switch replyMessage {
                            case .mediaGroup(_, let media):
                                let isYou = media.first?.senderId == CurrentSessionInfo.shared.currentUid
                                imagesContent(isYou: isYou, media: media)

                            case .message(let msg):
                                let isYou = msg.senderId == CurrentSessionInfo.shared.currentUid
                                contentView(isYou: isYou, replyMessage: msg)
                                
                            case .checkpoint, .encryptionBanner, .groupIntro:
                                EmptyView()
                            }
                        }
                }
            }
            .clipped()

        }
    }
    
    @ViewBuilder
    private func imagesContent(isYou: Bool,media: [MessageDataItem]) -> some View {
        HStack(spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(isYou ? Color(red: 0.0, green: 0.53, blue: 0.73) : Color(red: 0.0, green: 0.73, blue: 0.53))
                .frame(width: 6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Sender label
                Text(isYou ? common("you") : media.first?.senderName ?? "")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isYou ? Color(red: 0.0, green: 0.53, blue: 0.73) : Color(red: 0.0, green: 0.73, blue: 0.53))
                    .lineLimit(1)
                
                // Message content
                Text(t(ChatTranslationKeys.REPLY_MEDIA_COUNT, args: ["\(media.count)"]))
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            
            Spacer(minLength: 0)
            Button(action: {
                withAnimation {
                    chatRoomVM.replyMessage = nil
                }
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.gray)
                    .frame(width: 24, height: 24)
            }
            
         
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    // MARK: - Content View
    @ViewBuilder
    private func contentView(isYou: Bool, replyMessage: MessageDataItem) -> some View {
        HStack(spacing: 0) {
            // Left accent bar
            Rectangle()
                .fill(isYou ? Color(red: 0.0, green: 0.53, blue: 0.73) : Color(red: 0.0, green: 0.73, blue: 0.53))
                .frame(width: 6)
            
            VStack(alignment: .leading, spacing: 4) {
                // Sender label
                Text(isYou ? common("you") : replyMessage.senderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(isYou ? Color(red: 0.0, green: 0.53, blue: 0.73) : Color(red: 0.0, green: 0.73, blue: 0.53))
                    .lineLimit(1)
                
                // Message content
                messageContent(for: replyMessage)
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .lineLimit(4)
                    .multilineTextAlignment(.leading)
            }
            .padding(.leading, 12)
            .padding(.vertical, 8)
            
            Spacer(minLength: 0)
            
            HStack(spacing: 8) {
                // Thumbnail and icon
                thumbnailView(for: replyMessage)
                
                // Close button
                Button(action: {
                    withAnimation {
                        chatRoomVM.replyMessage = nil
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.gray)
                        .frame(width: 24, height: 24)
                }
            }
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            loadThumbnailIfNeeded(for: replyMessage)
        }
    }
    
    // MARK: - Message Content
    @ViewBuilder
    private func messageContent(for message: MessageDataItem) -> some View {
        if message.isViewOnce {
            Text(t(ChatTranslationKeys.CHAT_VIEW_ONCE_MESSAGE))
        } else {
            messageTypeContent(for: message)
        }
    }

    @ViewBuilder
    private func messageTypeContent(for message: MessageDataItem) -> some View {
        switch message.typeMessage {
        case .TEXT:
            Text(message.message.text)
        case .IMAGE:
            Text(t(ChatTranslationKeys.REPLY_PHOTO))
        case .VIDEO, .VIDEO_NOTE:
            Text(t(ChatTranslationKeys.REPLY_VIDEO))
        case .STATUS:
            Text(t(ChatTranslationKeys.REPLY_STATUS))
        case .AUDIO:
            let duration = 123
            let minutes = duration / 60
            let seconds = duration % 60
            Text(String(format: "🎤 Audio %d:%02d", minutes, seconds))
        case .VOICE:
            Text(t(ChatTranslationKeys.REPLY_VOICE_MESSAGE))
        case .CALL_AUDIO:
            Text(t(ChatTranslationKeys.REPLY_VOICE_CALL))
        case .CALL_VIDEO:
            Text(t(ChatTranslationKeys.REPLY_VIDEO_CALL))
        case .MISSING_CALL_AUDIO:
            Text(t(ChatTranslationKeys.REPLY_MISSED_VOICE_CALL))
        case .MISSING_CALL_VIDEO:
            Text(t(ChatTranslationKeys.REPLY_MISSED_VIDEO_CALL))
        case .DOCUMENT:
            Text(t(ChatTranslationKeys.REPLY_DOCUMENT))
        case .CONTACT:
            Text(t(ChatTranslationKeys.REPLY_CONTACT))
        case .LOCATION:
            Text(t(ChatTranslationKeys.REPLY_LOCATION))
        case .POLL:
            Text(t(ChatTranslationKeys.REPLY_POLL))
        case .ISMONEY:
            Text(t(ChatTranslationKeys.REPLY_PAYMENT))
        case .GROUP_CREATED:
            Text(t(ChatTranslationKeys.REPLY_GROUP_CREATED))
        case .GROUP_UPDATED, .USER_ADDED_TO_GROUP, .USER_JOINED_GROUP, .USER_LEFT_GROUP,
             .USER_REMOVED_FROM_GROUP, .USER_PROMOTED_TO_ADMIN, .USER_DEMOTED_FROM_ADMIN:
            // System records — the composer offers no reply action on them, so
            // this arm only exists to keep the switch exhaustive.
            EmptyView()
        case .CHANNEL_INVITE:
            Text(t(ChatTranslationKeys.REPLY_CHANNEL_INVITE))
        }
    }
    
    // MARK: - Thumbnail View
    @ViewBuilder
    private func thumbnailView(for message: MessageDataItem) -> some View {
        let shouldShowThumbnail = shouldShowThumbnail(for: message.typeMessage)
        
        if shouldShowThumbnail {
            ZStack {
                // Thumbnail image or background
                if message.typeMessage == .IMAGE || message.typeMessage == .STATUS,
                   let image = thumbnailImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 44, height: 44)
                        .cornerRadius(4)
                        .clipped()
                } else {
                    Color(white: 0.9)
                        .frame(width: 44, height: 44)
                        .cornerRadius(4)
                }
                
                // Icon overlay
                iconView(for: message.typeMessage)
                    .frame(width: 24, height: 24)
                    .foregroundColor(iconTintColor(for: message.typeMessage))
            }
        }
    }
    
    // MARK: - Icon View
    @ViewBuilder
    private func iconView(for type: MessageTypeProps) -> some View {
        switch type {
        case .VIDEO, .VIDEO_NOTE:
            Image(systemName: "play.circle.fill")
                .foregroundColor(.white)
        case .AUDIO:
            Image(systemName: "mic.fill")
        case .VOICE:
            Image(systemName: "waveform")
        case .CALL_AUDIO:
            Image(systemName: "phone.fill")
        case .CALL_VIDEO:
            Image(systemName: "video.fill")
        case .MISSING_CALL_AUDIO:
            Image(systemName: "phone.down.fill")
        case .MISSING_CALL_VIDEO:
            Image(systemName: "video.slash.fill")
        case .DOCUMENT:
            Image(systemName: "doc.fill")
        case .CONTACT:
            Image(systemName: "person.crop.circle.fill")
        case .LOCATION:
            Image(systemName: "location.fill")
        case .ISMONEY:
            Image(systemName: "banknote.fill")
        default:
            EmptyView()
        }
    }
    
    // MARK: - Helper Methods
    private func shouldShowThumbnail(for type: MessageTypeProps) -> Bool {
        switch type {
        case .IMAGE, .VIDEO, .STATUS, .AUDIO, .VOICE, .CALL_AUDIO, .CALL_VIDEO,
             .MISSING_CALL_AUDIO, .MISSING_CALL_VIDEO, .DOCUMENT,
             .CONTACT, .LOCATION, .ISMONEY:
            return true
        default:
            return false
        }
    }
    
    private func iconTintColor(for type: MessageTypeProps) -> Color {
        switch type {
        case .MISSING_CALL_AUDIO, .MISSING_CALL_VIDEO:
            return .red
        case .ISMONEY:
            return .green
        default:
            return .gray
        }
    }
    
    private func loadThumbnailIfNeeded(for message: MessageDataItem) {
        if message.typeMessage == .IMAGE {
            if let image = uploadVM.getCachedImage(key: message.codeMessage) {
                thumbnailImage = image
            }
            return
        }
        if message.typeMessage == .STATUS {
            let candidates = [
                message.message.thumbnail,
                message.message.image
            ].compactMap { $0 }.filter { !$0.isEmpty }
            for raw in candidates {
                if let image = imageFromDataURL(raw.cleanedBase64) {
                    thumbnailImage = image
                    return
                }
            }
        }
    }
}

extension ReplyViewSwiftUI {
    private func t(_ key: String, args: [String] = []) -> String {
        chatRoomVM.translationService?.resolve(key: key, module: ChatTranslationKeys.MODULE, args: args).value ?? key
    }

    private func common(_ key: String) -> String {
        chatRoomVM.translationService?.resolve(key: key, module: ChatTranslationKeys.COMMON_MODULE).value ?? key.capitalized
    }
}

