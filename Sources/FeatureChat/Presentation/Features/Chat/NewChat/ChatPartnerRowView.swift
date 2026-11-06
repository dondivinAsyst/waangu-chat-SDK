//
//  ChatPartnerRowView.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 12.01.2025.
//

import SwiftUI
import WaanguSharedUI



struct ChatPartnerRowView<Content: View>: View {
    private let user: UserContactProps
    private let trailingItems: Content
    
    init(user: UserContactProps, @ViewBuilder trailingItems: () -> Content = { EmptyView() }) {
        self.user = user
        self.trailingItems = trailingItems()
    }
    
    var body: some View {
        HStack(spacing: 12) {
            CircularProfileImageView(user.avatar, size: .xSmall)
                .frame(width: 45, height: 45)
            
            VStack(alignment: .leading, spacing: 3) {
                Text(user.name)
                    .font(.body)
                    .foregroundStyle(.primary)
                
                // ✅ Enhanced bio/subtitle showing description or phone
                Text(bioText)
                    .font(.subheadline)
                    .foregroundStyle(.gray)
                    .lineLimit(1)
            }
            
            Spacer()
            
            trailingItems
        }
        .padding(.vertical, 4)
    }
    
    /// Returns the appropriate bio text (description or phone number)
    private var bioText: String {
        if !user.description.isEmpty && user.description != "No status" {
            return user.description
        } else if !user.phone.isEmpty {
            return user.phone
        } else {
            return "Hey there! I am using Waangu"
        }
    }
}

//#Preview {
//    ChatPartnerRowView(user: .placeholder)
//}
