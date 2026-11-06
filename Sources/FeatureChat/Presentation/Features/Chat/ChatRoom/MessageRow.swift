////
////  MessageRow.swift
////  Pods
////
////  Created by Don divin on 2/6/26.
////
//
//
//@available(iOS 17.0, *)
//struct MessageRow: View {
//
//    let message: MessageDataItem
//    let uploadVM: UploadViewModel
//    let imageNamespace: Namespace.ID
//    let isHighlighted: Bool
//    let isSelectionMode: Bool
//
//    let onSwipeReply: () -> Void
//    let onReplyTap: (String) -> Void
//    let onLongPress: () -> Void
//
//    @State private var dragOffset: CGFloat = 0
//
//    var body: some View {
//        HStack {
//            if message.direction == .received {
//                bubble
//                Spacer()
//            } else {
//                Spacer()
//                bubble
//            }
//        }
//        .padding(.horizontal, 12)
//    }
//
//    private var bubble: some View {
//        VStack(alignment: .leading, spacing: 6) {
//
//            if let reply = message.replyTo {
//                ReplyPreviewView(reply: reply) {
//                    onReplyTap(reply.messageID)
//                }
//            }
//
//            MessageContentView(
//                message: message,
//                uploadVM: uploadVM,
//                namespace: imageNamespace
//            )
//        }
//        .padding(10)
//        .background(background)
//        .clipShape(RoundedRectangle(cornerRadius: 18))
//        .offset(x: dragOffset)
//        .gesture(swipeGesture)
//        .onLongPressGesture(perform: onLongPress)
//    }
//
//    private var background: some View {
//        ZStack {
//            if isHighlighted {
//                Color.green.opacity(0.15)
//            }
//            message.direction == .received
//                ? Color(.systemGray5)
//                : Color.green
//        }
//    }
//
//    private var swipeGesture: some Gesture {
//        DragGesture()
//            .onChanged {
//                let value = message.direction == .received
//                    ? max(0, $0.translation.width)
//                    : min(0, $0.translation.width)
//                dragOffset = value * 0.4
//            }
//            .onEnded {
//                if abs(dragOffset) > 80 {
//                    Haptic.impact(.light)
//                    onSwipeReply()
//                }
//                dragOffset = 0
//            }
//    }
//}
