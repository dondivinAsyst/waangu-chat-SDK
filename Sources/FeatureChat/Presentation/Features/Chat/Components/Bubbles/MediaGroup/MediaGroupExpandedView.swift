////
////  MediaGroupExpandedView.swift
////  Pods
////
////  Created by Don divin on 2/12/26.
////
//
//import SwiftUI
//
//@available(iOS 16.0, *)
//struct MediaGroupExpandedView: View {
//    let messages: [MessageDataItem]
//    @ObservedObject var chatVM: ChatRoomViewModel
//    @ObservedObject var uploadVM: UploadViewModel
//    @Environment(\.dismiss) private var dismiss
//
//    var body: some View {
//        NavigationView {
//            ScrollView {
//                LazyVStack(spacing: 2) {
//                    ForEach(messages) { message in
//                        expandedImageRow(message)
//                    }
//                }
//            }
//            .background(Color.black)
//            .navigationBarTitleDisplayMode(.inline)
//            .toolbar {
//                ToolbarItem(placement: .topBarLeading) {
//                    Button {
//                        dismiss()
//                    } label: {
//                        Image(systemName: "chevron.left")
//                            .foregroundColor(.white)
//                            .fontWeight(.semibold)
//                    }
//                }
//                ToolbarItem(placement: .principal) {
//                    VStack(spacing: 2) {
//                        Text(messages.first?.senderName ?? "")
//                            .font(.subheadline)
//                            .fontWeight(.semibold)
//                            .foregroundColor(.white)
//                        Text("\(messages.count) media")
//                            .font(.caption)
//                            .foregroundColor(.gray)
//                    }
//                }
//            }
//            .toolbarBackground(Color.black, for: .navigationBar)
//            .toolbarBackground(.visible, for: .navigationBar)
//        }
//    }
//
//    @ViewBuilder
//    private func expandedImageRow(_ message: MessageDataItem) -> some View {
//        VStack(spacing: 0) {
//            // Full-width image
//            if let uiImage = message.message.UIimage {
//                Image(uiImage: uiImage)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .frame(maxWidth: .infinity)
//                    .background(Color.black)
//                    .contentShape(Rectangle())
//                    .onTapGesture {
//                        dismiss()
//                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
//                            let frame = CGRect(x: 0, y: 0, width: UIScreen.main.bounds.width, height: 300)
//                            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
//                                chatVM.onTapImage(message, frame: frame)
//                            }
//                        }
//                    }
//            } else if let thumbnail = message.message.thumbnail,
//                      let image = decodeBase64ToUIImage(thumbnail) {
//                Image(uiImage: image)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .frame(maxWidth: .infinity)
//                    .background(Color.black)
//            } else {
//                Rectangle()
//                    .fill(Color.gray.opacity(0.3))
//                    .frame(height: 200)
//                    .overlay(
//                        Image(systemName: "photo")
//                            .font(.largeTitle)
//                            .foregroundColor(.gray)
//                    )
//            }
//
//            // Caption if present
//            if !message.message.text.isEmpty {
//                HStack {
//                    Text(message.message.text)
//                        .foregroundColor(.white)
//                        .font(.body)
//                    Spacer()
//                }
//                .padding(.horizontal, 12)
//                .padding(.vertical, 8)
//                .background(Color.black)
//            }
//
//            // Timestamp bar
//            HStack {
//                Text(message.senderName)
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                Spacer()
//                Text(message.displayTime)
//                    .font(.caption)
//                    .foregroundColor(.gray)
//                if message.direction == .sent {
//                    MessageStatusIcon(messageStatus: message.status)
//                }
//            }
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(Color.black)
//        }
//    }
//}
