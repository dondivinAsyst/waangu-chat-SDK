//
//  SelectedChatPartnerView.swift
//  WhatsAppClone
//
//  Created by Muharrem Efe Çayırbahçe on 13.01.2025.
//

import SwiftUI
import WaanguSharedUI

struct SelectedChatPartnerView: View {
    let users: [UserContactProps]
    let onTapHandler: (_ user: UserContactProps) -> Void
    
    var body: some View {
        ScrollView(.horizontal , showsIndicators: false) {
            HStack {
                ForEach(users) { item in
                    chatPartnerView(item)
                }
            }
        }
    }
    
    private func chatPartnerView(_ user: UserContactProps) -> some View {
        VStack {
            CircularProfileImageView(user.avatar, size: .medium)
                .overlay(alignment: .topTrailing) {
                    cancelButton(user)
                }
            
            Text(user.name)
                
        }
    }
    
    private func cancelButton(_ user: UserContactProps) -> some View {
        Button {
            onTapHandler(user)
        } label: {
            Image(systemName: "xmark")
                .imageScale(.small)
                .foregroundColor(.white)
//                .fontWeight(.semibold)
                .padding(5)
                .background(Color(.systemGray2))
                .clipShape(Circle())
        }
    }
}

//#Preview {
//    SelectedChatPartnerView(users: UserItem.placeholders) { user in
//        
//    }
//}
