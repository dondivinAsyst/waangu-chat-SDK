////
////  MessageCellSwiftUIView.swift
////  Pods
////
////  Created by Don divin on 2/6/26.
////
//
//
//import SwiftUI
//
//@available(iOS 16.0, *)
//struct MessageCellSwiftUIView: View {
//    let message: MessageDataItem
//    let channel: ChannelItem
//    let showSenderName: Bool
//    let uploadVM: UploadViewModel
//    let chatVM: ChatRoomViewModel
//    let imageTransitionNamespace: Namespace.ID
//    
//    let isSelectionMode: Bool
//    let isSelected: Bool
//    let isHighlighted: Bool
//    let highlightOpacity: Double
//    
//    var onSelectMessage: (Bool) -> Void
//    
//    var body: some View {
//        HStack(alignment: .bottom, spacing: 8) {
//            if message.direction == .received {
//                receivedMessageContent
//                Spacer(minLength: 60)
//            } else {
//                Spacer(minLength: 60)
//                sentMessageContent
//            }
//        }
//        .padding(.horizontal, 12)
//        .padding(.vertical, 4)
//        .background(highlightBackground)
//        .contentShape(Rectangle())
//    }
//    
//    // MARK: - Received Message
//    
//    private var receivedMessageContent: some View {
//        HStack(alignment: .bottom, spacing: 8) {
//            if isSelectionMode {
//                selectionCheckbox
//            }
//            
//            VStack(alignment: .leading, spacing: 4) {
//                if showSenderName {
//                    Text(message.senderName)
//                        .font(.caption)
//                        .foregroundColor(.gray)
//                }
//                
//                messageContentView
//                    .padding(10)
//                    .background(Color.white)
//                    .cornerRadius(12)
//                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
//            }
//        }
//    }
//    
//    // MARK: - Sent Message
//    
//    private var sentMessageContent: some View {
//        HStack(alignment: .bottom, spacing: 8) {
//            VStack(alignment: .trailing, spacing: 4) {
//                messageContentView
//                    .padding(10)
//                    .background(Color.green.opacity(0.2))
//                    .cornerRadius(12)
//                    .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
//            }
//            
//            if isSelectionMode {
//                selectionCheckbox
//            }
//        }
//    }
//    
//    // MARK: - Message Content
//    
//    @ViewBuilder
//    private var messageContentView: some View {
//        VStack(alignment: message.direction == .received ? .leading : .trailing, spacing: 4) {
//            // Reply preview if exists
//            if let replyTo = message.reply {
//                switch replyTo {
//                case .message(let msg):
//                    if msg != nil {
//                        replyPreview(for: msg)
//                    }
//                   
//                }
//               
//            }
//            
//            // Main content
//            switch message.typeMessage {
//            case .TEXT:
//                if let text = message.message.text as? String {
//                    Text(text)
//                        .font(.body)
//                        .foregroundColor(.primary)
//                }
//            case .IMAGE , .VIDEO:
//                if let thumbnailURL = message.message.thumbnail {
//                    AsyncImage(url: URL(string: thumbnailURL)) { image in
//                        image
//                            .resizable()
//                            .aspectRatio(contentMode: .fill)
//                    } placeholder: {
//                        ProgressView()
//                    }
//                    .frame(maxWidth: 250, maxHeight: 300)
//                    .cornerRadius(8)
//                }
//            case .DOCUMENT:
//                EmptyView()
//            case .AUDIO:
//                audioMessageView
//            case .VOICE:
//                EmptyView()
//            case .CONTACT:
//                EmptyView()
//            case .LOCATION:
//                EmptyView()
//            case .MISSING_CALL_AUDIO, .MISSING_CALL_VIDEO, .CALL_AUDIO, .CALL_VIDEO:
//                BubbleCallView(message: message, isSelectionMode: isSelectionMode)
//            case .ISMONEY:
//                EmptyView()
//          
//            default:
//                Text("Unsupported message type")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//            }
//            
//            // Timestamp and status
//            HStack(spacing: 4) {
//                Text(message.createdAt.formatted(date: .omitted, time: .shortened))
//                    .font(.caption2)
//                    .foregroundColor(.gray)
//                
//                if message.direction == .sent {
//                    messageStatusIcon
//                }
//            }
//            
////            // Reactions
////            if let reactions = message.reactions, !reactions.isEmpty {
////                reactionsView(reactions: reactions)
////            }
//        }
//    }
//    
//    // MARK: - Reply Preview
//    
//    private func replyPreview(for replyMessage: MessageDataItem?) -> some View {
//        VStack(alignment: .leading, spacing: 2) {
//            Text(replyMessage?.senderName ?? "")
//                .font(.caption)
//                .fontWeight(.semibold)
//                .foregroundColor(.blue)
//            
//            Text(replyMessage?.message.text ?? "")
//                .font(.caption)
//                .foregroundColor(.gray)
//                .lineLimit(2)
//        }
//        .padding(8)
//        .background(Color.black.opacity(0.5))
//        .cornerRadius(8)
//    }
//    
//    // MARK: - Audio Message
//    
//    private var audioMessageView: some View {
//        HStack(spacing: 12) {
//            Image(systemName: "play.circle.fill")
//                .font(.title2)
//                .foregroundColor(.blue)
//            
//            VStack(alignment: .leading, spacing: 4) {
//                Text("Voice Message")
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                
//                if let duration = (message.message.audio != nil) ? 123 : 0 {
//                    Text(formatDuration(TimeInterval(duration)))
//                        .font(.caption2)
//                        .foregroundColor(.gray)
//                }
//            }
//            
//            Spacer()
//        }
//        .padding(8)
//    }
//    
//    // MARK: - Reactions View
//    
////    private func reactionsView(reactions: [Reaction]) -> some View {
////        HStack(spacing: 4) {
////            ForEach(reactions, id: \.id) { reaction in
////                HStack(spacing: 2) {
////                    Text(reaction.emoji)
////                        .font(.caption)
////                    
////                    if reaction.count > 1 {
////                        Text("\(reaction.count)")
////                            .font(.caption2)
////                            .foregroundColor(.gray)
////                    }
////                }
////                .padding(.horizontal, 6)
////                .padding(.vertical, 2)
////                .background(Color.gray.opacity(0.2))
////                .cornerRadius(10)
////            }
////        }
////    }
//    private func reactionsView(reactions: [Reaction]) -> some View {
//        HStack(spacing: 4) {
//            ForEach(reactions, id: \.self) { reaction in
//                Text(reaction.emoji)
//                    .font(.caption)
//                    .padding(.horizontal, 6)
//                    .padding(.vertical, 2)
//                    .background(Color.gray.opacity(0.2))
//                    .cornerRadius(10)
//            }
//        }
//    }
//
//    
//    // MARK: - Message Status Icon
//    
//    @ViewBuilder
//    private var messageStatusIcon: some View {
//        switch message.status {
//        case .PENDING:
//            Image(systemName: "clock")
//                .font(.caption2)
//                .foregroundColor(.gray)
//            
//        case .UNSEEN:
//            Image(systemName: "checkmark")
//                .font(.caption2)
//                .foregroundColor(.gray)
//            
//        case .DELIVERED:
//            Image(systemName: "checkmark.circle")
//                .font(.caption2)
//                .foregroundColor(.gray)
//            
//        case .SEEN:
//            Image(systemName: "checkmark.circle.fill")
//                .font(.caption2)
//                .foregroundColor(.blue)
//            
//     default:
//            Image(systemName: "exclamationmark.circle")
//                .font(.caption2)
//                .foregroundColor(.red)
//        }
//    }
//    
//    // MARK: - Selection Checkbox
//    
//    private var selectionCheckbox: some View {
//        Button(action: {
//            onSelectMessage(!isSelected)
//        }) {
//            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
//                .font(.title3)
//                .foregroundColor(isSelected ? .blue : .gray)
//        }
//    }
//    
//    // MARK: - Highlight Background
//    
//    @ViewBuilder
//    private var highlightBackground: some View {
//        if isHighlighted {
//            Color.green.opacity(0.08 * highlightOpacity)
//                .cornerRadius(8)
//        }
//    }
//    
//    // MARK: - Helpers
//    
//    private func formatDuration(_ seconds: TimeInterval) -> String {
//        let minutes = Int(seconds) / 60
//        let secs = Int(seconds) % 60
//        return String(format: "%d:%02d", minutes, secs)
//    }
//}
//
//// MARK: - Supporting Types
//
////enum MessageDirection {
////    case sent
////    case received
////}
////
////enum MessageStatus {
////    case pending
////    case sent
////    case delivered
////    case read
////    case failed
////}
////
////struct Reaction {
////    let emoji: String
////    let count: Int
////    let users: [String]
////}
//
//#if DEBUG
////// Temporary local conformance to help SwiftUI identify reactions.
////extension Reaction: Identifiable, Hashable {
////    public var id: String {
////        // Combine emoji and count to form a stable id for this view layer.
////        "\(emoji)-\(count)"
////    }
////    public static func == (lhs: Reaction, rhs: Reaction) -> Bool {
////        lhs.emoji == rhs.emoji && lhs.count == rhs.count
////    }
////    public func hash(into hasher: inout Hasher) {
////        hasher.combine(emoji)
////        hasher.combine(count)
////    }
////}
//#endif
