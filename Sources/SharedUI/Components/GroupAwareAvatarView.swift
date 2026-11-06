//
//  GroupAwareAvatarView.swift
//  SharedUI
//
//  Avatar component that visually differentiates between individual and group chats
//  - Individual chats: Circular avatar
//  - Group chats: Rounded square avatar (WhatsApp-style)
//

import SwiftUI
import SDWebImageSwiftUI

public enum AvatarSize {
    case xxSmall
    case xSmall
    case small
    case medium
    case large
    case xLarge
    
    var dimension: CGFloat {
        switch self {
        case .xxSmall: return 32
        case .xSmall: return 48
        case .small: return 56
        case .medium: return 64
        case .large: return 80
        case .xLarge: return 120
        }
    }
    
    var groupCornerRadius: CGFloat {
        switch self {
        case .xxSmall: return 8
        case .xSmall: return 12
        case .small: return 14
        case .medium: return 16
        case .large: return 20
        case .xLarge: return 28
        }
    }
    
    var iconSize: CGFloat {
        switch self {
        case .xxSmall: return 16
        case .xSmall: return 20
        case .small: return 24
        case .medium: return 28
        case .large: return 36
        case .xLarge: return 52
        }
    }
}

@available(iOS 15.0, *)
public struct GroupAwareAvatarView: View {
    let imageUrl: String?
    let isGroup: Bool
    let size: AvatarSize
    let onClick: (() -> Void)?
    
    public init(
        imageUrl: String?,
        isGroup: Bool,
        size: AvatarSize,
        onClick: (() -> Void)? = nil
    ) {
        self.imageUrl = imageUrl
        self.isGroup = isGroup
        self.size = size
        self.onClick = onClick
    }
    
    public var body: some View {
        Button(action: {
            onClick?()
        }) {
            if isGroup {
                groupAvatarView
            } else {
                individualAvatarView
            }
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(onClick == nil)
    }
    
    // MARK: - Individual Avatar (Circular)
    
    private var individualAvatarView: some View {
        ZStack {
            Circle()
                .fill(Color.gray.opacity(0.2))
                .frame(width: size.dimension, height: size.dimension)
            
            if let urlString = imageUrl, !urlString.isEmpty {
                WebImage(url: URL(string: urlString))
                    .resizable()
//                    .placeholder {
//                        fallbackIcon(systemName: "person.fill")
//                    }
                    .indicator(.activity)
                    .scaledToFill()
                    .frame(width: size.dimension, height: size.dimension)
                    .clipShape(Circle())
            } else {
                fallbackIcon(systemName: "person.fill")
            }
        }
    }
    
    // MARK: - Group Avatar (Rounded Square)
    
    private var groupAvatarView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size.groupCornerRadius)
                .fill(Color.gray.opacity(0.2))
                .frame(width: size.dimension, height: size.dimension)
            
            if let urlString = imageUrl, !urlString.isEmpty {
                WebImage(url: URL(string: urlString))
                    .resizable()
//                    .placeholder {
//                        fallbackIcon(systemName: "person.3.fill")
//                    }
                    .indicator(.activity)
                    .scaledToFill()
                    .frame(width: size.dimension, height: size.dimension)
                    .clipShape(RoundedRectangle(cornerRadius: size.groupCornerRadius))
            } else {
                fallbackIcon(systemName: "person.3.fill")
            }
        }
    }
    
    // MARK: - Fallback Icon
    
    private func fallbackIcon(systemName: String) -> some View {
        Image(systemName: systemName)
            .resizable()
            .scaledToFit()
            .frame(width: size.iconSize, height: size.iconSize)
            .foregroundColor(.gray)
    }
}

// MARK: - Preview

@available(iOS 15.0, *)
struct GroupAwareAvatarView_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            Text("Individual Chats (Circular)")
                .font(.headline)
            
            HStack(spacing: 16) {
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: false,
                    size: .xSmall
                )
                
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: false,
                    size: .small
                )
                
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: false,
                    size: .medium
                )
            }
            
            Divider()
            
            Text("Group Chats (Rounded Square)")
                .font(.headline)
            
            HStack(spacing: 16) {
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: true,
                    size: .xSmall
                )
                
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: true,
                    size: .small
                )
                
                GroupAwareAvatarView(
                    imageUrl: nil,
                    isGroup: true,
                    size: .medium
                )
            }
        }
        .padding()
    }
}
